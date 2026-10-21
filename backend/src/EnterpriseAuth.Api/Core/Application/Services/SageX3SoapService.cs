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

                // Header Record: H;Template;Site1;Site2;;Customer;Currency;ShiDate;DelDate;Flag;Lorry;Location
                fileBuilder.Append($"H;{header?.ZSDHTYP_0};{header?.ZSALFCY_0};{header?.ZSTOFCY_0};;{header?.ZBPCORD_0};{header?.ZSUR_0};{shiDate};{delDate};2;{header?.ZLOCFCY_0};{header?.ZLOC_0}|");

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

        private async Task<Dictionary<string, (string SalesUnit, string TaxLevel)>> GetItemMetadataAsync(IEnumerable<string?> itemCodes)
        {
            var dict = new Dictionary<string, (string SalesUnit, string TaxLevel)>(StringComparer.OrdinalIgnoreCase);
            try
            {
                var validCodes = itemCodes.Where(c => !string.IsNullOrWhiteSpace(c)).Select(c => c!.Trim()).Distinct().ToList();
                if (!validCodes.Any()) return dict;

                string schema = "INLPROD";
                var httpContext = _httpContextAccessor.HttpContext;
                if (httpContext != null && httpContext.Request.Headers.TryGetValue("X-X3-Schema", out var schemaHeader) && !string.IsNullOrWhiteSpace(schemaHeader))
                {
                    schema = schemaHeader.ToString().Trim();
                }

                using var connection = new SqlConnection(_innodisConnectionString);
                string sql = $@"
                    SELECT LTRIM(RTRIM(ITMREF_0)) AS ItemCode, 
                           LTRIM(RTRIM(ISNULL(SAU_0, 'UN'))) AS SalesUnit, 
                           LTRIM(RTRIM(ISNULL(VACITM_0, 'STD'))) AS TaxLevel
                    FROM x3.{schema}.ITMMASTER
                    WHERE ITMREF_0 IN @ItemCodes";

                var rows = await connection.QueryAsync(sql, new { ItemCodes = validCodes });
                foreach (var r in rows)
                {
                    dict[(string)r.ItemCode] = ((string)r.SalesUnit, (string)r.TaxLevel);
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SageX3SoapService] Warning: Failed to query ITMMASTER metadata: {ex.Message}");
            }
            return dict;
        }

        public async Task<X3ImportResult> ImportSalesInvoiceAsync(StagingSalesInvoiceHeader invoice)
        {
            var result = new X3ImportResult { Identifier = invoice.InvoiceId };
            string soapEnvelope = string.Empty;
            string responseXml = string.Empty;

            try
            {
                // 1. Build the I_FILE content
                var fileBuilder = new StringBuilder();

                string invoiceDate = invoice.CreatedAt ?? DateTime.UtcNow.ToString("yyyyMMdd");
                
                // Format: yyyy-MM-dd to yyyyMMdd if necessary, but we'll assume it's clean or parse it.
                // It's safer to just remove hyphens if they exist to match X3 expected "yyyyMMdd"
                invoiceDate = invoiceDate.Replace("-", "").Replace(" ", "").Replace(":", "");
                if (invoiceDate.Length > 8) invoiceDate = invoiceDate.Substring(0, 8);
                if (string.IsNullOrWhiteSpace(invoiceDate)) invoiceDate = DateTime.UtcNow.ToString("yyyyMMdd");

                string dueDate = (invoice.DueDate ?? "").Replace("-", "").Replace(" ", "").Replace(":", "");
                if (dueDate.Length > 8) dueDate = dueDate.Substring(0, 8);
                if (string.IsNullOrWhiteSpace(dueDate)) dueDate = invoiceDate;

                // Ensure default values from plan
                var userSiteCode = _httpContextAccessor.HttpContext?.User?.FindFirst("SiteCode")?.Value;
                string site = (!string.IsNullOrWhiteSpace(userSiteCode) && userSiteCode != "ALL") 
                    ? userSiteCode 
                    : (!string.IsNullOrWhiteSpace(invoice.SalesSite) && invoice.SalesSite != "ALL" ? invoice.SalesSite : "IPL");
                string pricingRule = invoice.PricingRule ?? "";

                // Resolve Sales Rep
                string salesRep = (invoice.SalesRep ?? "").Trim();

                // Header Record: V;SalesSite;InvoiceType;SalesSite;1;;CustomerCode;InvoiceDate;Reference;2;SalesRep;MUR;DueDate;;|
                fileBuilder.Append($"V;{site};{invoice.InvoiceType};{site};1;;{invoice.CustomerCode};{invoiceDate};{invoice.Reference ?? ""};2;{salesRep};MUR;{dueDate};;|");

                // Pre-resolve item metadata (official SalesUnit and TaxLevel from ITMMASTER)
                var itemMetadata = await GetItemMetadataAsync(invoice.Lines.Select(l => l.Sku));

                int lineMultiplier = 1000;
                foreach (var line in invoice.Lines)
                {
                    string unit = line.SalesUnit ?? "";
                    string taxRule = line.TaxRule ?? "";

                    if (itemMetadata.TryGetValue(line.Sku ?? "", out var meta))
                    {
                        if (string.IsNullOrWhiteSpace(unit) || string.Equals(unit, "EA", StringComparison.OrdinalIgnoreCase))
                        {
                            unit = meta.SalesUnit;
                        }
                        if (string.IsNullOrWhiteSpace(taxRule) || taxRule == "0.00" || taxRule == "0")
                        {
                            taxRule = meta.TaxLevel;
                        }
                    }

                    if (string.IsNullOrWhiteSpace(unit)) unit = "UN";
                    if (string.IsNullOrWhiteSpace(taxRule)) taxRule = "VAT0";

                    string qty = line.Quantity.ToString("F3", System.Globalization.CultureInfo.InvariantCulture);
                    string basePrice = line.BasePrice.ToString("F2", System.Globalization.CultureInfo.InvariantCulture);
                    string disc1 = line.DiscountAmount.ToString("F2", System.Globalization.CultureInfo.InvariantCulture);
                    string disc2 = (line.Discount2 > 0 ? line.Discount2 : line.DiscountAmountFlat).ToString("F2", System.Globalization.CultureInfo.InvariantCulture);
                    string disc3 = line.Discount3.ToString("F2", System.Globalization.CultureInfo.InvariantCulture);
                    string warehouse = line.Warehouse ?? "";
                    string location = line.Location ?? "";
                    string lotNumber = line.LotNumber ?? "";

                    // Line Record: D;LineNo;Sku;Name;SalesUnit;Quantity;Price;Disc1;Disc2;Disc3;TaxRule;;;Warehouse;Location;LotNumber;|
                    fileBuilder.Append($"D;{lineMultiplier};{line.Sku};{line.Name};{unit};{qty};{basePrice};{disc1};{disc2};{disc3};{taxRule};;;{warehouse};{location};{lotNumber};|");
                    
                    // Analytical Record: A;DPT;Cce0|
                    string cce0 = string.IsNullOrWhiteSpace(line.Cce0) ? "COMMERCIAL" : line.Cce0;
                    fileBuilder.Append($"A;DPT;{cce0};|");
                    
                    lineMultiplier += 1000;
                }

                fileBuilder.Append("END");

                // 2. Construct the JSON for the CDATA block
                string iFile = fileBuilder.ToString();
                string inputXmlJson = "{\"GRP1\":{" +
                                      "\"I_MODIMP\":\"ZSIHWEBA\"," +
                                      "\"I_AOWSTA\":\"NO\"," +
                                      "\"I_EXEC\":\"REALTIME\"," +
                                      "\"I_RECORDSEP\":\"|\"," +
                                      "\"I_FILE\":\"" + iFile.Replace("\"", "\\\"") + "\"" +
                                      "}}";

                // 3. Construct the SOAP Envelope
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

                // 4. Send Request
                Console.WriteLine("====== SAGE X3 SALES INVOICE SOAP REQUEST ======");
                Console.WriteLine(soapEnvelope);
                Console.WriteLine("================================================");

                var request = new HttpRequestMessage(HttpMethod.Post, _soapUrl);
                request.Content = new StringContent(soapEnvelope, Encoding.UTF8, "text/xml");
                
                var authToken = Convert.ToBase64String(Encoding.ASCII.GetBytes($"{_username}:{_password}"));
                request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Basic", authToken);

                request.Headers.TryAddWithoutValidation("SOAPAction", "");
                request.Headers.TryAddWithoutValidation("soapAction", "");

                var response = await _httpClient.SendAsync(request);
                responseXml = await response.Content.ReadAsStringAsync();

                if (!response.IsSuccessStatusCode)
                {
                    result.Success = false;
                    result.TechnicalError = $"HTTP {response.StatusCode}: {responseXml}";
                    await InsertSoapAuditAsync("ImportSalesInvoice", invoice.InvoiceId, soapEnvelope, responseXml, false, result.TechnicalError);
                    return result;
                }

                // 5. Parse Response
                var parsedResult = ParseSoapResponse(responseXml, result);
                
                // For Sales Invoices, we trust O_STATUS >= 1
                await InsertSoapAuditAsync("ImportSalesInvoice", invoice.InvoiceId, soapEnvelope, responseXml, parsedResult.Success, parsedResult.Success ? null : string.Join(" | ", parsedResult.Messages));
                return parsedResult;
            }
            catch (Exception ex)
            {
                result.Success = false;
                result.TechnicalError = ex.Message;
                await InsertSoapAuditAsync("ImportSalesInvoice", invoice.InvoiceId, soapEnvelope, responseXml, false, ex.Message);
                return result;
            }
        }

        public async Task<X3ImportResult> ImportCreditNoteAsync(StagingSalesInvoiceHeader creditNote)
        {
            var result = new X3ImportResult { Identifier = creditNote.InvoiceId };
            string soapEnvelope = string.Empty;
            string responseXml = string.Empty;

            try
            {
                // 1. Build the I_FILE content
                var fileBuilder = new StringBuilder();

                string creditNoteDate = creditNote.CreatedAt ?? DateTime.UtcNow.ToString("yyyyMMdd");
                creditNoteDate = creditNoteDate.Replace("-", "").Replace(" ", "").Replace(":", "");
                if (creditNoteDate.Length > 8) creditNoteDate = creditNoteDate.Substring(0, 8);
                else creditNoteDate = creditNoteDate.PadRight(8, '0');

                string dueDate = !string.IsNullOrWhiteSpace(creditNote.DueDate)
                    ? creditNote.DueDate.Replace("-", "").Replace(" ", "").Replace(":", "")
                    : creditNoteDate;
                if (dueDate.Length > 8) dueDate = dueDate.Substring(0, 8);
                else dueDate = dueDate.PadRight(8, '0');

                var userSiteCode = _httpContextAccessor.HttpContext?.User?.FindFirst("SiteCode")?.Value;
                string site = (!string.IsNullOrWhiteSpace(userSiteCode) && userSiteCode != "ALL") 
                    ? userSiteCode 
                    : (!string.IsNullOrWhiteSpace(creditNote.SalesSite) && creditNote.SalesSite != "ALL" ? creditNote.SalesSite : "IPL");

                string salesSite = site;
                string crnType = "CRN";

                // Normalized Category Flag: 2 = Credit Note, 3 = Return
                int category = creditNote.Category == 3 ? 3 : 2;

                // Field 9 (INVREF): strictly user-provided reference/description; blank if empty
                string reference = creditNote.Reference ?? "";
                string salesRep = creditNote.SalesRep ?? "";

                // Sanitize Reason for Sage X3 Miscellaneous Table 8 (ZREASONSTATE):
                string rawReason = (creditNote.Reason ?? "").Trim();
                string reason = rawReason;
                if (reason.Contains("(") && reason.Contains(")"))
                {
                    var match = System.Text.RegularExpressions.Regex.Match(reason, @"\(([A-Za-z0-9_-]+)\)");
                    if (match.Success)
                    {
                        reason = match.Groups[1].Value.Trim();
                    }
                }

                var validReasons = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
                {
                    "RET", "DEF", "MIS", "DNC", "PRI", "QTY", "LTE", "NOD", "DSC",
                    "BW", "DP", "DPR", "EXP", "MRK", "PE", "WO", "WSO"
                };

                if (!validReasons.Contains(reason))
                {
                    reason = "MIS"; // Safe default to Miscellaneous Table 8 code
                }
                else
                {
                    reason = reason.ToUpperInvariant();
                }

                // Field 16 (SIHORI): Document Origin Mode (1 = Direct Credit Note, 4 = Linked with Invoice)
                string sihoriFlag = !string.IsNullOrWhiteSpace(creditNote.TransactionMode)
                    ? creditNote.TransactionMode
                    : (string.IsNullOrWhiteSpace(creditNote.OriginInvoiceId) ? "1" : "4");

                // Field 17 (SIHORINUM): Real Sage X3 Document Number (populated only if linked, blank if direct)
                string sihoriNum = (sihoriFlag == "4") ? (creditNote.OriginInvoiceId ?? "") : "";

                // Header Record (17 Positions):
                // Pos 1: V
                // Pos 2: SalesSite
                // Pos 3: CRN
                // Pos 4: ShippingSite
                // Pos 5: Category (2 for CRN, 3 for RTN)
                // Pos 6: <Blank> (Invoice Number)
                // Pos 7: CustomerCode
                // Pos 8: CreditNoteDate
                // Pos 9: Reference (User input, blank if empty)
                // Pos 10: Stock Transaction (1)
                // Pos 11: SalesRep
                // Pos 12: Currency (MUR)
                // Pos 13: DueDate
                // Pos 14: MRA credit note ref (0)
                // Pos 15: Reason (e.g. BW, MIS)
                // Pos 16: SIHORI (Document Origin Mode: 1 = Direct, 4 = Linked)
                // Pos 17: SIHORINUM (Original Sage X3 Document Number, e.g. IPLSI261044318)
                fileBuilder.Append($"V;{site};{crnType};{salesSite};{category};;{creditNote.CustomerCode};{creditNoteDate};{reference};1;{salesRep};MUR;{dueDate};0;{reason};{sihoriFlag};{sihoriNum};|");

                // Pre-resolve item metadata (official SalesUnit and TaxLevel from ITMMASTER)
                var candidateSkus = new HashSet<string>(creditNote.Lines.Where(l => !string.IsNullOrEmpty(l.Sku)).Select(l => l.Sku!));
                var itemMetadata = await GetItemMetadataAsync(candidateSkus);

                int lineMultiplier = 1000;
                foreach (var line in creditNote.Lines)
                {
                    string sku = line.Sku ?? "";
                    string name = line.Name ?? "";
                    string unit = line.SalesUnit ?? "";
                    double price = line.BasePrice;
                    string taxRule = line.TaxRule ?? "";
                    string cce0 = string.IsNullOrWhiteSpace(line.Cce0) ? "COMMERCIAL" : line.Cce0;
                    string warehouse = line.Warehouse ?? "";

                    if (itemMetadata.TryGetValue(sku, out var meta))
                    {
                        if (string.IsNullOrWhiteSpace(unit) || string.Equals(unit, "EA", StringComparison.OrdinalIgnoreCase))
                        {
                            unit = meta.SalesUnit;
                        }
                        if (string.IsNullOrWhiteSpace(taxRule) || taxRule == "0.00" || taxRule == "0")
                        {
                            taxRule = meta.TaxLevel;
                        }
                    }

                    if (string.IsNullOrWhiteSpace(unit)) unit = "UN";
                    if (string.IsNullOrWhiteSpace(taxRule)) taxRule = "VAT0";

                    string qty = (line.Quantity % 1 == 0)
                        ? line.Quantity.ToString("F0", System.Globalization.CultureInfo.InvariantCulture)
                        : line.Quantity.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture);

                    string basePriceStr = (price % 1 == 0)
                        ? price.ToString("F0", System.Globalization.CultureInfo.InvariantCulture)
                        : price.ToString("0.##", System.Globalization.CultureInfo.InvariantCulture);

                    string disc1 = (line.DiscountAmount % 1 == 0)
                        ? line.DiscountAmount.ToString("F0", System.Globalization.CultureInfo.InvariantCulture)
                        : line.DiscountAmount.ToString("0.##", System.Globalization.CultureInfo.InvariantCulture);

                    var d2Val = line.Discount2 > 0 ? line.Discount2 : line.DiscountAmountFlat;
                    string disc2 = (d2Val % 1 == 0)
                        ? d2Val.ToString("F0", System.Globalization.CultureInfo.InvariantCulture)
                        : d2Val.ToString("0.##", System.Globalization.CultureInfo.InvariantCulture);

                    string disc3 = (line.Discount3 % 1 == 0)
                        ? line.Discount3.ToString("F0", System.Globalization.CultureInfo.InvariantCulture)
                        : line.Discount3.ToString("0.##", System.Globalization.CultureInfo.InvariantCulture);

                    // Detail Record (14 Positions):
                    // D;LineNo;Sku;Name;SalesUnit;Quantity;Price;Disc1;Disc2;Disc3;TaxRule;;;Warehouse;|
                    // Positions 12 and 13 are explicitly blank (;;), Position 14 is Warehouse
                    fileBuilder.Append($"D;{lineMultiplier};{sku};{name};{unit};{qty};{basePriceStr};{disc1};{disc2};{disc3};{taxRule};;;{warehouse};|");

                    // Analytical Record: A;DPT;Cce0|
                    fileBuilder.Append($"A;DPT;{cce0};|");

                    lineMultiplier += 1000;
                }

                fileBuilder.Append("END");

                // 2. Construct JSON CDATA with ZSCRWEB template
                string iFile = fileBuilder.ToString();
                string inputXmlJson = "{\"GRP1\":{" +
                                      "\"I_MODIMP\":\"ZSCRWEB\"," +
                                      "\"I_AOWSTA\":\"NO\"," +
                                      "\"I_EXEC\":\"REALTIME\"," +
                                      "\"I_RECORDSEP\":\"|\"," +
                                      "\"I_FILE\":\"" + iFile.Replace("\"", "\\\"") + "\"" +
                                      "}}";

                // 3. Construct SOAP Envelope
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

                Console.WriteLine("====== SAGE X3 CREDIT NOTE SOAP REQUEST (ZSCRWEB) ======");
                Console.WriteLine(soapEnvelope);
                Console.WriteLine("=========================================================");

                var request = new HttpRequestMessage(HttpMethod.Post, _soapUrl);
                request.Content = new StringContent(soapEnvelope, Encoding.UTF8, "text/xml");

                var authToken = Convert.ToBase64String(Encoding.ASCII.GetBytes($"{_username}:{_password}"));
                request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Basic", authToken);

                request.Headers.TryAddWithoutValidation("SOAPAction", "");
                request.Headers.TryAddWithoutValidation("soapAction", "");

                var response = await _httpClient.SendAsync(request);
                responseXml = await response.Content.ReadAsStringAsync();

                if (!response.IsSuccessStatusCode)
                {
                    result.Success = false;
                    result.TechnicalError = $"HTTP {response.StatusCode}: {responseXml}";
                    await InsertSoapAuditAsync("ImportCreditNote", creditNote.InvoiceId, soapEnvelope, responseXml, false, result.TechnicalError);
                    return result;
                }

                // 4. Parse Response
                var parsedResult = ParseSoapResponse(responseXml, result);
                await InsertSoapAuditAsync("ImportCreditNote", creditNote.InvoiceId, soapEnvelope, responseXml, parsedResult.Success, parsedResult.Success ? null : string.Join(" | ", parsedResult.Messages));
                return parsedResult;
            }
            catch (Exception ex)
            {
                result.Success = false;
                result.TechnicalError = ex.Message;
                await InsertSoapAuditAsync("ImportCreditNote", creditNote.InvoiceId, soapEnvelope, responseXml, false, ex.Message);
                return result;
            }
        }

        public async Task<X3ImportResult> ImportCreditNoteAsync(StagingCreditNoteHeader creditNote)
        {
            // Backward-compatibility bridge: convert StagingCreditNoteHeader to StagingSalesInvoiceHeader
            var invoiceHeader = new StagingSalesInvoiceHeader
            {
                InvoiceId = creditNote.CreditNoteId,
                InvoiceType = "2",
                SalesSite = creditNote.SalesSite,
                CustomerCode = creditNote.CustomerCode,
                CustomerName = creditNote.CustomerName,
                Reference = creditNote.Reference,
                CreatedAt = creditNote.CreatedAt,
                CreatedBy = creditNote.CreatedBy,
                DeviceId = creditNote.DeviceId,
                OriginInvoiceId = creditNote.OriginalInvoiceId,
                TransactionMode = string.Equals(creditNote.CreditNoteType, "STANDALONE", StringComparison.OrdinalIgnoreCase) ? "1" : "4"
            };

            foreach (var l in creditNote.Lines)
            {
                invoiceHeader.Lines.Add(new StagingSalesInvoiceLine
                {
                    InvoiceId = creditNote.CreditNoteId,
                    LineNo = l.LineNo,
                    Sku = l.StandaloneSku,
                    Name = l.StandaloneName,
                    Quantity = l.Quantity,
                    BasePrice = l.StandalonePrice ?? 0.0,
                    SalesUnit = l.StandaloneSalesUnit,
                    TaxRule = l.StandaloneTaxRule,
                    LotNumber = l.StandaloneLot,
                    Warehouse = l.StandaloneWarehouse,
                    Cce0 = l.StandaloneCce0
                });
            }

            return await ImportCreditNoteAsync(invoiceHeader);
        }

        private static readonly System.Collections.Concurrent.ConcurrentDictionary<string, string> _facilityCompanyCache = new();
        private static readonly System.Collections.Concurrent.ConcurrentDictionary<string, string> _facilityDefaultBankCache = new();

        private async Task<(string company, string defaultBank)> ResolveCompanyAndBankAsync(string fcy, string schema = "INLDRYRUN")
        {
            string cleanFcy = (!string.IsNullOrWhiteSpace(fcy) && fcy != "ALL") ? fcy.Trim() : "POD";

            if (!_facilityCompanyCache.TryGetValue(cleanFcy, out var company))
            {
                try
                {
                    using var conn = new SqlConnection(_innodisConnectionString);
                    await conn.OpenAsync();
                    var legCpy = await conn.QueryFirstOrDefaultAsync<string>(
                        $"SELECT TOP 1 LEGCPY_0 FROM x3.{schema}.FACILITY WHERE FCY_0 = @cleanFcy",
                        new { cleanFcy });
                    company = !string.IsNullOrWhiteSpace(legCpy) ? legCpy.Trim() : ((cleanFcy == "IPL") ? "IPLTD" : "INL");
                    _facilityCompanyCache[cleanFcy] = company;
                }
                catch
                {
                    company = (cleanFcy == "IPL") ? "IPLTD" : "INL";
                }
            }

            string cacheKey = $"{cleanFcy}_{company}";
            if (!_facilityDefaultBankCache.TryGetValue(cacheKey, out var defaultBank))
            {
                try
                {
                    using var conn = new SqlConnection(_innodisConnectionString);
                    await conn.OpenAsync();
                    var ban = await conn.QueryFirstOrDefaultAsync<string>(
                        $"SELECT TOP 1 BAN_0 FROM x3.{schema}.BANK WHERE (FCY_0 = @cleanFcy OR (CPY_0 = @company AND (FCY_0 IS NULL OR FCY_0 = ''))) ORDER BY CASE WHEN FCY_0 = @cleanFcy THEN 1 ELSE 2 END, CASE WHEN BAN_0 LIKE 'MCB%' THEN 1 ELSE 2 END, BAN_0 ASC",
                        new { cleanFcy, company });
                    defaultBank = !string.IsNullOrWhiteSpace(ban) ? ban.Trim() : ((company == "IPLTD") ? "MCB76" : "MCB92");
                    _facilityDefaultBankCache[cacheKey] = defaultBank;
                }
                catch
                {
                    defaultBank = (company == "IPLTD") ? "MCB76" : "MCB92";
                }
            }

            return (company, defaultBank);
        }

        public async Task<X3ImportResult> ImportPaymentAsync(List<StagingSalesInvoicePayment> payments)
        {
            var result = new X3ImportResult();
            if (payments == null || !payments.Any())
            {
                result.Success = true;
                return result;
            }

            var firstPayment = payments.First();
            result.Identifier = firstPayment.DocumentId;
            string soapEnvelope = string.Empty;
            string responseXml = string.Empty;

            try
            {
                var fileBuilder = new StringBuilder();

                foreach (var payment in payments)
                {
                    bool isCreditNote = string.Equals(payment.DocumentType, "CREDIT_NOTE", StringComparison.OrdinalIgnoreCase);
                    
                    // Entry Type: REM (Reimbursement/Refund) for Credit Note, REC (Receipt) for Invoice
                    string entryType = !string.IsNullOrWhiteSpace(payment.X3EntryType) 
                        ? payment.X3EntryType 
                        : (isCreditNote ? "REM" : "REC");
                    
                    // Sign: 1 for Disbursement (Outflow), 2 for Receipt (Inflow)
                    int sign = payment.X3Sign > 0 ? payment.X3Sign : (isCreditNote ? 1 : 2);
                    
                    // Document Category: SCRN for Credit Note, SINV for Sales Invoice
                    string docCategory = !string.IsNullOrWhiteSpace(payment.X3DocumentType) 
                        ? payment.X3DocumentType 
                        : (isCreditNote ? "SCRN" : "SINV");

                    string customerCode = !string.IsNullOrWhiteSpace(payment.CustomerCode) ? payment.CustomerCode.Trim() : "";

                    // Dynamically resolve site, legal company, and default bank from Sage X3
                    string fcy = (!string.IsNullOrWhiteSpace(payment.SalesSite) && payment.SalesSite != "ALL") 
                        ? payment.SalesSite.Trim() 
                        : "POD";
                    
                    var (resolvedCompany, resolvedDefaultBank) = await ResolveCompanyAndBankAsync(fcy);
                    string company = resolvedCompany;
                    string controlAccount = "122001";

                    // Map payment mode (CSH, CHQ, BTR)
                    string methodUpper = (payment.PaymentMethod ?? "").Trim().ToUpperInvariant();
                    string pam = "CSH";
                    if (methodUpper == "CHEQUE" || methodUpper == "CHQ") pam = "CHQ";
                    else if (methodUpper == "BANK_TRANSFER" || methodUpper == "BTR" || methodUpper == "BLINK" || methodUpper == "JUICE" || methodUpper == "QR" || methodUpper == "QR CODE") pam = "BTR";
                    else if (!string.IsNullOrWhiteSpace(payment.X3PaymentMode)) pam = payment.X3PaymentMode.Trim().ToUpperInvariant();

                    // Resolve Bank Code: strictly <= 5 characters (K:5c in Sage X3)
                    string bank = (!string.IsNullOrWhiteSpace(payment.BankCode) && 
                                   payment.BankCode.Trim().Length <= 5 && 
                                   !payment.BankCode.Trim().Equals("CASH01", StringComparison.OrdinalIgnoreCase))
                        ? payment.BankCode.Trim()
                        : resolvedDefaultBank;

                    string currency = !string.IsNullOrWhiteSpace(payment.Currency) ? payment.Currency.Trim() : "MUR";
                    string amtStr = payment.Amount.ToString("F2", System.Globalization.CultureInfo.InvariantCulture);

                    string payDate = (payment.CreatedAt ?? DateTime.UtcNow.ToString("yyyyMMdd"))
                        .Replace("-", "").Replace(" ", "").Replace(":", "");
                    if (payDate.Length > 8) payDate = payDate.Substring(0, 8);
                    if (string.IsNullOrWhiteSpace(payDate)) payDate = DateTime.UtcNow.ToString("yyyyMMdd");

                    string description = !string.IsNullOrWhiteSpace(payment.ChequeNumber) 
                        ? $"CHQ {payment.ChequeNumber}".Trim() 
                        : (isCreditNote ? "Cash Refund" : "Payment");
                    if (description.Length > 30) description = description.Substring(0, 30);

                    string targetDocNum = !string.IsNullOrWhiteSpace(payment.X3InvoiceDocumentId) ? payment.X3InvoiceDocumentId.Trim() : "";

                    // P Header Line:
                    // P;[NUM];[TYP];;[BPR];[CPY];[ACC];;[PAM];[FCY];[BAN];[SNS];[CUR];[AMTCUR];[AMT];0;[DATE];[DES]
                    fileBuilder.Append($"P;;{entryType};;{customerCode};{company};{controlAccount};;{pam};{fcy};{bank};{sign};{currency};{amtStr};{amtStr};0;{payDate};{description}|");

                    // D Detail Line:
                    // Pos 19: D | Pos 20: DENCOD | Pos 21: COA | Pos 22: ACC | Pos 23: BPRLIN | Pos 24: VCRTYP | Pos 25: VCRNUM
                    // Pos 26: *1 (DUDDAT) | Pos 27: *2 (DUDLIG = 1) | Pos 28: *3 | Pos 29: *4 | Pos 30: CURLIN
                    // Pos 31: AMTLIN | Pos 32: VATLIN | Pos 33: QTYLIN (0) | Pos 34: DSP | Pos 35: DESLIN
                    fileBuilder.Append($"D;;;{controlAccount};{customerCode};{docCategory};{targetDocNum};{payDate};1;;;{currency};{amtStr};;0;;{description}|");
                }

                fileBuilder.Append("END");

                string iFile = fileBuilder.ToString();
                string inputXmlJson = "{\"GRP1\":{" +
                                      "\"I_MODIMP\":\"ZPAYWEBA\"," +
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

                Console.WriteLine("====== SAGE X3 PAYMENT SOAP REQUEST (ZPAYWEBA) ======");
                Console.WriteLine(soapEnvelope);
                Console.WriteLine("======================================================");

                var request = new HttpRequestMessage(HttpMethod.Post, _soapUrl);
                request.Content = new StringContent(soapEnvelope, Encoding.UTF8, "text/xml");
                
                var authToken = Convert.ToBase64String(Encoding.ASCII.GetBytes($"{_username}:{_password}"));
                request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Basic", authToken);
                request.Headers.TryAddWithoutValidation("SOAPAction", "");
                request.Headers.TryAddWithoutValidation("soapAction", "");

                var response = await _httpClient.SendAsync(request);
                responseXml = await response.Content.ReadAsStringAsync();

                Console.WriteLine("====== SAGE X3 PAYMENT SOAP RESPONSE (ZPAYWEBA) ======");
                Console.WriteLine(responseXml);
                Console.WriteLine("=======================================================");

                if (!response.IsSuccessStatusCode)
                {
                    result.Success = false;
                    result.TechnicalError = $"HTTP {response.StatusCode}: {responseXml}";
                    await InsertSoapAuditAsync("ImportPayment", result.Identifier, soapEnvelope, responseXml, false, result.TechnicalError);
                    return result;
                }

                var parsedResult = ParseSoapResponse(responseXml, result);
                await InsertSoapAuditAsync("ImportPayment", result.Identifier, soapEnvelope, responseXml, parsedResult.Success, parsedResult.Success ? null : string.Join(" | ", parsedResult.Messages));
                return parsedResult;
            }
            catch (Exception ex)
            {
                result.Success = false;
                result.TechnicalError = ex.Message;
                await InsertSoapAuditAsync("ImportPayment", result.Identifier, soapEnvelope, responseXml, false, ex.Message);
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
                            string? currentProduct = null;
                            
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
                result.RawPayload = xml;
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
                                if (oMessa.Contains("Creation of "))
                                {
                                    result.DocumentId = oMessa.Substring(oMessa.IndexOf("Creation of ")).Replace("Creation of ", "").Trim();
                                    importSuccess = true; // Force import success if document was created
                                }
                                else
                                {
                                    result.Messages.Add($"Sage X3: {oMessa}");
                                }
                            }
                        }
                    }
                    catch (Exception innerEx)
                    {
                        result.Messages.Add("Inner XML Parse warning: " + innerEx.Message);
                    }
                }

                // 2. Global Status in the SOAP XML: 1 = Success, 0 = Error
                var statusNode = doc.Descendants().FirstOrDefault(d => d.Name.LocalName == "status");
                bool endpointSuccess = statusNode?.Value == "1";

                // 3. Extract all messages from multiRef blocks
                var rawMessages = doc.Descendants().Where(d => d.Name.LocalName == "message").Select(m => m.Value).ToList();
                
                var creationMsg = rawMessages.FirstOrDefault(m => m != null && m.Contains("Creation of "));
                if (creationMsg != null)
                {
                    result.DocumentId = creationMsg.Substring(creationMsg.IndexOf("Creation of ")).Replace("Creation of ", "").Trim();
                    importSuccess = true; // Force success if document was created
                }

                // Filter out empty strings and creation confirmation messages
                var errorMessages = rawMessages
                                    .Where(m => !string.IsNullOrWhiteSpace(m) && !m.Contains("Creation of "))
                                    .ToList();
                
                result.Messages.AddRange(errorMessages);

                // 4. Final Success Evaluation: If DocumentId is populated, it's a success despite any endpoint warnings.
                if (!string.IsNullOrEmpty(result.DocumentId))
                {
                    result.Success = true;
                }
                else
                {
                    result.Success = endpointSuccess && importSuccess;
                }

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
