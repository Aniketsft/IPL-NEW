using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Threading.Tasks;
using System.Xml.Linq;
using System.Xml.XPath;
using EnterpriseAuth.Api.Core.Application.DTOs;
using EnterpriseAuth.Api.Core.Application.Interfaces;
using EnterpriseAuth.Api.Core.Domain.Entities;
using EnterpriseAuth.Api.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using System.Text.Json;
using Dapper;
using Microsoft.Data.SqlClient;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;

namespace EnterpriseAuth.Api.Core.Application.Services
{
    public class SageX3SoapService : ISageX3SoapService
    {
        private readonly ScanProductionDbContext _context;
        private readonly HttpClient _httpClient;
        private readonly string _soapUrl;
        private readonly string _poolAlias;
        private readonly string _username;
        private readonly string _password;
        private readonly string _innodisConnectionString;
        private readonly IHttpContextAccessor _httpContextAccessor;
        private readonly IServiceScopeFactory _serviceScopeFactory;

        public SageX3SoapService(
            ScanProductionDbContext context, 
            IConfiguration configuration, 
            IHttpClientFactory httpClientFactory,
            IHttpContextAccessor httpContextAccessor,
            IServiceScopeFactory serviceScopeFactory)
        {
            _context = context;
            _httpClient = httpClientFactory.CreateClient();
            _httpClient.Timeout = TimeSpan.FromMinutes(10);
            _httpContextAccessor = httpContextAccessor;
            _serviceScopeFactory = serviceScopeFactory;
            
            var settings = configuration.GetSection("X3SoapService");
            _soapUrl = settings["Url"] ?? "http://192.168.120.6:8124/soap-generic/syracuse/collaboration/syracuse/CAdxWebServiceXmlCC";
            _poolAlias = settings["PoolAlias"] ?? "IMPORT-EXPORT";
            _username = settings["Username"] ?? "ADMIN";
            _password = settings["Password"] ?? "PASSWORD_HERE";
            _innodisConnectionString = configuration.GetConnectionString("Innodis")
                ?? throw new InvalidOperationException("Innodis connection string is missing.");
        }

        private async Task InsertSoapAuditAsync(
            string actionName,
            string? identifier,
            string requestPayload,
            string responsePayload,
            bool isSuccess,
            string? errorMessage = null)
        {
            try
            {
                var httpContext = _httpContextAccessor.HttpContext;
                
                var username = httpContext?.User?.FindFirst("username")?.Value 
                    ?? httpContext?.User?.Identity?.Name 
                    ?? "system";

                string? deviceId = null;
                if (httpContext != null && httpContext.Request.Headers.TryGetValue("X-Device-Id", out var deviceIdVal))
                {
                    deviceId = deviceIdVal.ToString();
                }

                var auditRecord = new X3SoapAudit
                {
                    Id = Guid.NewGuid(),
                    ActionName = actionName,
                    Identifier = identifier,
                    RequestPayload = requestPayload,
                    ResponsePayload = responsePayload,
                    IsSuccess = isSuccess,
                    ErrorMessage = errorMessage?.Length > 2000 ? errorMessage.Substring(0, 2000) : errorMessage,
                    TriggeredBy = username,
                    DeviceId = deviceId,
                    CreatedAt = DateTime.UtcNow
                };

                using (var scope = _serviceScopeFactory.CreateScope())
                {
                    var dbContext = scope.ServiceProvider.GetRequiredService<ScanProductionDbContext>();
                    dbContext.X3SoapAudits.Add(auditRecord);
                    await dbContext.SaveChangesAsync();
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Audit Error] Failed to write SOAP audit: {ex.Message}");
            }
        }

