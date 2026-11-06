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
        private readonly IConfiguration _configuration;
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
            _configuration = configuration;
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

        private string ResolveX3Schema()
        {
            var httpContext = _httpContextAccessor.HttpContext;
            if (httpContext != null &&
                httpContext.Request.Headers.TryGetValue("X-X3-Schema", out var schemaHeader) &&
                !string.IsNullOrWhiteSpace(schemaHeader))
            {
                return schemaHeader.ToString().Trim();
            }

            var configSchema = _configuration["SyncSettings:X3SchemaName"];
            if (!string.IsNullOrWhiteSpace(configSchema))
            {
                return configSchema.Trim();
            }

            return "INLDRYRUN";
        }

        private static readonly Dictionary<string, (string SalesSite, string FinancialSite)> DefaultSiteMappings = new(StringComparer.OrdinalIgnoreCase)
        {
            { "CGD", ("CGD", "CGD") },
            { "CRP", ("CRP", "CRP") },
            { "DPD", ("DPD", "DPD") },
            { "DPM", ("DPM", "DPM") },
            { "FFD", ("FFD", "FFD") },
            { "POD", ("POD", "POD") }, // Single Source of Truth: Poultry Sales & Distrib -> Financial Site: POD
            { "PRO", ("PRO", "PRO") },
            { "PTT", ("PTT", "PTT") },
            { "SCG", ("SCG", "CGD") }, // Consumer Shop To Shop -> Financial Site: CGD
            { "SCP", ("SCP", "POD") }, // Chilled Shop To Shop -> Financial Site: POD
            { "SDA", ("SDA", "DPD") }, // Dairy Shop To Shop -> Financial Site: DPD
            { "SFF", ("SFF", "FFD") }, // Frozen Shop To Shop -> Financial Site: FFD
            { "IPL", ("IPL", "IPL") }
        };

        private static readonly System.Collections.Concurrent.ConcurrentDictionary<string, (string SalesSite, string FinancialSite)> _siteMappingCache = new();
        private static readonly System.Collections.Concurrent.ConcurrentDictionary<string, List<string>> _customTabletFieldsCache = new();
        private static readonly System.Collections.Concurrent.ConcurrentDictionary<string, HashSet<string>?> _validWarehousesCache = new();
        private static readonly System.Collections.Concurrent.ConcurrentDictionary<string, HashSet<string>> _validSalesRepsCache = new();

        private sealed class StockSlot
        {
            public string Warehouse { get; init; } = string.Empty;
            public string Location { get; init; } = string.Empty;
            public string LotNumber { get; init; } = string.Empty;
            public decimal Qty { get; init; }
        }

        private async Task<(string SalesSite, string FinancialSite)> ResolveSiteMappingAsync(string? rawSite, string schema)
        {
            string cleanSite = (!string.IsNullOrWhiteSpace(rawSite) && !string.Equals(rawSite.Trim(), "ALL", StringComparison.OrdinalIgnoreCase))
                ? rawSite.Trim().ToUpperInvariant()
                : "POD";

            // 1. Authoritative in-memory baseline from x3.INLDRYRUN.FACILITY
            string salesSite = cleanSite;
            string financialSite = cleanSite;
            if (DefaultSiteMappings.TryGetValue(cleanSite, out var authoritative))
            {
                salesSite = authoritative.SalesSite;
                financialSite = authoritative.FinancialSite;
            }

            string cacheKey = $"{schema}_{cleanSite}".ToUpperInvariant();
            if (_siteMappingCache.TryGetValue(cacheKey, out var cached))
            {
                return cached;
            }

            try
            {
                using var connection = new SqlConnection(_innodisConnectionString);
                string sql = $@"
                    SELECT TOP 1
                        LTRIM(RTRIM(f.FCY_0)) AS Sales_Site_Code,
                        LTRIM(RTRIM(COALESCE(NULLIF(LTRIM(RTRIM(f.FINRSPFCY_0)), ''), f.FCY_0))) AS Financial_Site_Code
                    FROM x3.{schema}.FACILITY f WITH (NOLOCK)
                    LEFT JOIN x3.{schema}.FACILITY rf WITH (NOLOCK) ON f.FINRSPFCY_0 = rf.FCY_0
                    WHERE LTRIM(RTRIM(f.FCY_0)) = @SiteCode
                      AND (f.LEGCPY_0 = 'INL' OR @SiteCode = 'IPL');";

                var row = await connection.QueryFirstOrDefaultAsync(sql, new { SiteCode = cleanSite });
                if (row != null)
                {
                    salesSite = ((string?)row.Sales_Site_Code ?? salesSite).Trim();
                    financialSite = ((string?)row.Financial_Site_Code ?? financialSite).Trim();
                }

                // Strict invariant safeguard: POD always maps to Shipping/Financial Site POD
                if (string.Equals(cleanSite, "POD", StringComparison.OrdinalIgnoreCase))
                {
                    salesSite = "POD";
                    financialSite = "POD";
                }

                Console.WriteLine($"[SageX3SoapService] Single Source of Truth Mapping ({schema}): Input={cleanSite} -> SalesSite(SALFCY)={salesSite}, Shipping/FinancialSite(STOFCY)={financialSite}");

                var resolved = (salesSite, financialSite);
                _siteMappingCache[cacheKey] = resolved;
                return resolved;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SageX3SoapService] Warning: Failed to resolve FACILITY mapping for {cleanSite} in {schema}: {ex.Message}");
                if (string.Equals(cleanSite, "POD", StringComparison.OrdinalIgnoreCase))
                {
                    salesSite = "POD";
                    financialSite = "POD";
                }
                return (salesSite, financialSite);
            }
        }

        private async Task<(string TabletName, string? AssignedWarehouse, string? AssignedLocation)> ResolveDeviceIdentityAsync(
            string? rawTabletSource,
            string? rawDeviceId,
            string? userName)
        {
            var httpContext = _httpContextAccessor.HttpContext;
            var headerDeviceId = (httpContext != null && httpContext.Request.Headers.TryGetValue("X-Device-Id", out var hDev))
                ? hDev.ToString().Trim()
                : null;
            var cleanTablet = (rawTabletSource ?? string.Empty).Trim();
            var cleanDeviceId = !string.IsNullOrWhiteSpace(rawDeviceId)
                ? rawDeviceId.Trim()
                : (headerDeviceId ?? string.Empty);
            var cleanUser = (userName ?? string.Empty).Trim();

            try
            {
                using var scope = _serviceScopeFactory.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<ScanProductionDbContext>();
                var activeDevices = await db.DeviceLocations
                    .AsNoTracking()
                    .Where(d => d.IsActive)
                    .ToListAsync();

                DeviceLocation? matched = null;

                if (!string.IsNullOrEmpty(cleanDeviceId))
                {
                    matched = activeDevices.FirstOrDefault(d =>
                        string.Equals(d.DeviceId, cleanDeviceId, StringComparison.OrdinalIgnoreCase) ||
                        (!string.IsNullOrWhiteSpace(headerDeviceId) && string.Equals(d.DeviceId, headerDeviceId, StringComparison.OrdinalIgnoreCase)));
                }

                if (matched == null && !string.IsNullOrEmpty(cleanTablet))
                {
                    matched = activeDevices.FirstOrDefault(d =>
                        string.Equals(d.DeviceName, cleanTablet, StringComparison.OrdinalIgnoreCase));
                }

                if (matched == null && !string.IsNullOrEmpty(cleanDeviceId))
                {
                    matched = activeDevices.FirstOrDefault(d =>
                        !string.IsNullOrWhiteSpace(d.HardwareModel) &&
                        (string.Equals(d.HardwareModel.Trim(), cleanDeviceId, StringComparison.OrdinalIgnoreCase) ||
                         cleanDeviceId.Contains(d.HardwareModel.Trim(), StringComparison.OrdinalIgnoreCase) ||
                         d.HardwareModel.Contains(cleanDeviceId, StringComparison.OrdinalIgnoreCase)));
                }

                if (matched == null && !string.IsNullOrEmpty(cleanUser))
                {
                    matched = activeDevices.FirstOrDefault(d =>
                        !string.IsNullOrWhiteSpace(d.AssignedUserName) &&
                        string.Equals(d.AssignedUserName.Trim(), cleanUser, StringComparison.OrdinalIgnoreCase));
                }

                if (matched != null && !string.IsNullOrWhiteSpace(matched.DeviceName))
                {
                    return (
                        matched.DeviceName.Trim().ToUpperInvariant(),
                        matched.WarehouseCode?.Trim(),
                        matched.LocationCode?.Trim());
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SageX3SoapService] DeviceLocations lookup notice: {ex.Message}");
            }

            string fallbackTablet = (!string.IsNullOrEmpty(cleanTablet) &&
                System.Text.RegularExpressions.Regex.IsMatch(cleanTablet, @"^HM\d+$", System.Text.RegularExpressions.RegexOptions.IgnoreCase))
                ? cleanTablet.ToUpperInvariant()
                : "HM1";

            return (fallbackTablet, null, null);
        }

        private async Task<List<string>> GetCustomTabletFieldNamesAsync(string schema)
        {
            string cacheKey = schema.ToUpperInvariant();
            if (_customTabletFieldsCache.TryGetValue(cacheKey, out var cached))
            {
                return cached;
            }

            var discovered = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var candidateSchemas = new[] { schema, "X3", "INL" }
                .Where(s => !string.IsNullOrWhiteSpace(s))
                .Distinct(StringComparer.OrdinalIgnoreCase);

            try
            {
                using var connection = new SqlConnection(_innodisConnectionString);

                foreach (var candSchema in candidateSchemas)
                {
                    try
                    {
                        string sqlTab = $@"
                            SELECT DISTINCT LTRIM(RTRIM(z.CODZON_0))
                            FROM x3.{candSchema}.ATABZON z WITH (NOLOCK)
                            INNER JOIN x3.{candSchema}.ATEXTE t WITH (NOLOCK)
                                ON (t.NUMERO_0 = z.NOLONG_0 OR t.NUMERO_0 = z.NOCOURT_0)
                            WHERE z.CODFIC_0 IN ('SINVOICE', 'SINVOICEV')
                              AND UPPER(t.TEXTE_0) LIKE '%TABLET%'";
                        var tabCols = await connection.QueryAsync<string>(sqlTab);
                        foreach (var c in tabCols.Where(x => !string.IsNullOrWhiteSpace(x)))
                            discovered.Add(c.Trim());
                    }
                    catch { }

                    try
                    {
                        string sqlMsk = $@"
                            SELECT DISTINCT LTRIM(RTRIM(z.CODZON_0))
                            FROM x3.{candSchema}.AMSKZON z WITH (NOLOCK)
                            INNER JOIN x3.{candSchema}.ATEXTE t WITH (NOLOCK)
                                ON t.NUMERO_0 = z.INTIT_0
                            WHERE z.CODMSK_0 LIKE 'SIH%'
                              AND UPPER(t.TEXTE_0) LIKE '%TABLET%'";
                        var mskCols = await connection.QueryAsync<string>(sqlMsk);
                        foreach (var c in mskCols.Where(x => !string.IsNullOrWhiteSpace(x)))
                            discovered.Add(c.Trim());
                    }
                    catch { }

                    if (discovered.Any()) break;
                }
            }
            catch { }

            var list = discovered.ToList();
            if (list.Any())
            {
                Console.WriteLine($"[SageX3SoapService] Discovered Tablet Source dictionary field(s) in {schema}: {string.Join(", ", list)}");
                _customTabletFieldsCache[cacheKey] = list;
            }
            return list;
        }

        private async Task EnsureTabletSourceUpdatedAsync(string schema, string? x3DocId, string tabletSource)
        {
            if (string.IsNullOrWhiteSpace(x3DocId) || string.IsNullOrWhiteSpace(tabletSource)) return;

            try
            {
                using var connection = new SqlConnection(_innodisConnectionString);
                var customCols = await GetCustomTabletFieldNamesAsync(schema);
                if (!customCols.Any())
                {
                    string sqlCols = $@"
                        SELECT c.name
                        FROM sys.columns c
                        INNER JOIN sys.tables t ON c.object_id = t.object_id
                        INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
                        WHERE s.name = @Schema AND t.name = 'SINVOICE'
                          AND (c.name LIKE 'Z%TAB%' OR c.name LIKE 'Z%SRC%' OR c.name LIKE 'Z%DEV%' OR c.name LIKE 'Z%HM%');";

                    customCols = (await connection.QueryAsync<string>(sqlCols, new { Schema = schema })).ToList();
                }

                foreach (var col in customCols)
                {
                    // X3 SQL columns carry a _0 suffix (dictionary field ZTABLETSRC -> column ZTABLETSRC_0)
                    string cleanCol = col.Trim();
                    var candidates = cleanCol.EndsWith("_0", StringComparison.OrdinalIgnoreCase)
                        ? new[] { cleanCol }
                        : new[] { cleanCol + "_0", cleanCol };

                    foreach (var candidate in candidates)
                    {
                        try
                        {
                            string updateSql = $"UPDATE x3.{schema}.SINVOICE SET [{candidate}] = @Tablet WHERE NUM_0 = @DocId;";
                            int rowsUpdated = await connection.ExecuteAsync(updateSql, new { Tablet = tabletSource, DocId = x3DocId });
                            Console.WriteLine($"[SageX3SoapService] Tablet Source [{candidate}]='{tabletSource}' on SINVOICE {x3DocId}: {rowsUpdated} row(s) updated");
                            break;
                        }
                        catch (Exception ex)
                        {
                            Console.WriteLine($"[SageX3SoapService] Notice: Could not update [{candidate}] on SINVOICE {x3DocId}: {ex.Message}");
                        }
                    }
                }
            }
            catch (Exception exGlobal)
            {
                Console.WriteLine($"[SageX3SoapService] EnsureTabletSourceUpdatedAsync notice: {exGlobal.Message}");
            }
        }

        private async Task<HashSet<string>?> GetValidWarehousesAsync(string schema)
        {
            string cacheKey = schema.ToUpperInvariant();
            if (_validWarehousesCache.TryGetValue(cacheKey, out var cached))
            {
                return cached;
            }

            var candidateSchemas = new[] { schema, "X3", "INL" }
                .Where(s => !string.IsNullOrWhiteSpace(s))
                .Distinct(StringComparer.OrdinalIgnoreCase);

            try
            {
                var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                using var connection = new SqlConnection(_innodisConnectionString);

                foreach (var candSchema in candidateSchemas)
                {
                    try
                    {
                        string sql = $@"
                            SELECT DISTINCT LTRIM(RTRIM(WRH_0))
                            FROM x3.{candSchema}.TABWRH WITH (NOLOCK)
                            WHERE LTRIM(RTRIM(ISNULL(WRH_0, ''))) <> ''";
                        var rows = await connection.QueryAsync<string>(sql);
                        foreach (var w in rows.Where(x => !string.IsNullOrWhiteSpace(x)))
                        {
                            set.Add(w.Trim());
                        }
                        if (set.Count > 0) break;
                    }
                    catch { }
                }

                _validWarehousesCache[cacheKey] = set;
                Console.WriteLine($"[SageX3SoapService] Loaded {set.Count} valid TABWRH warehouse code(s) for {schema}.");
                return set;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SageX3SoapService] TABWRH lookup notice for {schema}: {ex.Message}");
                return null;
            }
        }

        private async Task<HashSet<string>> GetValidSalesRepsAsync(string schema)
        {
            string cacheKey = schema.ToUpperInvariant();
            if (_validSalesRepsCache.TryGetValue(cacheKey, out var cached))
            {
                return cached;
            }

            var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var candidateSchemas = new[] { schema, "X3", "INL" }
                .Where(s => !string.IsNullOrWhiteSpace(s))
                .Distinct(StringComparer.OrdinalIgnoreCase);

            try
            {
                using var connection = new SqlConnection(_innodisConnectionString);

                foreach (var candSchema in candidateSchemas)
                {
                    try
                    {
                        string sql = $@"
                            SELECT DISTINCT LTRIM(RTRIM(REPNUM_0))
                            FROM x3.{candSchema}.SALESREP WITH (NOLOCK)
                            WHERE LTRIM(RTRIM(ISNULL(REPNUM_0, ''))) <> ''";
                        var rows = await connection.QueryAsync<string>(sql);
                        foreach (var r in rows.Where(x => !string.IsNullOrWhiteSpace(x)))
                        {
                            set.Add(r.Trim());
                        }
                        if (set.Count > 0) break;
                    }
                    catch { }
                }

                if (set.Count > 0)
                {
                    _validSalesRepsCache[cacheKey] = set;
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SageX3SoapService] SALESREP lookup notice for {schema}: {ex.Message}");
            }
            return set;
        }

        private static bool IsPlaceholderStockToken(string? val)
        {
            if (string.IsNullOrWhiteSpace(val)) return true;
            var v = val.Trim();
            return string.Equals(v, "Main (WH-01)", StringComparison.OrdinalIgnoreCase)
                || string.Equals(v, "WH-01", StringComparison.OrdinalIgnoreCase)
                || string.Equals(v, "A4-S2-B12", StringComparison.OrdinalIgnoreCase)
                || string.Equals(v, "Standard Storage (Pickable)", StringComparison.OrdinalIgnoreCase);
        }

        private async Task<Dictionary<string, List<StockSlot>>> GetShippingSiteStockAsync(
            string schema,
            string shippingSite,
            IEnumerable<string?> itemCodes)
        {
            var result = new Dictionary<string, List<StockSlot>>(StringComparer.OrdinalIgnoreCase);
            try
            {
                var validCodes = itemCodes
                    .Where(c => !string.IsNullOrWhiteSpace(c))
                    .Select(c => c!.Trim().ToUpperInvariant())
                    .Distinct(StringComparer.OrdinalIgnoreCase)
                    .ToList();
                if (!validCodes.Any() || string.IsNullOrWhiteSpace(shippingSite)) return result;

                using var connection = new SqlConnection(_innodisConnectionString);
                string sql = $@"
                    SELECT
                        LTRIM(RTRIM(stk.ITMREF_0)) AS Sku,
                        LTRIM(RTRIM(ISNULL(stk.WRH_0, ''))) AS Warehouse,
                        LTRIM(RTRIM(ISNULL(stk.LOC_0, ''))) AS Location,
                        LTRIM(RTRIM(ISNULL(stk.LOT_0, ''))) AS LotNumber,
                        SUM(ISNULL(stk.QTYSTU_0, 0)) AS Qty
                    FROM x3.{schema}.STOCK stk WITH (NOLOCK)
                    LEFT JOIN x3.{schema}.STOLOT sl WITH (NOLOCK)
                        ON stk.ITMREF_0 = sl.ITMREF_0 AND stk.LOT_0 = sl.LOT_0
                    WHERE LTRIM(RTRIM(stk.STOFCY_0)) = @ShippingSite
                      AND LTRIM(RTRIM(stk.ITMREF_0)) IN @ItemCodes
                      AND stk.STA_0 = 'A'
                      AND stk.QTYSTU_0 > 0
                      AND (sl.SHLDAT_0 IS NULL OR sl.SHLDAT_0 >= CAST(GETDATE() AS DATE))
                    GROUP BY
                        LTRIM(RTRIM(stk.ITMREF_0)),
                        LTRIM(RTRIM(ISNULL(stk.WRH_0, ''))),
                        LTRIM(RTRIM(ISNULL(stk.LOC_0, ''))),
                        LTRIM(RTRIM(ISNULL(stk.LOT_0, '')))
                    ORDER BY SUM(ISNULL(stk.QTYSTU_0, 0)) DESC";

                var rows = await connection.QueryAsync(sql, new { ShippingSite = shippingSite.Trim().ToUpperInvariant(), ItemCodes = validCodes });
                foreach (var r in rows)
                {
                    string sku = (string)r.Sku;
                    if (!result.TryGetValue(sku, out var list))
                    {
                        list = new List<StockSlot>();
                        result[sku] = list;
                    }
                    list.Add(new StockSlot
                    {
                        Warehouse = ((string?)r.Warehouse ?? string.Empty).Trim(),
                        Location = ((string?)r.Location ?? string.Empty).Trim(),
                        LotNumber = ((string?)r.LotNumber ?? string.Empty).Trim(),
                        Qty = Convert.ToDecimal(r.Qty)
                    });
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SageX3SoapService] Warning: Failed to query STOCK for shipping site {shippingSite}: {ex.Message}");
            }
            return result;
        }

        private async Task<Dictionary<string, (string SalesUnit, string TaxLevel)>> GetItemMetadataAsync(IEnumerable<string?> itemCodes)
        {
            var dict = new Dictionary<string, (string SalesUnit, string TaxLevel)>(StringComparer.OrdinalIgnoreCase);
            try
            {
                var validCodes = itemCodes.Where(c => !string.IsNullOrWhiteSpace(c)).Select(c => c!.Trim()).Distinct().ToList();
                if (!validCodes.Any()) return dict;

                string schema = ResolveX3Schema();

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

        private static readonly System.Collections.Concurrent.ConcurrentDictionary<string, List<string>> _templateHeaderFieldsCache = new();

        private static string NormalizeTemplateFieldKey(string? rawField)
        {
            var f = (rawField ?? string.Empty).Trim();
            if (string.IsNullOrEmpty(f) || f.StartsWith("*")) return f;

            var clean = System.Text.RegularExpressions.Regex.Replace(f, @"^\[[^\]]+\]", "").Trim();
            if (clean.Contains('.')) clean = clean.Substring(clean.LastIndexOf('.') + 1).Trim();
            clean = System.Text.RegularExpressions.Regex.Replace(clean, @"\(\d+\)$", "").Trim();
            if (clean.EndsWith("_0", StringComparison.OrdinalIgnoreCase) || clean.EndsWith("_1", StringComparison.OrdinalIgnoreCase))
            {
                clean = clean.Substring(0, clean.Length - 2).Trim();
            }
            return clean.ToUpperInvariant();
        }

        private static bool IsValidHeaderFieldOrder(string templateCode, List<string> fields)
        {
            if (fields == null || fields.Count < 5) return false;

            if (string.Equals(templateCode, "ZSIHWEBA", StringComparison.OrdinalIgnoreCase))
            {
                if (fields.Count < 14) return false;

                // First field must be record delimiter /
                if (!string.Equals(fields[0]?.Trim(), "/", StringComparison.OrdinalIgnoreCase)) return false;

                // Proven working row sequence from Sage X3 ZSIHWEBA:
                // Pos 1: SALFCY, Pos 2: SIVTYP, Pos 3: STOFCY, Pos 4: INVTYP, Pos 5: NUM, Pos 6: BPCINV
                var f1 = NormalizeTemplateFieldKey(fields[1]);
                var f2 = NormalizeTemplateFieldKey(fields[2]);
                var f3 = NormalizeTemplateFieldKey(fields[3]);
                var f4 = NormalizeTemplateFieldKey(fields[4]);
                var f5 = NormalizeTemplateFieldKey(fields[5]);
                var f6 = NormalizeTemplateFieldKey(fields[6]);

                if (f1 != "SALFCY" || f2 != "SIVTYP") return false;
                if (f3 != "STOFCY" && f3 != "FCY") return false;
                if (f4 != "INVTYP") return false;
                if (f5 != "NUM" && f5 != "INVNUM" && f5 != "VCRNUM" && f5 != "SIHNUM") return false;
                if (f6 != "BPCINV" && f6 != "BPR") return false;

                return true;
            }

            if (string.Equals(templateCode, "ZSCRWEB", StringComparison.OrdinalIgnoreCase))
            {
                if (fields.Count < 14) return false;

                // First field must be record delimiter /
                if (!string.Equals(fields[0]?.Trim(), "/", StringComparison.OrdinalIgnoreCase)) return false;

                var f1 = NormalizeTemplateFieldKey(fields[1]);
                var f2 = NormalizeTemplateFieldKey(fields[2]);
                if (f1 != "SALFCY" || f2 != "SIVTYP") return false;

                var headerKeys = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                int slashSeen = 0;
                foreach (var raw in fields)
                {
                    var t = (raw ?? string.Empty).Trim();
                    if (t == "/")
                    {
                        slashSeen++;
                        if (slashSeen >= 2) break;
                        continue;
                    }
                    headerKeys.Add(NormalizeTemplateFieldKey(t));
                }

                return headerKeys.Contains("SALFCY")
                    && headerKeys.Contains("SIVTYP")
                    && (headerKeys.Contains("STOFCY") || headerKeys.Contains("FCY"))
                    && headerKeys.Contains("INVTYP")
                    && (headerKeys.Contains("BPCINV") || headerKeys.Contains("BPR"));
            }

            return true;
        }

        private static bool TryExtractDecimal(Dictionary<string, object> row, string colName, out decimal value)
        {
            value = 0m;
            if (!row.TryGetValue(colName, out var raw) || raw == null) return false;
            if (raw is decimal d) { value = d; return true; }
            if (raw is int i) { value = i; return true; }
            if (raw is short s) { value = s; return true; }
            if (raw is long l) { value = l; return true; }
            if (raw is byte b) { value = b; return true; }
            if (raw is double db) { value = (decimal)db; return true; }
            if (raw is float fl) { value = (decimal)fl; return true; }
            return decimal.TryParse(
                Convert.ToString(raw, System.Globalization.CultureInfo.InvariantCulture),
                System.Globalization.NumberStyles.Any,
                System.Globalization.CultureInfo.InvariantCulture,
                out value);
        }

        private async Task<List<string>> GetTemplateHeaderFieldsAsync(string templateCode, string schema)
        {
            string cacheKey = $"{schema}_{templateCode}".ToUpperInvariant();
            if (_templateHeaderFieldsCache.TryGetValue(cacheKey, out var cached))
            {
                return cached;
            }

            var fieldNames = new List<string>();
            var candidateSchemas = new[] { schema, "INL" }
                .Where(s => !string.IsNullOrWhiteSpace(s))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToList();

            try
            {
                using var connection = new SqlConnection(_innodisConnectionString);

                foreach (var candSchema in candidateSchemas)
                {
                    // 1. Primary Sage X3 Import/Export Template Detail table: AOED (GESAOE)
                    try
                    {
                        string sqlAoed = $"SELECT * FROM x3.{candSchema}.AOED WITH (NOLOCK) WHERE AOE_0 = @TmplCode";
                        var rawRows = (await connection.QueryAsync(sqlAoed, new { TmplCode = templateCode })).ToList();
                        if (rawRows.Any())
                        {
                            var vDicts = new List<(Dictionary<string, object> Row, string Field)>();
                            var dDicts = new List<(Dictionary<string, object> Row, string Field)>();

                            foreach (var rowObj in rawRows)
                            {
                                if (rowObj is IDictionary<string, object> dict)
                                {
                                    var ci = new Dictionary<string, object>(dict, StringComparer.OrdinalIgnoreCase);
                                    string idVal = Convert.ToString(
                                        ci.TryGetValue("ID_0", out var vId) ? vId :
                                        (ci.TryGetValue("RECFLE_0", out var vRec) ? vRec :
                                        (ci.TryGetValue("FIL_0", out var vFil) ? vFil : "")))?.Trim() ?? "";

                                    string fldVal = Convert.ToString(
                                        ci.TryGetValue("FLD_0", out var vFld) ? vFld :
                                        (ci.TryGetValue("OBJECT_0", out var vObj) ? vObj :
                                        (ci.TryGetValue("ZON_0", out var vZon) ? vZon : "")))?.Trim() ?? "";

                                    if (string.Equals(idVal, "V", StringComparison.OrdinalIgnoreCase))
                                    {
                                        vDicts.Add((ci, fldVal));
                                    }
                                    else if (string.Equals(idVal, "D", StringComparison.OrdinalIgnoreCase))
                                    {
                                        dDicts.Add((ci, fldVal));
                                    }
                                }
                            }

                            if (vDicts.Any())
                            {
                                var allColumns = vDicts[0].Row.Keys.ToList();
                                Console.WriteLine($"[SageX3SoapService] AOED columns for {templateCode} in {candSchema}: {string.Join(", ", allColumns)}");

                                var priorityRankCols = new[]
                                {
                                    "NUMLIG_0", "LIG_0", "POS_0", "NUM_0", "SEQ_0", "LIN_0",
                                    "AOELIG_0", "ORDR_0", "CHRONO_0"
                                };
                                var excludedCols = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
                                {
                                    "UPDTICK_0", "AOE_0", "TAB_0", "FLD_0", "ID_0", "NB_0", "ORD_0", "LEV_0", "ROWID",
                                    "RNG_0", "CREUSR_0", "UPDUSR_0", "CREDAT_0", "UPDDAT_0", "CREDATTIM_0", "UPDDATTIM_0", "AUUID_0"
                                };

                                var candidateCols = priorityRankCols
                                    .Where(c => vDicts[0].Row.ContainsKey(c))
                                    .Concat(allColumns.Where(c => !priorityRankCols.Contains(c, StringComparer.OrdinalIgnoreCase) && !excludedCols.Contains(c)))
                                    .Concat(vDicts[0].Row.ContainsKey("ROWID") ? new[] { "ROWID" } : Array.Empty<string>())
                                    .ToList();

                                string? verifiedRankCol = null;
                                bool verifiedWithLev = false;
                                foreach (var candCol in candidateCols)
                                {
                                    var keyed = new List<(decimal Lev, decimal Rank, string Field)>();
                                    bool allNumeric = true;
                                    foreach (var item in vDicts)
                                    {
                                        if (!TryExtractDecimal(item.Row, candCol, out var rnk))
                                        {
                                            allNumeric = false;
                                            break;
                                        }
                                        decimal lev = TryExtractDecimal(item.Row, "LEV_0", out var lv) ? lv : 0m;
                                        keyed.Add((lev, rnk, item.Field));
                                    }

                                    if (!allNumeric) continue;

                                    // Strategy A: Global rank across V-fields (handles templates where SINVOICE and SINVOICEV have different LEV_0)
                                    if (keyed.Select(k => k.Rank).Distinct().Count() == vDicts.Count)
                                    {
                                        var sortedPureRank = keyed
                                            .OrderBy(k => k.Rank)
                                            .Select(k => k.Field)
                                            .ToList();

                                        if (IsValidHeaderFieldOrder(templateCode, sortedPureRank))
                                        {
                                            fieldNames = sortedPureRank;
                                            verifiedRankCol = candCol;
                                            verifiedWithLev = false;
                                            break;
                                        }
                                    }

                                    // Strategy B: Level + Rank composite order
                                    if (keyed.Select(k => (k.Lev, k.Rank)).Distinct().Count() == vDicts.Count)
                                    {
                                        var sortedLevRank = keyed
                                            .OrderBy(k => k.Lev)
                                            .ThenBy(k => k.Rank)
                                            .Select(k => k.Field)
                                            .ToList();

                                        if (IsValidHeaderFieldOrder(templateCode, sortedLevRank))
                                        {
                                            fieldNames = sortedLevRank;
                                            verifiedRankCol = candCol;
                                            verifiedWithLev = true;
                                            break;
                                        }
                                    }
                                }

                                if (verifiedRankCol != null)
                                {
                                    Console.WriteLine($"[SageX3SoapService] Verified AOED rank column '{verifiedRankCol}' (withLev={verifiedWithLev}) for {templateCode} in {candSchema}.");
                                    if (dDicts.Any())
                                    {
                                        var sortedD = (verifiedWithLev
                                                ? dDicts.OrderBy(d => TryExtractDecimal(d.Row, "LEV_0", out var lv) ? lv : 0m)
                                                        .ThenBy(d => TryExtractDecimal(d.Row, verifiedRankCol, out var rk) ? rk : 0m)
                                                : dDicts.OrderBy(d => TryExtractDecimal(d.Row, verifiedRankCol, out var rk) ? rk : 0m))
                                            .Select(d => d.Field)
                                            .ToList();
                                        Console.WriteLine($"[SageX3SoapService] Discovered {sortedD.Count} D-line fields for {templateCode} in {candSchema}: {string.Join(", ", sortedD)}");
                                    }
                                    break;
                                }
                                else
                                {
                                    Console.WriteLine($"[SageX3SoapService] Warning: AOED rows found for {templateCode} in {candSchema}, but no column produced verified header alignment.");
                                }
                            }
                        }
                    }
                    catch (Exception exAoed)
                    {
                        Console.WriteLine($"[SageX3SoapService] AOED template lookup notice for {templateCode} in {candSchema}: {exAoed.Message}");
                    }

                    // 2. Fallback: AOBJIMPD (isolated try/catch)
                    if (!fieldNames.Any())
                    {
                        try
                        {
                            string sqlImp = $@"
                                SELECT LTRIM(RTRIM(OBJECT_0)) AS FieldName
                                FROM x3.{candSchema}.AOBJIMPD WITH (NOLOCK)
                                WHERE MOD_0 = @TmplCode AND RECFLE_0 = 'V'
                                ORDER BY LIG_0";

                            var impFields = (await connection.QueryAsync<string>(sqlImp, new { TmplCode = templateCode })).ToList();
                            if (impFields.Any() && IsValidHeaderFieldOrder(templateCode, impFields))
                            {
                                fieldNames = impFields;
                                break;
                            }
                        }
                        catch { }
                    }

                    // 3. Fallback: AOBJEXTD (isolated try/catch)
                    if (!fieldNames.Any())
                    {
                        try
                        {
                            string sqlExt = $@"
                                SELECT LTRIM(RTRIM(FLD_0)) AS FieldName
                                FROM x3.{candSchema}.AOBJEXTD WITH (NOLOCK)
                                WHERE EXT_0 = @TmplCode AND (FIL_0 = 'V' OR FIL_0 = 'SIH' OR FIL_0 LIKE '%INVOICE%' OR FIL_0 = '')
                                ORDER BY NUMLIG_0";

                            var extFields = (await connection.QueryAsync<string>(sqlExt, new { TmplCode = templateCode })).ToList();
                            if (extFields.Any() && IsValidHeaderFieldOrder(templateCode, extFields))
                            {
                                fieldNames = extFields;
                                break;
                            }
                        }
                        catch { }
                    }
                }

                if (fieldNames.Any())
                {
                    Console.WriteLine($"[SageX3SoapService] Discovered {fieldNames.Count} V-header fields for {templateCode}: {string.Join(", ", fieldNames)}");
                    _templateHeaderFieldsCache[cacheKey] = fieldNames;
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SageX3SoapService] Template introspection notice for {templateCode}: {ex.Message}");
            }

            return fieldNames;
        }

        private string ConstructDynamicVHeader(List<string> templateFields, Dictionary<string, string> values, string fallbackHeader)
        {
            if (templateFields == null || templateFields.Count == 0)
            {
                return fallbackHeader;
            }

            var parts = new List<string> { "V" };
            int repIndex = 0;

            foreach (var rawField in templateFields)
            {
                var f = (rawField ?? string.Empty).Trim();
                if (string.Equals(f, "V", StringComparison.OrdinalIgnoreCase)) continue;

                // "/" is the record-id row: the first one opens the V record, the next one opens the D record, so stop there
                if (f == "/")
                {
                    if (parts.Count > 1) break;
                    continue;
                }

                // Preserve blank or *1 / *2 generic placeholder slots in Sage X3 AOED
                if (string.IsNullOrEmpty(f) || f.StartsWith("*"))
                {
                    parts.Add("");
                    continue;
                }

                // Normalize: strip [F:SIH], table dots, (0)/(1), and _0/_1 suffixes
                var cleanNoTable = System.Text.RegularExpressions.Regex.Replace(f, @"^\[[^\]]+\]", "").Trim();
                if (cleanNoTable.Contains('.')) cleanNoTable = cleanNoTable.Substring(cleanNoTable.LastIndexOf('.') + 1).Trim();

                bool isSecondRep = cleanNoTable.EndsWith("(1)", StringComparison.OrdinalIgnoreCase)
                    || cleanNoTable.EndsWith("_1", StringComparison.OrdinalIgnoreCase)
                    || string.Equals(cleanNoTable, "REP1", StringComparison.OrdinalIgnoreCase)
                    || string.Equals(cleanNoTable, "REP2", StringComparison.OrdinalIgnoreCase);

                var clean = System.Text.RegularExpressions.Regex.Replace(cleanNoTable, @"\(\d+\)$", "").Trim();
                if (clean.EndsWith("_0", StringComparison.OrdinalIgnoreCase) || clean.EndsWith("_1", StringComparison.OrdinalIgnoreCase))
                {
                    clean = clean.Substring(0, clean.Length - 2).Trim();
                }

                string? val = null;
                if (string.Equals(clean, "REP", StringComparison.OrdinalIgnoreCase))
                {
                    if (isSecondRep || repIndex > 0)
                    {
                        values.TryGetValue("REP_1", out val);
                    }
                    else
                    {
                        values.TryGetValue("REP", out val);
                    }
                    repIndex++;
                }
                else if (values.TryGetValue(f, out var exact))
                {
                    val = exact;
                }
                else if (values.TryGetValue(cleanNoTable, out var cleanNoTabVal))
                {
                    val = cleanNoTabVal;
                }
                else if (values.TryGetValue(clean, out var cleanVal))
                {
                    val = cleanVal;
                }
                else if (string.Equals(clean, "NUM", StringComparison.OrdinalIgnoreCase)
                      || string.Equals(clean, "INVNUM", StringComparison.OrdinalIgnoreCase)
                      || string.Equals(clean, "VCRNUM", StringComparison.OrdinalIgnoreCase)
                      || string.Equals(clean, "SIHNUM", StringComparison.OrdinalIgnoreCase)
                      || string.Equals(clean, "DOCNUM", StringComparison.OrdinalIgnoreCase))
                {
                    if (values.TryGetValue("NUM", out var numVal))
                    {
                        val = numVal;
                    }
                }
                else if (clean.Contains("TAB", StringComparison.OrdinalIgnoreCase)
                      || clean.Contains("TBL", StringComparison.OrdinalIgnoreCase)
                      || clean.Contains("TABLET", StringComparison.OrdinalIgnoreCase)
                      || clean.Contains("DEVSRC", StringComparison.OrdinalIgnoreCase)
                      || string.Equals(clean, "ZSRC", StringComparison.OrdinalIgnoreCase)
                      || string.Equals(clean, "ZSOURCE", StringComparison.OrdinalIgnoreCase)
                      || string.Equals(clean, "ZHM", StringComparison.OrdinalIgnoreCase))
                {
                    if (values.TryGetValue("ZTABLETSRC", out var vTab))
                    {
                        val = vTab;
                    }
                }

                parts.Add(val ?? "");
            }

            var line = string.Join(";", parts) + ";|";
            Console.WriteLine($"[SageX3SoapService] Constructed Dynamic V Header: {line}");
            return line;
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
                invoiceDate = invoiceDate.Replace("-", "").Replace(" ", "").Replace(":", "");
                if (invoiceDate.Length > 8) invoiceDate = invoiceDate.Substring(0, 8);
                if (string.IsNullOrWhiteSpace(invoiceDate)) invoiceDate = DateTime.UtcNow.ToString("yyyyMMdd");

                string dueDate = (invoice.DueDate ?? "").Replace("-", "").Replace(" ", "").Replace(":", "");
                if (dueDate.Length > 8) dueDate = dueDate.Substring(0, 8);
                if (string.IsNullOrWhiteSpace(dueDate)) dueDate = invoiceDate;

                string schema = ResolveX3Schema();

                // Prioritize invoice.SalesSite over userSiteCode, then map SalesSite (SALFCY) vs FinancialSite (STOFCY)
                var userSiteCode = _httpContextAccessor.HttpContext?.User?.FindFirst("SiteCode")?.Value;
                string requestedSite = (!string.IsNullOrWhiteSpace(invoice.SalesSite) && invoice.SalesSite != "ALL")
                    ? invoice.SalesSite
                    : (!string.IsNullOrWhiteSpace(userSiteCode) && userSiteCode != "ALL" ? userSiteCode : "POD");

                var (salesSite, shippingSite) = await ResolveSiteMappingAsync(requestedSite, schema);

                // Resolve Sales Rep(s) cleanly and validate against x3.<schema>.SALESREP
                var repParts = (invoice.SalesRep ?? "")
                    .Split(new[] { ',', ';' }, StringSplitOptions.RemoveEmptyEntries)
                    .Select(r => r.Trim())
                    .Where(r => !string.IsNullOrEmpty(r))
                    .ToArray();
                string primarySalesRep = repParts.Length > 0 ? repParts[0] : "";
                string secondarySalesRep = repParts.Length > 1 ? repParts[1] : "";

                var validSalesReps = await GetValidSalesRepsAsync(schema);
                if (validSalesReps.Count > 0)
                {
                    if (!string.IsNullOrEmpty(primarySalesRep) && !validSalesReps.Contains(primarySalesRep))
                    {
                        Console.WriteLine($"[SageX3SoapService] Clearing non-SALESREP primary rep '{primarySalesRep}' so X3 inherits from BPCINV.");
                        primarySalesRep = "";
                    }
                    if (!string.IsNullOrEmpty(secondarySalesRep) && !validSalesReps.Contains(secondarySalesRep))
                    {
                        Console.WriteLine($"[SageX3SoapService] Clearing non-SALESREP secondary rep '{secondarySalesRep}' so X3 inherits from BPCINV.");
                        secondarySalesRep = "";
                    }
                }

                string reference = !string.IsNullOrWhiteSpace(invoice.InvoiceId)
                    ? invoice.InvoiceId.Trim()
                    : (!string.IsNullOrWhiteSpace(invoice.TransactionalId)
                        ? invoice.TransactionalId.Trim()
                        : (invoice.Reference ?? ""));

                // Resolve standardized HM* tablet name (e.g. HM1) & assigned device warehouse/location
                var (tabletSource, assignedWarehouse, assignedLocation) = await ResolveDeviceIdentityAsync(
                    invoice.TabletSource,
                    invoice.DeviceId,
                    invoice.UserName ?? invoice.CreatedBy);

                // Sage X3 sales invoice type for mobile sales invoices is always MICAS (never STD)
                const string invType = "MICAS";

                var invoiceHeaderValues = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
                {
                    { "SALFCY", salesSite },
                    { "SIVTYP", invType },
                    { "STOFCY", shippingSite },
                    { "FCY", shippingSite },
                    { "INVTYP", "1" },
                    { "NUM", "" },
                    { "NUM_0", "" },
                    { "INVNUM", "" },
                    { "VCRNUM", "" },
                    { "SIHNUM", "" },
                    { "BPCINV", invoice.CustomerCode ?? "" },
                    { "BPR", invoice.CustomerCode ?? "" },
                    { "BPCORD", invoice.CustomerCode ?? "" },
                    { "BPCPYR", invoice.CustomerCode ?? "" },
                    { "INVDAT", invoiceDate },
                    { "ACCDAT", invoiceDate },
                    { "BPRVCR", reference },
                    { "INVREF", reference },
                    { "STOMVTFLG", "2" },
                    { "STA", "3" },
                    { "REP", primarySalesRep },
                    { "REP_0", primarySalesRep },
                    { "REP_1", secondarySalesRep },
                    { "CUR", "MUR" },
                    { "STRDUDDAT", dueDate },
                    { "PTE", invoice.PaymentTerm ?? "" },
                    { "INVDTAAMT", "" },
                    { "ZMRACRNREF", "" },
                    { "ZREASONSTATE", "" },
                    { "SIHORI", "1" },
                    { "SIHORINUM", "" },
                    { "ZTABLETSRC", tabletSource },
                    { "ZTABSRC", tabletSource },
                    { "ZTBLSRC", tabletSource },
                    { "ZSRC", tabletSource },
                    { "ZSOURCE", tabletSource },
                    { "ZTABLET", tabletSource },
                    { "ZTAB", tabletSource },
                    { "ZDEVSRC", tabletSource },
                    { "ZHM", tabletSource }
                };

                var customTabletCols = await GetCustomTabletFieldNamesAsync(schema);
                foreach (var col in customTabletCols)
                {
                    invoiceHeaderValues[col] = tabletSource;
                    if (col.EndsWith("_0", StringComparison.OrdinalIgnoreCase))
                    {
                        invoiceHeaderValues[col.Substring(0, col.Length - 2)] = tabletSource;
                    }
                }

                var invoiceTemplateFields = await GetTemplateHeaderFieldsAsync("ZSIHWEBA", schema);
                // Template ZSIHWEBA V-Record definition (Proven working layout):
                // 1:V(/), 2:SALFCY, 3:SIVTYP, 4:STOFCY, 5:INVTYP(1), 6:NUM(), 7:BPCINV, 8:ACCDAT, 9:INVREF, 10:STOMVTFLG(2), 11:STA(3), 12:REP(1), 13:CUR(MUR), 14:STRDUDDAT, 15:ZMRACRNREF(), 16:ZREASONSTATE(), 17:ZTABLETSRC
                string fallbackInvoiceHeader = $"V;{salesSite};{invType};{shippingSite};1;;{invoice.CustomerCode};{invoiceDate};{reference};2;3;{primarySalesRep};MUR;{dueDate};;;{tabletSource};|";
                fileBuilder.Append(ConstructDynamicVHeader(invoiceTemplateFields, invoiceHeaderValues, fallbackInvoiceHeader));

                // Pre-resolve item metadata (official SalesUnit and TaxLevel from ITMMASTER), valid TABWRH warehouses & STOCK in shippingSite
                var itemMetadata = await GetItemMetadataAsync(invoice.Lines.Select(l => l.Sku));
                var validWarehouses = await GetValidWarehousesAsync(schema);
                var siteStockMap = await GetShippingSiteStockAsync(schema, shippingSite, invoice.Lines.Select(l => l.Sku));

                int lineMultiplier = 1000;
                foreach (var line in invoice.Lines)
                {
                    string sku = (line.Sku ?? "").Trim();
                    string safeLineName = (line.Name ?? "").Replace(";", " ").Replace("|", " ").Replace("\r", " ").Replace("\n", " ").Trim();
                    string unit = line.SalesUnit ?? "";
                    string taxRule = line.TaxRule ?? "";

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

                    string qty = line.Quantity.ToString("F3", System.Globalization.CultureInfo.InvariantCulture);
                    string basePrice = line.BasePrice.ToString("F2", System.Globalization.CultureInfo.InvariantCulture);
                    string disc1 = line.DiscountAmount.ToString("F2", System.Globalization.CultureInfo.InvariantCulture);
                    string disc2 = (line.Discount2 > 0 ? line.Discount2 : line.DiscountAmountFlat).ToString("F2", System.Globalization.CultureInfo.InvariantCulture);
                    string disc3 = line.Discount3.ToString("F2", System.Globalization.CultureInfo.InvariantCulture);

                    string warehouse = IsPlaceholderStockToken(line.Warehouse) ? "" : (line.Warehouse ?? "").Trim();
                    string location = IsPlaceholderStockToken(line.Location) ? "" : (line.Location ?? "").Trim();
                    string lotNumber = (line.LotNumber ?? "").Trim();

                    // Validate warehouse strictly against x3.<schema>.TABWRH (strips site codes like POD / IPL / CGD when WRH management is off)
                    if (!string.IsNullOrEmpty(warehouse))
                    {
                        if (validWarehouses != null)
                        {
                            if (!validWarehouses.Contains(warehouse)) warehouse = "";
                        }
                        else if (string.Equals(warehouse, salesSite, StringComparison.OrdinalIgnoreCase)
                              || string.Equals(warehouse, shippingSite, StringComparison.OrdinalIgnoreCase)
                              || string.Equals(warehouse, "CGD", StringComparison.OrdinalIgnoreCase)
                              || string.Equals(warehouse, "POD", StringComparison.OrdinalIgnoreCase))
                        {
                            warehouse = "";
                        }
                    }

                    // Align line stock allocation (Warehouse, Location, Lot) with shippingSite (Financial Site) so STOMVTFLG=2 succeeds
                    if (siteStockMap.TryGetValue(sku, out var availableStocks) && availableStocks.Any())
                    {
                        var exactMatch = availableStocks.FirstOrDefault(s =>
                            (string.IsNullOrEmpty(warehouse) || string.Equals(s.Warehouse, warehouse, StringComparison.OrdinalIgnoreCase)) &&
                            (string.IsNullOrEmpty(location) || string.Equals(s.Location, location, StringComparison.OrdinalIgnoreCase)) &&
                            (string.IsNullOrEmpty(lotNumber) || string.Equals(s.LotNumber, lotNumber, StringComparison.OrdinalIgnoreCase)));

                        if (exactMatch != null)
                        {
                            warehouse = exactMatch.Warehouse;
                            location = exactMatch.Location;
                            lotNumber = exactMatch.LotNumber;
                        }
                        else
                        {
                            var lotMatch = !string.IsNullOrEmpty(lotNumber)
                                ? availableStocks.FirstOrDefault(s => string.Equals(s.LotNumber, lotNumber, StringComparison.OrdinalIgnoreCase))
                                : null;

                            if (lotMatch != null)
                            {
                                warehouse = lotMatch.Warehouse;
                                location = lotMatch.Location;
                                lotNumber = lotMatch.LotNumber;
                            }
                            else
                            {
                                var devMatch = availableStocks.FirstOrDefault(s =>
                                    (!string.IsNullOrEmpty(assignedLocation) && string.Equals(s.Location, assignedLocation, StringComparison.OrdinalIgnoreCase)) ||
                                    (!string.IsNullOrEmpty(assignedWarehouse) && string.Equals(s.Warehouse, assignedWarehouse, StringComparison.OrdinalIgnoreCase)));

                                var best = devMatch ?? availableStocks.First();
                                warehouse = best.Warehouse;
                                location = best.Location;
                                lotNumber = best.LotNumber;
                            }
                        }
                    }

                    if (!string.IsNullOrEmpty(warehouse) && validWarehouses != null && !validWarehouses.Contains(warehouse))
                    {
                        warehouse = "";
                    }

                    // Template ZSIHWEBA D-Record definition (Rows 17-31):
                    // 17:D(/), 18:SIDLIN, 19:ITMREF, 20:ITMDES, 21:SAU, 22:QTY, 23:GROPRI, 24:DISCRGVAL1, 25:DISCRGVAL2, 26:DISCRGVAL3, 27:VACITM, 28:ZPRIUOM(), 29:ZPRIQTY(), 30:WRH, 31:LOC
                    fileBuilder.Append($"D;{lineMultiplier};{sku};{safeLineName};{unit};{qty};{basePrice};{disc1};{disc2};{disc3};{taxRule};;;{warehouse};{location};|");
                    
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

                if (parsedResult.Success || (!string.IsNullOrEmpty(parsedResult.RawPayload) && parsedResult.RawPayload.Contains("Creation of ", StringComparison.OrdinalIgnoreCase)))
                {
                    var createdDocId = parsedResult.DocumentId;
                    if (string.IsNullOrEmpty(createdDocId) && !string.IsNullOrEmpty(parsedResult.RawPayload))
                    {
                        var idx = parsedResult.RawPayload.IndexOf("Creation of ", StringComparison.OrdinalIgnoreCase);
                        if (idx >= 0)
                        {
                            var sub = parsedResult.RawPayload.Substring(idx + "Creation of ".Length);
                            var endIdx = sub.IndexOfAny(new[] { '<', '"', '\r', '\n', ' ' });
                            createdDocId = endIdx > 0 ? sub.Substring(0, endIdx).Trim() : sub.Trim();
                        }
                    }

                    if (!string.IsNullOrEmpty(createdDocId) && !string.IsNullOrEmpty(tabletSource))
                    {
                        await EnsureTabletSourceUpdatedAsync(schema, createdDocId, tabletSource);
                    }
                }

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

                string crnSchema = ResolveX3Schema();

                var userSiteCode = _httpContextAccessor.HttpContext?.User?.FindFirst("SiteCode")?.Value;
                string requestedCrnSite = (!string.IsNullOrWhiteSpace(creditNote.SalesSite) && creditNote.SalesSite != "ALL")
                    ? creditNote.SalesSite
                    : (!string.IsNullOrWhiteSpace(userSiteCode) && userSiteCode != "ALL" ? userSiteCode : "POD");

                var (salesSite, shippingSite) = await ResolveSiteMappingAsync(requestedCrnSite, crnSchema);
                // Sage X3 sales invoice type for credit notes AND returns: MICRE
                string crnType = "MICRE";

                // Normalized Category Flag: 2 = Credit Note, 3 = Return
                int category = creditNote.Category == 3 ? 3 : 2;

                // Field 9 (INVREF): Unique Reference generated on mobile device (e.g. HCPOD571261000001 or HRPOD571261000001)
                string reference = !string.IsNullOrWhiteSpace(creditNote.InvoiceId)
                    ? creditNote.InvoiceId.Trim()
                    : (!string.IsNullOrWhiteSpace(creditNote.TransactionalId)
                        ? creditNote.TransactionalId.Trim()
                        : (creditNote.Reference ?? ""));

                var crnRepParts = (creditNote.SalesRep ?? "")
                    .Split(new[] { ',', ';' }, StringSplitOptions.RemoveEmptyEntries)
                    .Select(r => r.Trim())
                    .Where(r => !string.IsNullOrEmpty(r))
                    .ToArray();
                string primaryCrnRep = crnRepParts.Length > 0 ? crnRepParts[0] : "";
                string secondaryCrnRep = crnRepParts.Length > 1 ? crnRepParts[1] : "";

                var validCrnSalesReps = await GetValidSalesRepsAsync(crnSchema);
                if (validCrnSalesReps.Count > 0)
                {
                    if (!string.IsNullOrEmpty(primaryCrnRep) && !validCrnSalesReps.Contains(primaryCrnRep))
                    {
                        primaryCrnRep = "";
                    }
                    if (!string.IsNullOrEmpty(secondaryCrnRep) && !validCrnSalesReps.Contains(secondaryCrnRep))
                    {
                        secondaryCrnRep = "";
                    }
                }

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

                // Stock Transaction Flag: In Sage X3 Local Menu 1 (Non/Oui): 1 = No, 2 = Yes
                // - Return (Category 3): YES (2)
                // - Credit Note (Category 2): NO (1)
                int stockTransaction = (category == 3) ? 2 : 1;

                var (tabletSource, crnAssignedWarehouse, _) = await ResolveDeviceIdentityAsync(
                    creditNote.TabletSource,
                    creditNote.DeviceId,
                    creditNote.UserName ?? creditNote.CreatedBy);

                var crnHeaderValues = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
                {
                    { "SALFCY", salesSite },
                    { "SIVTYP", crnType },
                    { "STOFCY", shippingSite },
                    { "FCY", shippingSite },
                    { "INVTYP", category.ToString() },
                    { "NUM", "" },
                    { "NUM_0", "" },
                    { "INVNUM", "" },
                    { "VCRNUM", "" },
                    { "SIHNUM", "" },
                    { "BPCINV", creditNote.CustomerCode ?? "" },
                    { "BPR", creditNote.CustomerCode ?? "" },
                    { "BPCORD", creditNote.CustomerCode ?? "" },
                    { "BPCPYR", creditNote.CustomerCode ?? "" },
                    { "INVDAT", creditNoteDate },
                    { "ACCDAT", creditNoteDate },
                    { "BPRVCR", reference },
                    { "INVREF", reference },
                    { "STOMVTFLG", stockTransaction.ToString() },
                    { "STA", "3" },
                    { "REP", primaryCrnRep },
                    { "REP_0", primaryCrnRep },
                    { "REP_1", secondaryCrnRep },
                    { "CUR", "MUR" },
                    { "STRDUDDAT", dueDate },
                    { "INVDTAAMT", "" },
                    { "ZMRACRNREF", "0" },
                    { "ZREASONSTATE", reason },
                    { "SIHORI", sihoriFlag },
                    { "SIHORINUM", sihoriNum },
                    { "ZTABLETSRC", tabletSource },
                    { "ZTABSRC", tabletSource },
                    { "ZTBLSRC", tabletSource },
                    { "ZSRC", tabletSource },
                    { "ZSOURCE", tabletSource },
                    { "ZTABLET", tabletSource },
                    { "ZTAB", tabletSource },
                    { "ZDEVSRC", tabletSource },
                    { "ZHM", tabletSource }
                };

                var crnTabletCols = await GetCustomTabletFieldNamesAsync(crnSchema);
                foreach (var col in crnTabletCols)
                {
                    crnHeaderValues[col] = tabletSource;
                    if (col.EndsWith("_0", StringComparison.OrdinalIgnoreCase))
                    {
                        crnHeaderValues[col.Substring(0, col.Length - 2)] = tabletSource;
                    }
                }

                // Header Record (Matching Sage X3 ZSCRWEB template):
                var crnTemplateFields = await GetTemplateHeaderFieldsAsync("ZSCRWEB", crnSchema);
                string fallbackCrnHeader = $"V;{salesSite};{crnType};{shippingSite};{category};;{creditNote.CustomerCode};{creditNoteDate};{reference};{stockTransaction};3;{primaryCrnRep};MUR;{dueDate};;0;{reason};{sihoriFlag};{sihoriNum};{tabletSource};|";
                fileBuilder.Append(ConstructDynamicVHeader(crnTemplateFields, crnHeaderValues, fallbackCrnHeader));

                // Pre-resolve item metadata (official SalesUnit and TaxLevel from ITMMASTER) & valid TABWRH warehouses
                var candidateSkus = new HashSet<string>(creditNote.Lines.Where(l => !string.IsNullOrEmpty(l.Sku)).Select(l => l.Sku!));
                var itemMetadata = await GetItemMetadataAsync(candidateSkus);
                var validCrnWarehouses = await GetValidWarehousesAsync(crnSchema);

                int lineMultiplier = 1000;
                foreach (var line in creditNote.Lines)
                {
                    string sku = (line.Sku ?? "").Trim();
                    string name = (line.Name ?? "").Replace(";", " ").Replace("|", " ").Replace("\r", " ").Replace("\n", " ").Trim();
                    string unit = line.SalesUnit ?? "";
                    double price = line.BasePrice;
                    string taxRule = line.TaxRule ?? "";
                    string cce0 = string.IsNullOrWhiteSpace(line.Cce0) ? "COMMERCIAL" : line.Cce0;
                    string warehouse = IsPlaceholderStockToken(line.Warehouse) ? "" : (line.Warehouse ?? "").Trim();

                    if (stockTransaction == 2 && string.IsNullOrWhiteSpace(warehouse) && !string.IsNullOrWhiteSpace(crnAssignedWarehouse))
                    {
                        warehouse = crnAssignedWarehouse.Trim();
                    }

                    if (!string.IsNullOrEmpty(warehouse))
                    {
                        if (validCrnWarehouses != null)
                        {
                            if (!validCrnWarehouses.Contains(warehouse)) warehouse = "";
                        }
                        else if (string.Equals(warehouse, salesSite, StringComparison.OrdinalIgnoreCase)
                              || string.Equals(warehouse, shippingSite, StringComparison.OrdinalIgnoreCase)
                              || string.Equals(warehouse, "CGD", StringComparison.OrdinalIgnoreCase)
                              || string.Equals(warehouse, "POD", StringComparison.OrdinalIgnoreCase))
                        {
                            warehouse = "";
                        }
                    }

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
                TabletSource = creditNote.DeviceId ?? "HM1",
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

        private string? ResolveBankForPaymentMethod(string method, string defaultFallbackBank)
        {
            string m = (method ?? "").Trim().ToUpperInvariant();
            if (m == "CREDIT")
            {
                return null; // Credit transactions do not have a bank
            }

            var mapping = _configuration.GetSection("PaymentBankMapping");
            string? mappedBank = null;

            if (m == "CASH" || m == "CSH")
            {
                mappedBank = mapping["Cash"];
            }
            else if (m == "CHEQUE" || m == "CHQ")
            {
                mappedBank = mapping["Cheque"];
            }
            else if (m == "JUICE")
            {
                mappedBank = mapping["Juice"];
            }
            else if (m == "BLINK")
            {
                mappedBank = mapping["Blink"];
            }
            else if (m == "MYT MONEY" || m == "MYTMONEY")
            {
                mappedBank = mapping["MytMoney"] ?? mapping["Blink"];
            }
            else if (m == "BANK_TRANSFER" || m == "BTR" || m == "QR" || m == "QR CODE")
            {
                mappedBank = mapping["Blink"] ?? mapping["Juice"];
            }

            if (!string.IsNullOrWhiteSpace(mappedBank))
            {
                return mappedBank.Trim();
            }

            // Fallback to facility default bank if mapping is left blank for now
            return defaultFallbackBank;
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
                    string methodUpper = (payment.PaymentMethod ?? "").Trim().ToUpperInvariant();
                    if (methodUpper == "CREDIT")
                    {
                        // Credit transactions do not post bank payment receipts
                        continue;
                    }

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

                    // Dynamically resolve financial site, legal company, and default bank from Sage X3
                    string rawPaySite = (!string.IsNullOrWhiteSpace(payment.SalesSite) && payment.SalesSite != "ALL") 
                        ? payment.SalesSite.Trim() 
                        : "POD";
                    string paySchema = ResolveX3Schema();
                    var (_, fcy) = await ResolveSiteMappingAsync(rawPaySite, paySchema);
                    
                    var (resolvedCompany, resolvedDefaultBank) = await ResolveCompanyAndBankAsync(fcy, paySchema);
                    string company = resolvedCompany;
                    string controlAccount = "122001";

                    // Map payment mode (CSH, CHQ, BTR)
                    string pam = "CSH";
                    if (methodUpper == "CHEQUE" || methodUpper == "CHQ") pam = "CHQ";
                    else if (methodUpper == "BANK_TRANSFER" || methodUpper == "BTR" || methodUpper == "BLINK" || methodUpper == "JUICE" || methodUpper == "QR" || methodUpper == "QR CODE" || methodUpper == "MYT MONEY") pam = "BTR";
                    else if (!string.IsNullOrWhiteSpace(payment.X3PaymentMode)) pam = payment.X3PaymentMode.Trim().ToUpperInvariant();

                    // Resolve Bank Code: strictly assigned by backend mapping per payment method
                    string? resolvedBank = ResolveBankForPaymentMethod(methodUpper, resolvedDefaultBank);
                    string bank = !string.IsNullOrWhiteSpace(resolvedBank) ? resolvedBank : resolvedDefaultBank;

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
                                    if (!oMessa.Contains("Number not assigned and sequence number manual", StringComparison.OrdinalIgnoreCase)
                                        && !oMessa.Contains("automatic assignment of the number", StringComparison.OrdinalIgnoreCase)
                                        && !oMessa.Contains("Error format ZREASONSTATE", StringComparison.OrdinalIgnoreCase))
                                    {
                                        result.Messages.Add($"Sage X3: {oMessa}");
                                    }
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
                                    .Where(m => !string.IsNullOrWhiteSpace(m)
                                             && !m.Contains("Creation of ", StringComparison.OrdinalIgnoreCase)
                                             && !m.Contains("Number not assigned and sequence number manual", StringComparison.OrdinalIgnoreCase)
                                             && !m.Contains("automatic assignment of the number", StringComparison.OrdinalIgnoreCase)
                                             && !m.Contains("Error format ZREASONSTATE", StringComparison.OrdinalIgnoreCase))
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
