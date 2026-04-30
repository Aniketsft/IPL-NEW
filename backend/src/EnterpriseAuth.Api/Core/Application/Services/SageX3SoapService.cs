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

        public SageX3SoapService(ScanProductionDbContext context, IConfiguration configuration, IHttpClientFactory httpClientFactory)
        {
            _context = context;
            _httpClient = httpClientFactory.CreateClient();
            
            var settings = configuration.GetSection("X3SoapService");
            _soapUrl = settings["Url"] ?? "http://192.168.120.6:8124/soap-generic/syracuse/collaboration/syracuse/CAdxWebServiceXmlCC";
            _poolAlias = settings["PoolAlias"] ?? "IMPORT-EXPORT";
            _username = settings["Username"] ?? "ADMIN";
            _password = settings["Password"] ?? "PASSWORD_HERE";
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

                // Header Record: H;Template;Site1;Site2;;Customer;Currency;ShiDate;DelDate;Flag;Lorry;Location
                fileBuilder.Append($"H;{header?.ZSDHTYP_0};{header?.ZSALFCY_0};{header?.ZSTOFCY_0};;{header?.ZBPCORD_0};{header?.ZSUR_0};{shiDate};{delDate};2;{header?.ZLOCFCY_0};{header?.ZLOC_0}|");

                // Line Records: L;SONo;LineNo;ItemCode;Description;Unit;Qty
                foreach (var line in lines)
                {
                    string qty = line.ZQTY_0.ToString("F3"); // 3 decimal places
                    fileBuilder.Append($"L;{line.ZSOHNUM_0};{line.ZSOPLIN_0};{line.ZITMREF_0};{line.ZITMDES_0};{line.ZSAU_0};{qty}|");
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
                string soapEnvelope = $@"<soapenv:Envelope xmlns:xsi=""http://www.w3.org/2001/XMLSchema-instance"" xmlns:xsd=""http://www.w3.org/2001/XMLSchema"" xmlns:soapenv=""http://schemas.xmlsoap.org/soap/envelope/"" xmlns:wss=""http://www.adonix.com/WSS"">
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
                string responseXml = await response.Content.ReadAsStringAsync();

                if (!response.IsSuccessStatusCode)
                {
                    result.Success = false;
                    result.TechnicalError = $"HTTP {response.StatusCode}: {responseXml}";
                    return result;
                }

                // 6. Parse Response
                return ParseSoapResponse(responseXml, result);
            }
            catch (Exception ex)
            {
                result.Success = false;
                result.TechnicalError = ex.Message;
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

                    var importResult = await ImportProductionEodAsync(workOrder, records);
                    result.Results.Add(importResult);

                    if (importResult.Success)
                    {
                        result.SuccessCount++;
                        foreach (var record in records)
                        {
                            record.IsProcessed = true;
                        }

                        await _context.SaveChangesAsync();
                        await transaction.CommitAsync();
                    }
                    else
                    {
                        result.FailureCount++;
                    }
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

        private async Task<X3ImportResult> ImportProductionEodAsync(string workOrder, List<StagingEod> records)
        {
            var result = new X3ImportResult { Identifier = workOrder };

            try
            { 
                var fileBuilder = new StringBuilder();

                foreach (var rec in records)
                {
                    string mfgDate = rec.DateOfManufacturing.ToString("yyyyMMdd");
                    string expDate = rec.ExpiryDate?.ToString("yyyyMMdd") ?? "";
                    string qty = rec.TotalManufacturedQuantity.ToString("F3");

                    // Mapping according to requirement:
                    // M;Site;WorkOrderNumber;ProductCode;TotalManufacturedQuantity;Unit;1;;dateOfManufacturing;STD;|
                    fileBuilder.Append($"M;IPL;{rec.WorkOrderNumber};{rec.ProductCode};{qty};{rec.Unit};1;;{mfgDate};STD;|");
                    
                    // S;Unit;TotalManufacturedQuantity;1;Location;ItemStatus;;;;;ExpiryDate|
                    fileBuilder.Append($"S;{rec.Unit};{qty};1;{rec.Location};{rec.ItemStatus};;;;;{expDate}|");
                    
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

                string soapEnvelope = $@"<soapenv:Envelope xmlns:xsi=""http://www.w3.org/2001/XMLSchema-instance"" xmlns:xsd=""http://www.w3.org/2001/XMLSchema"" xmlns:soapenv=""http://schemas.xmlsoap.org/soap/envelope/"" xmlns:wss=""http://www.adonix.com/WSS"">
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
                string responseXml = await response.Content.ReadAsStringAsync();

                if (!response.IsSuccessStatusCode)
                {
                    result.Success = false;
                    result.TechnicalError = $"HTTP {response.StatusCode}: {responseXml}";
                    return result;
                }

                return ParseSoapResponse(responseXml, result);
            }
            catch (Exception ex)
            {
                result.Success = false;
                result.TechnicalError = ex.Message;
                return result;
            }
        }

        private X3ImportResult ParseSoapResponse(string xml, X3ImportResult result)
        {
            try
            {
                var doc = XDocument.Parse(xml);
                
                // 1. Result JSON extraction (optional detail)
                var resultNode = doc.Descendants("resultXml").FirstOrDefault();
                if (resultNode != null && !string.IsNullOrEmpty(resultNode.Value))
                {
                    try 
                    {
                        using var jsonDoc = JsonDocument.Parse(resultNode.Value);
                        if (jsonDoc.RootElement.TryGetProperty("GRP1", out var grp1))
                        {
                            if (grp1.TryGetProperty("O_REQNUM", out var reqNum))
                                result.RequestNumber = reqNum.GetString();
                        }
                    }
                    catch { /* Ignore JSON parse errors in resultXml */ }
                }

                // 2. Global Status in the XML: 1 = Success, 0 = Error
                var statusNode = doc.Descendants("status").FirstOrDefault();
                result.Success = statusNode?.Value == "1";

                // 3. Extract all messages from multiRef blocks
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