        public async Task<EndOfDayResult> ProcessEndOfDayAsync()
        {
            var result = new EndOfDayResult();

            // 1. Simple SQL Query to get unique SO numbers
            // 1. Fetch unique SO numbers directly from SQL to minimize memory usage
            var soNumbers = await _context.Database
                .SqlQuery<string>($"SELECT DISTINCT ZSOHNUM_0 AS Value FROM Staging WHERE IsProcessed = 0 AND ZSOHNUM_0 IS NOT NULL")
                .ToListAsync();

            if (!soNumbers.Any())
            {
                return result;
            }

            result.TotalProcessed = soNumbers.Count;

            // 2. Process each SO number individually
            foreach (var soNumber in soNumbers)
            {
                // Each SO is processed in its own transaction for robustness
                using var transaction = await _context.Database.BeginTransactionAsync();
                try
                {
                    var records = await _context.StagingRecords
                        .Where(r => !r.IsProcessed && r.ZSOHNUM_0 == soNumber)
                        .ToListAsync();

                    var importResult = await ImportSalesOrderAsync(soNumber, records);
                    result.Results.Add(importResult);

                    if (importResult.Success)
                    {
                        result.SuccessCount++;
                        
                        // Mark staging records as processed
                        foreach (var record in records)
                        {
                            record.IsProcessed = true;
                            record.ZVACITM_0 = importResult.RequestNumber;
                        }

                        // Also mark the normalized SalesOrder as processed
                        var normalizedOrder = await _context.SalesOrders
                            .FirstOrDefaultAsync(o => o.SourceOrderId == soNumber);
                        if (normalizedOrder != null)
                        {
                            normalizedOrder.IsProcessed = true;
                            normalizedOrder.UpdatedAt = DateTime.UtcNow;
                        }

                        await _context.SaveChangesAsync();
                        await transaction.CommitAsync();
                    }
                    else
                    {
                        result.FailureCount++;
                        // We still allow the rest of the batch to continue
                    }
                }
                catch (Exception ex)
                {
                    await transaction.RollbackAsync();
                    result.FailureCount++;
                    result.Results.Add(new X3ImportResult 
                    { 
                        Identifier = soNumber, 
                        Success = false, 
                        TechnicalError = $"Database/Processing Error: {ex.Message}" 
                    });
                }
            }

            return result;
        }

        public async Task<X3ImportResult> ImportSalesOrderAsync(string soNumber, List<Staging> records)
        {
            var result = new X3ImportResult { Identifier = soNumber };
            string soapEnvelope = string.Empty;
            string responseXml = string.Empty;

            try
            {
                // 1. Find the Header record (H) and Lines (L)
                var header = records.FirstOrDefault(r => r.ZREC_0 == "H");
                var lines = records.Where(r => r.ZREC_0 == "L").ToList();

                if (header == null)
                {
                    header = records.FirstOrDefault();
                }

                // 2. Build the I_FILE content
                var fileBuilder = new StringBuilder();
                
                string shiDate = header?.ZSHIDAT_0?.ToString("yyyyMMdd") ?? "";
                string delDate = header?.ZDLVDAT_0?.ToString("yyyyMMdd") ?? "";

                // Header Record: H;Template;Site1;Site2;;Customer;Currency;ShiDate;DelDate;Flag;;Location;Lorry
                fileBuilder.Append($"H;{header?.ZSDHTYP_0};{header?.ZSALFCY_0};{header?.ZSTOFCY_0};;{header?.ZBPCORD_0};{header?.ZSUR_0};{shiDate};{delDate};{header?.ZCFMFLG_0};;{header?.ZLOC_0};{header?.ZLOCFCY_0}|");

                // Line Records: L;SONo;LineNo;ItemCode;Description;Unit;Qty;Lot
                foreach (var line in lines)
                {
                    string qty = line.ZQTY_0.ToString("F3"); // 3 decimal places
                    fileBuilder.Append($"L;{line.ZSOHNUM_0};{line.ZSOPLIN_0};{line.ZITMREF_0};{line.ZITMDES_0};{line.ZSAU_0};{qty};{line.LotNumber}|");
                }

                fileBuilder.Append("END");

                // 3. Construct the JSON for the CDATA block (Manual construction to avoid character escaping)
                string iFile = fileBuilder.ToString();
                string inputXmlJson = "{\"GRP1\":{" +
                                      "\"I_MODIMP\":\"ZSDH2\"," +
                                      "\"I_AOWSTA\":\"NO\"," +
                                      "\"I_EXEC\":\"REALTIME\"," +
                                      "\"I_RECORDSEP\":\"|\"," +
                                      "\"I_FILE\":\"" + iFile.Replace("\"", "\\\"") + "\"" +
                                      "}}";

                // 4. Construct the SOAP Envelope
                soapEnvelope = $@"<soapenv:Envelope xmlns:xsi=""http://www.w3.org/2001/XMLSchema-instance"" xmlns:xsd=""http://www.w3.org/2001/XMLSchema"" xmlns:soapenv=""http://schemas.xmlsoap.org/soap/envelope/"" xmlns:wss=""http://www.adonix.com/WSS"">
   <soapenv:Header/>
   <soapenv:Body>
      <wss:run soapenv:encodingStyle=""http://schemas.xmlsoap.org/soap/encoding/"">
         <callContext xsi:type=""wss:CAdxCallContext"">
            <codeLang xsi:type=""xsd:string"">ENG</codeLang>
            <poolAlias xsi:type=""xsd:string"">{_poolAlias}</poolAlias>
            <poolId xsi:type=""xsd:string""></poolId>
            <requestConfig xsi:type=""xsd:string""></requestConfig>
         </callContext>
         <publicName xsi:type=""xsd:string"">AOWSIMPORT</publicName>
            <inputXml xsi:type=""xsd:string"">
                  <![CDATA[{inputXmlJson}]]>
          </inputXml>
      </wss:run>
   </soapenv:Body>
</soapenv:Envelope>";

                // 5. Send Request
                Console.WriteLine("====== SAGE X3 SOAP REQUEST ======");
                Console.WriteLine(soapEnvelope);
                Console.WriteLine("==================================");

                var request = new HttpRequestMessage(HttpMethod.Post, _soapUrl);
                request.Content = new StringContent(soapEnvelope, Encoding.UTF8, "text/xml");
                
                // Set Basic Authentication
                var authToken = Convert.ToBase64String(Encoding.ASCII.GetBytes($"{_username}:{_password}"));
                request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Basic", authToken);

                // Syracuse can be picky about SOAPAction casing
                request.Headers.Add("SOAPAction", "");
                request.Headers.Add("soapAction", ""); 

                var response = await _httpClient.SendAsync(request);
                responseXml = await response.Content.ReadAsStringAsync();

                if (!response.IsSuccessStatusCode)
                {
                    result.Success = false;
                    result.TechnicalError = $"HTTP {response.StatusCode}: {responseXml}";
                    await InsertSoapAuditAsync("ImportSalesOrder", soNumber, soapEnvelope, responseXml, false, result.TechnicalError);
                    return result;
                }

                // 6. Parse Response
                var parsedResult = ParseSoapResponse(responseXml, result);
                
                // Override success based on specific delivery validation string
                bool hasDeliveryValidated = parsedResult.Messages.Any(m => m.Contains("delivery validated", StringComparison.OrdinalIgnoreCase)) || 
                                            responseXml.Contains("delivery validated", StringComparison.OrdinalIgnoreCase);
                
                parsedResult.Success = hasDeliveryValidated;
                
                await InsertSoapAuditAsync("ImportSalesOrder", soNumber, soapEnvelope, responseXml, parsedResult.Success, parsedResult.Success ? null : string.Join(" | ", parsedResult.Messages));
                return parsedResult;
            }
            catch (Exception ex)
            {
                result.Success = false;
                result.TechnicalError = ex.Message;
                await InsertSoapAuditAsync("ImportSalesOrder", soNumber, soapEnvelope, responseXml, false, ex.Message);
                return result;
            }
        }

        public async Task<EndOfDayResult> ProcessProductionEodAsync()
        {
            var result = new EndOfDayResult();

            // 1. Fetch unique Work Order numbers directly from SQL
            var workOrders = await _context.Database
                .SqlQuery<string>($"SELECT DISTINCT WorkOrderNumber AS Value FROM StagingEod WHERE IsProcessed = 0 AND WorkOrderNumber IS NOT NULL")
                .ToListAsync();

            if (!workOrders.Any())
            {
                return result;
            }

            result.TotalProcessed = workOrders.Count;

            // 2. Process each Work Order individually
            foreach (var workOrder in workOrders)
            {
                using var transaction = await _context.Database.BeginTransactionAsync();
                try
                {
                    var records = await _context.StagingEodRecords
                        .Where(r => !r.IsProcessed && r.WorkOrderNumber == workOrder)
                        .ToListAsync();

                    /*
                    // Fetch missing BOM components dynamically for this specific Work Order
                    var missingBomCodes = await GetMissingBomProductCodesAsync(workOrder);

                    // ── Append missing BOM products to this Work Order's batch ──
                    // These are virtual in-memory records — never written to StagingEod.
                    if (missingBomCodes.Any())
                    {
                        var today = DateTime.Today;
                        var virtualRecords = missingBomCodes.Select(code => new StagingEod
                        {
                            WorkOrderNumber           = workOrder,
                            ProductCode               = code,
                            TotalManufacturedQuantity = 0m,
                            EaQuantity                = 0m,
                            DateOfManufacturing       = today,
                            ExpiryDate                = today.AddDays(5),
                            Unit                      = "KG",
                            Location                  = "IPLCH",
                            ItemStatus                = "A",
                            Location2                 = "LPOULTRY",  // CCE_0
                            Location3                 = "CHILLED"    // CCE_1
                        }).ToList();

                        Console.WriteLine($"[EOD] Appending {virtualRecords.Count} missing BOM components (qty=0) to Work Order [{workOrder}] SOAP batch.");
                        records.AddRange(virtualRecords);
                    }
                    */

                    // Batch records into chunks of 50 to prevent Sage X3/Syracuse timeouts
                    const int batchSize = 50;
                    for (int i = 0; i < records.Count; i += batchSize)
                    {
                        var batch = records.Skip(i).Take(batchSize).ToList();
                        var importResult = await ImportProductionEodAsync(workOrder, batch);
                        result.Results.Add(importResult);

                        if (importResult.Success)
                        {
                            // Only mark REAL (tracked) records as processed — virtual records have no Id
                            result.SuccessCount += batch.Count;
                            foreach (var record in batch.Where(r => r.Id != Guid.Empty && _context.Entry(r).State != Microsoft.EntityFrameworkCore.EntityState.Detached))
                            {
                                record.IsProcessed = true;
                            }

                            await _context.SaveChangesAsync();
                        }
                        else
                        {
                            // TRACE LOG SALVAGE: Parse logs to find successfully created tracking records in the failed batch.
                            // Sage X3 output format:
                            // "Production reporting on WO : IPLWO260400001 33519"
                            // "IPL Creation of WO tracking IPLTK260500002"
                            var successfulProducts = new HashSet<string>();
                            string currentProduct = null;
                            
                            foreach (var msg in importResult.Messages)
                            {
                                if (msg.StartsWith("Production reporting on WO : "))
                                {
                                    var parts = msg.Split(' ');
                                    currentProduct = parts.LastOrDefault();
                                }
                                else if (msg.Trim().StartsWith("Completed qty:", StringComparison.OrdinalIgnoreCase))
                                {
                                    if (!string.IsNullOrEmpty(currentProduct))
                                    {
                                        successfulProducts.Add(currentProduct);
                                    }
                                }
                            }

                            if (successfulProducts.Any())
                            {
                                int salvagedCount = 0;
                                foreach (var record in batch.Where(r => r.Id != Guid.Empty && _context.Entry(r).State != Microsoft.EntityFrameworkCore.EntityState.Detached))
                                {
                                    if (successfulProducts.Contains(record.ProductCode))
                                    {
                                        record.IsProcessed = true;
                                        salvagedCount++;
                                    }
                                }
                                
                                result.SuccessCount += salvagedCount;
                                int failedCount = batch.Count - salvagedCount;
                                result.FailureCount += failedCount;
                                
                                if (failedCount == 0 && salvagedCount > 0)
                                {
                                    importResult.Success = true;
                                }
                                
                                await _context.SaveChangesAsync();
                            }
                            else
                            {
                                result.FailureCount += batch.Count;
                            }
                        }
                    }

                    await transaction.CommitAsync();
                }
                catch (Exception ex)
                {
                    await transaction.RollbackAsync();
                    result.FailureCount++;
                    result.Results.Add(new X3ImportResult 
                    { 
                        Identifier = workOrder, 
                        Success = false, 
                        TechnicalError = $"Database/Processing Error: {ex.Message}" 
                    });
                }
            }

            return result;
        }

        /*
        /// <summary>
        /// Queries the Sage X3 BOM tables to find component products that are missing
        /// from today's StagingEod entries for the specific Work Order. These will be
        /// appended to the SOAP payload with qty=0 so Sage X3 always receives the complete BOM set.
        /// </summary>
        private async Task<IEnumerable<string>> GetMissingBomProductCodesAsync(string workOrder)
        {
            const string sql = @"
                SELECT DISTINCT f1.CPNITMREF_0
                FROM x3.INLDRYRUN.BOM f0
                JOIN x3.INLDRYRUN.BOMD f1 ON f0.ITMREF_0 = f1.ITMREF_0
                JOIN x3.INLDRYRUN.MFGITM f2 ON f0.ITMREF_0 = f2.ITMREF_0
                JOIN x3.INLDRYRUN.MFGHEAD f3 ON f2.MFGNUM_0 = f3.MFGNUM_0
                WHERE f0.ITMREF_0 = (
                    SELECT TOP 1 m.ITMREF_0
                    FROM x3.INLDRYRUN.MFGITM m
                    WHERE m.MFGNUM_0 = @WorkOrder
                      AND m.MFGLIN_0 = '1000'
                )
                AND f1.CPNTYP_0 = '4'
                AND NOT EXISTS (
                    SELECT 1
                    FROM [Hipo].[dbo].[StagingEod] H
                    WHERE H.ProductCode COLLATE DATABASE_DEFAULT = f1.CPNITMREF_0 COLLATE DATABASE_DEFAULT
                      AND H.WorkOrderNumber = @WorkOrder
                )";

            try
            {
                using var db = new SqlConnection(_innodisConnectionString);
                var codes = await db.QueryAsync<string>(sql, new { WorkOrder = workOrder });
                Console.WriteLine($"[EOD] Found {codes.Count()} BOM components missing from StagingEod for Work Order {workOrder}.");
                return codes;
            }
            }
        }
        */

        private async Task<X3ImportResult> ImportProductionEodAsync(string workOrder, List<StagingEod> records)
        {
            var result = new X3ImportResult { Identifier = workOrder };
            string soapEnvelope = string.Empty;
            string responseXml = string.Empty;

            try
            { 
                var fileBuilder = new StringBuilder();

                foreach (var rec in records)
                {
                    string mfgDate = rec.DateOfManufacturing.ToString("yyyyMMdd");
                    string expDate = rec.ExpiryDate?.ToString("yyyyMMdd") ?? "";
                    
                    string qty = string.Equals(rec.Unit, "EA", StringComparison.OrdinalIgnoreCase) 
                        ? rec.EaQuantity.ToString("F3") 
                        : rec.TotalManufacturedQuantity.ToString("F3");

                    // Mapping according to requirement:
                    // M;Site;WorkOrderNumber;ProductCode;TotalManufacturedQuantity;Unit;1;;dateOfManufacturing;STD;|
                    fileBuilder.Append($"M;IPL;{rec.WorkOrderNumber};{rec.ProductCode};{qty};{rec.Unit};1;;{mfgDate};STD;|");
                    
                    // S;Unit;TotalManufacturedQuantity;1;Location;ItemStatus;;;;;ExpiryDate|
                    fileBuilder.Append($"S;{rec.Unit};{qty};1;{rec.Location};{rec.ItemStatus};{rec.LotNumber ?? ""};;;{expDate}|");
                    
                    // LC;DPT;PRO;CUS;Location2;Location3;;;;|
                    fileBuilder.Append($"LC;DPT;PRO;CUS;{rec.Location2 ?? ""};{rec.Location3 ?? ""};;;;|");
                }

                fileBuilder.Append("END");

                string iFile = fileBuilder.ToString();
                string inputXmlJson = "{\"GRP1\":{" +
                                      "\"I_MODIMP\":\"ZMFG\"," +
                                      "\"I_AOWSTA\":\"NO\"," +
                                      "\"I_EXEC\":\"REALTIME\"," +
                                      "\"I_RECORDSEP\":\"|\"," +
                                      "\"I_FILE\":\"" + iFile.Replace("\"", "\\\"") + "\"" +
                                      "}}";

                soapEnvelope = $@"<soapenv:Envelope xmlns:xsi=""http://www.w3.org/2001/XMLSchema-instance"" xmlns:xsd=""http://www.w3.org/2001/XMLSchema"" xmlns:soapenv=""http://schemas.xmlsoap.org/soap/envelope/"" xmlns:wss=""http://www.adonix.com/WSS"">
   <soapenv:Header/>
   <soapenv:Body>
      <wss:run soapenv:encodingStyle=""http://schemas.xmlsoap.org/soap/encoding/"">
         <callContext xsi:type=""wss:CAdxCallContext"">
            <codeLang xsi:type=""xsd:string"">ENG</codeLang>
            <poolAlias xsi:type=""xsd:string"">{_poolAlias}</poolAlias>
            <poolId xsi:type=""xsd:string""></poolId>
            <requestConfig xsi:type=""xsd:string""></requestConfig>
         </callContext>
         <publicName xsi:type=""xsd:string"">AOWSIMPORT</publicName>
            <inputXml xsi:type=""xsd:string"">
                  <![CDATA[{inputXmlJson}]]>
          </inputXml>
      </wss:run>
   </soapenv:Body>
</soapenv:Envelope>";

                Console.WriteLine("====== SAGE X3 PRODUCTION EOD SOAP REQUEST ======");
                Console.WriteLine(soapEnvelope);
                Console.WriteLine("==================================================");

                var request = new HttpRequestMessage(HttpMethod.Post, _soapUrl);
                request.Content = new StringContent(soapEnvelope, Encoding.UTF8, "text/xml");
                
                var authToken = Convert.ToBase64String(Encoding.ASCII.GetBytes($"{_username}:{_password}"));
                request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Basic", authToken);
                // Syracuse can be picky about SOAPAction casing
                request.Headers.TryAddWithoutValidation("SOAPAction", "");
                request.Headers.TryAddWithoutValidation("soapAction", "");

                var response = await _httpClient.SendAsync(request);
                responseXml = await response.Content.ReadAsStringAsync();

                Console.WriteLine("====== SAGE X3 PRODUCTION EOD SOAP RESPONSE ======");
                Console.WriteLine(responseXml);
                Console.WriteLine("===================================================");

                if (!response.IsSuccessStatusCode)
                {
                    result.Success = false;
                    result.TechnicalError = $"HTTP {response.StatusCode}: {responseXml}";
                    await InsertSoapAuditAsync("ImportProductionEod", workOrder, soapEnvelope, responseXml, false, result.TechnicalError);
                    return result;
                }

                var parsedResult = ParseSoapResponse(responseXml, result);
                await InsertSoapAuditAsync("ImportProductionEod", workOrder, soapEnvelope, responseXml, parsedResult.Success, parsedResult.Success ? null : string.Join(" | ", parsedResult.Messages));
                return parsedResult;
            }
            catch (Exception ex)
            {
                result.Success = false;
                result.TechnicalError = ex.Message;
                await InsertSoapAuditAsync("ImportProductionEod", workOrder, soapEnvelope, responseXml, false, ex.Message);
                return result;
            }
        }

        private X3ImportResult ParseSoapResponse(string xml, X3ImportResult result)
        {
            try
            {
                var doc = XDocument.Parse(xml);
                
                bool importSuccess = false;
                
                // 1. Result XML extraction (Sage X3 returned CDATA containing XML)
                var resultNode = doc.Descendants("resultXml").FirstOrDefault();
                if (resultNode != null && !string.IsNullOrEmpty(resultNode.Value))
                {
                    try 
                    {
                        var innerDoc = XDocument.Parse(resultNode.Value);
                        var grp = innerDoc.Descendants("GRP").FirstOrDefault(g => (string?)g.Attribute("ID") == "GRP1");
                        if (grp != null)
                        {
                            var fields = grp.Descendants("FLD").ToDictionary(
                                f => (string?)f.Attribute("NAME") ?? "",
                                f => f.Value
                            );

                            if (fields.TryGetValue("O_REQNUM", out var reqNum))
                            {
                                result.RequestNumber = reqNum;
                            }

                            if (fields.TryGetValue("O_STATUS", out var oStatusStr) && int.TryParse(oStatusStr, out int oStatus))
                            {
                                // Sage X3 AOWS template import success:
                                // O_STATUS >= 1 typically indicates successfully completed (or imported with warnings).
                                // O_STATUS = 0 indicates failure.
                                importSuccess = oStatus >= 1;
                            }

                            if (fields.TryGetValue("O_MESSA", out var oMessa) && !string.IsNullOrWhiteSpace(oMessa))
                            {
                                result.Messages.Add($"Sage X3: {oMessa}");
                            }
                        }
                    }
                    catch (Exception innerEx)
                    {
                        result.Messages.Add("Inner XML Parse warning: " + innerEx.Message);
                    }
                }

                // 2. Global Status in the SOAP XML: 1 = Success, 0 = Error
                var statusNode = doc.Descendants("status").FirstOrDefault();
                bool endpointSuccess = statusNode?.Value == "1";

                // Success is true ONLY if the SOAP call completed successfully AND the Sage X3 import completed successfully
                result.Success = endpointSuccess && importSuccess;

                // 3. Extract all messages from multiRef blocks (if any validation errors exist)
                var messages = doc.Descendants().Where(d => d.Name.LocalName == "message").Select(m => m.Value).ToList();
                result.Messages.AddRange(messages);

                return result;
            }
            catch (Exception ex)
            {
                result.TechnicalError = "Response Parsing Error: " + ex.Message;
                return result;
            }
        }
    }
}
