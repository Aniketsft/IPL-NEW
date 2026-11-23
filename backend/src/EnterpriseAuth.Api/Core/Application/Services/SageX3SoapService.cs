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

        private static readonly Dictionary<string, (string SalesSite, string ShippingSite)> DefaultSiteMappings = new(StringComparer.OrdinalIgnoreCase)
        {
            { "CGD", ("CGD", "CGD") },
            { "CRP", ("CRP", "CRP") },
            { "DPD", ("DPD", "DPD") },
            { "DPM", ("DPM", "DPM") },
            { "FFD", ("FFD", "FFD") },
            { "POD", ("POD", "POD") }, // Single Source of Truth: Poultry Sales & Distrib -> Financial Site: POD
            { "PRO", ("PRO", "PRO") },
            { "PTT", ("PTT", "PTT") },
            { "SCG", ("CGD", "SCG") }, // Consumer Shop To Shop -> Sales Site: CGD, Shipping Site: SCG
            { "SCP", ("SCP", "SCP") }, // Note: SCP is explicitly excluded from mapping to POD
            { "SDA", ("DPD", "SDA") }, // Dairy Shop To Shop -> Sales Site: DPD, Shipping Site: SDA
            { "SFF", ("FFD", "SFF") }, // Frozen Shop To Shop -> Sales Site: FFD, Shipping Site: SFF
            { "IPL", ("IPL", "IPL") }
        };

        private static readonly System.Collections.Concurrent.ConcurrentDictionary<string, (string SalesSite, string ShippingSite)> _siteMappingCache = new();
        private static readonly System.Collections.Concurrent.ConcurrentDictionary<string, List<string>> _customTabletFieldsCache = new();
        private static readonly System.Collections.Concurrent.ConcurrentDictionary<string, HashSet<string>?> _validWarehousesCache = new();
        private static readonly System.Collections.Concurrent.ConcurrentDictionary<string, Dictionary<string, List<string>>> _siteWarehousesCache = new();
        private static readonly System.Collections.Concurrent.ConcurrentDictionary<string, HashSet<string>> _validSalesRepsCache = new();

        public sealed class StockSlot
        {
            public string Warehouse { get; init; } = string.Empty;
            public string Location { get; init; } = string.Empty;
            public string LotNumber { get; init; } = string.Empty;
            public decimal Qty { get; init; }
        }

        private sealed class TemplateDetailLayout
        {
            public List<string> DFields { get; init; } = new();
            public List<string> SFields { get; init; } = new();
        }

        private static readonly System.Collections.Concurrent.ConcurrentDictionary<string, TemplateDetailLayout> _templateDetailLayoutCache = new();

        private async Task<(string SalesSite, string ShippingSite)> ResolveSiteMappingAsync(string? rawSite, string schema)
        {
            string cleanSite = (!string.IsNullOrWhiteSpace(rawSite) && !string.Equals(rawSite.Trim(), "ALL", StringComparison.OrdinalIgnoreCase))
                ? rawSite.Trim().ToUpperInvariant()
                : "POD";

            // 1. Authoritative in-memory baseline from x3.INLDRYRUN.FACILITY
            string salesSite = cleanSite;
            string shippingSite = cleanSite;
            if (DefaultSiteMappings.TryGetValue(cleanSite, out var authoritative))
            {
                salesSite = authoritative.SalesSite;
                shippingSite = authoritative.ShippingSite;
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
                        LTRIM(RTRIM(f.FCY_0)) AS Shipping_Site_Code,
                        LTRIM(RTRIM(COALESCE(NULLIF(LTRIM(RTRIM(f.FINRSPFCY_0)), ''), f.FCY_0))) AS Financial_Sales_Site_Code
                    FROM x3.{schema}.FACILITY f WITH (NOLOCK)
                    LEFT JOIN x3.{schema}.FACILITY rf WITH (NOLOCK) ON f.FINRSPFCY_0 = rf.FCY_0
                    WHERE LTRIM(RTRIM(f.FCY_0)) = @SiteCode
                      AND (f.LEGCPY_0 = 'INL' OR @SiteCode = 'IPL');";

                var row = await connection.QueryFirstOrDefaultAsync(sql, new { SiteCode = cleanSite });
                if (row != null)
                {
                    shippingSite = ((string?)row.Shipping_Site_Code ?? shippingSite).Trim();
                    salesSite = ((string?)row.Financial_Sales_Site_Code ?? salesSite).Trim();
                }

                // Strict invariant safeguard: POD and SCP always remain independent sites
                if (string.Equals(cleanSite, "POD", StringComparison.OrdinalIgnoreCase))
                {
                    salesSite = "POD";
                    shippingSite = "POD";
                }
                else if (string.Equals(cleanSite, "SCP", StringComparison.OrdinalIgnoreCase))
                {
                    salesSite = "SCP";
                    shippingSite = "SCP";
                }

                Console.WriteLine($"[SageX3SoapService] Single Source of Truth Mapping ({schema}): Input={cleanSite} -> SalesSite(SALFCY)={salesSite}, ShippingSite(STOFCY)={shippingSite}");

                var resolved = (salesSite, shippingSite);
                _siteMappingCache[cacheKey] = resolved;
                return resolved;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SageX3SoapService] Warning: Failed to resolve FACILITY mapping for {cleanSite} in {schema}: {ex.Message}");
                if (string.Equals(cleanSite, "POD", StringComparison.OrdinalIgnoreCase))
                {
                    salesSite = "POD";
                    shippingSite = "POD";
                }
                return (salesSite, shippingSite);
            }
        }

        private async Task<(string TabletName, string? AssignedWarehouse, string? AssignedLocation)> ResolveDeviceIdentityAsync(
            string? rawTabletSource,
            string? rawDeviceId,
            string? userName,
            string? siteCode = null)
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
            var cleanSite = (siteCode ?? string.Empty).Trim();

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

                if (matched == null && !string.IsNullOrEmpty(cleanSite) && !string.Equals(cleanSite, "ALL", StringComparison.OrdinalIgnoreCase))
                {
                    matched = activeDevices.FirstOrDefault(d =>
                        string.Equals(d.SiteCode?.Trim(), cleanSite, StringComparison.OrdinalIgnoreCase) &&
                        !string.IsNullOrWhiteSpace(d.LocationCode));
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

        private async Task<Dictionary<string, List<string>>> GetSiteWarehousesMapAsync(string schema)
        {
            string cacheKey = schema.ToUpperInvariant();
            if (_siteWarehousesCache.TryGetValue(cacheKey, out var cached))
            {
                return cached;
            }

            var candidateSchemas = new[] { schema, "X3", "INL" }
                .Where(s => !string.IsNullOrWhiteSpace(s))
                .Distinct(StringComparer.OrdinalIgnoreCase);

            var map = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
            try
            {
                using var connection = new SqlConnection(_innodisConnectionString);
                foreach (var candSchema in candidateSchemas)
                {
                    // 1. Primary: STOCK table contains actual physical site-to-warehouse mappings
                    try
                    {
                        string sqlStock = $@"
                            SELECT DISTINCT 
                                LTRIM(RTRIM(STOFCY_0)) AS SiteCode,
                                LTRIM(RTRIM(WRH_0)) AS WarehouseCode
                            FROM x3.{candSchema}.STOCK WITH (NOLOCK)
                            WHERE LTRIM(RTRIM(ISNULL(WRH_0, ''))) <> ''
                              AND LTRIM(RTRIM(ISNULL(STOFCY_0, ''))) <> '';";

                        var rows = await connection.QueryAsync(sqlStock);
                        foreach (var r in rows)
                        {
                            string site = ((string?)r.SiteCode ?? "").Trim();
                            string wrh = ((string?)r.WarehouseCode ?? "").Trim();
                            if (string.IsNullOrEmpty(site) || string.IsNullOrEmpty(wrh)) continue;

                            if (!map.ContainsKey(site)) map[site] = new List<string>();
                            if (!map[site].Contains(wrh, StringComparer.OrdinalIgnoreCase))
                                map[site].Add(wrh);
                        }
                    }
                    catch { }

                    // 2. Secondary: ITMFACIL contains default warehouses per product-site
                    try
                    {
                        string sqlFacil = $@"
                            SELECT DISTINCT 
                                LTRIM(RTRIM(STOFCY_0)) AS SiteCode,
                                LTRIM(RTRIM(DEFWRH_0)) AS WarehouseCode
                            FROM x3.{candSchema}.ITMFACIL WITH (NOLOCK)
                            WHERE LTRIM(RTRIM(ISNULL(DEFWRH_0, ''))) <> ''
                              AND LTRIM(RTRIM(ISNULL(STOFCY_0, ''))) <> '';";

                        var rows = await connection.QueryAsync(sqlFacil);
                        foreach (var r in rows)
                        {
                            string site = ((string?)r.SiteCode ?? "").Trim();
                            string wrh = ((string?)r.WarehouseCode ?? "").Trim();
                            if (string.IsNullOrEmpty(site) || string.IsNullOrEmpty(wrh)) continue;

                            if (!map.ContainsKey(site)) map[site] = new List<string>();
                            if (!map[site].Contains(wrh, StringComparer.OrdinalIgnoreCase))
                                map[site].Add(wrh);
                        }
                    }
                    catch { }

                    // 3. Fallback: Check if TABWRH has site or prefix matches
                    try
                    {
                        var allWrhs = await GetValidWarehousesAsync(candSchema);
                        if (allWrhs != null && allWrhs.Any())
                        {
                            // If CGD has warehouse CG1 or similar in TABWRH
                            foreach (var w in allWrhs)
                            {
                                if (w.StartsWith("CG", StringComparison.OrdinalIgnoreCase))
                                {
                                    if (!map.ContainsKey("CGD")) map["CGD"] = new List<string>();
                                    if (!map["CGD"].Contains(w, StringComparer.OrdinalIgnoreCase)) map["CGD"].Add(w);
                                }
                                else if (w.StartsWith("PO", StringComparison.OrdinalIgnoreCase) || w.StartsWith("PD", StringComparison.OrdinalIgnoreCase))
                                {
                                    if (!map.ContainsKey("POD")) map["POD"] = new List<string>();
                                    if (!map["POD"].Contains(w, StringComparer.OrdinalIgnoreCase)) map["POD"].Add(w);
                                }
                            }
                        }
                    }
                    catch { }

                    if (map.Count > 0) break;
                }

                _siteWarehousesCache[cacheKey] = map;
                Console.WriteLine($"[SageX3SoapService] Loaded site warehouse mapping for {schema}: {map.Count} site(s) with warehouses.");
                return map;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SageX3SoapService] Site warehouse lookup notice for {schema}: {ex.Message}");
                return map;
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

        private static string FormatClean2Dp(double val)
        {
            decimal rounded = Math.Round((decimal)val, 2, MidpointRounding.AwayFromZero);
            return (rounded % 1 == 0)
                ? rounded.ToString("F0", System.Globalization.CultureInfo.InvariantCulture)
                : rounded.ToString("0.##", System.Globalization.CultureInfo.InvariantCulture);
        }

        private async Task<Dictionary<string, List<StockSlot>>> GetShippingSiteStockAsync(
            string schema,
            string shippingSite,
            IEnumerable<string?> itemCodes,
            string? preferredLorry = null)
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

                var cleanLorry = (preferredLorry ?? string.Empty).Trim().ToUpperInvariant();
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
                    ORDER BY
                        CASE
                            WHEN @Lorry = '' THEN 1
                            WHEN LTRIM(RTRIM(ISNULL(stk.LOC_0, ''))) = @Lorry
                              OR LTRIM(RTRIM(ISNULL(stk.WRH_0, ''))) = @Lorry THEN 0
                            ELSE 1
                        END,
                        COALESCE(MIN(sl.SHLDAT_0), '9999-12-31') ASC,
                        LTRIM(RTRIM(ISNULL(stk.LOT_0, ''))) ASC";

                var rows = await connection.QueryAsync(
                    sql,
                    new
                    {
                        ShippingSite = shippingSite.Trim().ToUpperInvariant(),
                        ItemCodes = validCodes,
                        Lorry = cleanLorry
                    });
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

        private sealed class MutableStockSlot
        {
            public string Warehouse { get; init; } = string.Empty;
            public string Location { get; init; } = string.Empty;
            public string LotNumber { get; init; } = string.Empty;
            public double RemainingQty { get; set; }
        }

        public static bool AllocateInvoiceLinesByLot(
            StagingSalesInvoiceHeader invoice,
            Dictionary<string, List<StockSlot>> siteStockMap,
            string? assignedWarehouse,
            string? assignedLocation)
        {
            if (invoice.Lines == null || invoice.Lines.Count == 0 || siteStockMap == null || siteStockMap.Count == 0)
            {
                return false;
            }

            var remainingBySku = new Dictionary<string, List<MutableStockSlot>>(StringComparer.OrdinalIgnoreCase);
            foreach (var kvp in siteStockMap)
            {
                remainingBySku[kvp.Key] = kvp.Value
                    .Where(s => s.Qty > 0)
                    .Select(s => new MutableStockSlot
                    {
                        Warehouse = s.Warehouse,
                        Location = s.Location,
                        LotNumber = s.LotNumber,
                        RemainingQty = (double)s.Qty
                    })
                    .ToList();
            }

            bool anyModified = false;
            var rebuiltLines = new List<StagingSalesInvoiceLine>(invoice.Lines.Count);

            foreach (var src in invoice.Lines.ToList())
            {
                string sku = (src.Sku ?? string.Empty).Trim();
                if (string.IsNullOrEmpty(sku) || src.Quantity <= 0.0001 || !remainingBySku.TryGetValue(sku, out var skuSlots) || skuSlots.Count == 0)
                {
                    rebuiltLines.Add(src);
                    continue;
                }

                string lineLoc = IsPlaceholderStockToken(src.Location) ? string.Empty : (src.Location ?? string.Empty).Trim();
                string lineWrh = IsPlaceholderStockToken(src.Warehouse) ? string.Empty : (src.Warehouse ?? string.Empty).Trim();
                string targetLorry = !string.IsNullOrWhiteSpace(assignedLocation)
                    ? assignedLocation.Trim()
                    : (!string.IsNullOrWhiteSpace(assignedWarehouse)
                        ? assignedWarehouse.Trim()
                        : (!string.IsNullOrWhiteSpace(lineLoc) ? lineLoc : lineWrh));

                List<MutableStockSlot> candidateSlots;
                if (!string.IsNullOrWhiteSpace(targetLorry))
                {
                    candidateSlots = skuSlots
                        .Where(s => string.Equals(s.Location, targetLorry, StringComparison.OrdinalIgnoreCase)
                                 || string.Equals(s.Warehouse, targetLorry, StringComparison.OrdinalIgnoreCase))
                        .ToList();
                }
                else
                {
                    candidateSlots = skuSlots;
                }

                if (candidateSlots.Count == 0)
                {
                    rebuiltLines.Add(src);
                    continue;
                }

                string preferredLot = (src.LotNumber ?? string.Empty).Trim();
                var orderedSlots = new List<MutableStockSlot>(candidateSlots.Count);
                if (!string.IsNullOrWhiteSpace(preferredLot))
                {
                    orderedSlots.AddRange(candidateSlots.Where(s => string.Equals(s.LotNumber, preferredLot, StringComparison.OrdinalIgnoreCase)));
                    orderedSlots.AddRange(candidateSlots.Where(s => !string.Equals(s.LotNumber, preferredLot, StringComparison.OrdinalIgnoreCase)));
                }
                else
                {
                    orderedSlots.AddRange(candidateSlots);
                }

                var chunks = new List<(string LotNumber, string Warehouse, string Location, double Qty)>();
                double remainingNeed = src.Quantity;

                foreach (var slot in orderedSlots)
                {
                    if (remainingNeed <= 0.0001) break;
                    if (slot.RemainingQty <= 0.0001) continue;

                    double take = Math.Min(remainingNeed, slot.RemainingQty);
                    take = Math.Round(take, 4, MidpointRounding.AwayFromZero);
                    if (take <= 0.0001) continue;

                    slot.RemainingQty = Math.Round(slot.RemainingQty - take, 4, MidpointRounding.AwayFromZero);
                    remainingNeed = Math.Round(remainingNeed - take, 4, MidpointRounding.AwayFromZero);

                    string resolvedWrh = !string.IsNullOrWhiteSpace(slot.Warehouse) ? slot.Warehouse : lineWrh;
                    string resolvedLoc = !string.IsNullOrWhiteSpace(slot.Location) ? slot.Location : lineLoc;
                    chunks.Add((slot.LotNumber, resolvedWrh, resolvedLoc, take));
                }

                if (chunks.Count == 0)
                {
                    // Insufficient available X3 stock slots to allocate: keep existing line untouched so billed total is preserved
                    rebuiltLines.Add(src);
                    continue;
                }

                if (remainingNeed > 0.0001)
                {
                    // Append unallocated tail to the last matched chunk so financial total is never silently reduced
                    var lastIdx = chunks.Count - 1;
                    var last = chunks[lastIdx];
                    chunks[lastIdx] = (last.LotNumber, last.Warehouse, last.Location, Math.Round(last.Qty + remainingNeed, 4, MidpointRounding.AwayFromZero));
                }

                if (chunks.Count == 1)
                {
                    var only = chunks[0];
                    if (string.IsNullOrWhiteSpace(src.LotNumber) && !string.IsNullOrWhiteSpace(only.LotNumber))
                    {
                        src.LotNumber = only.LotNumber;
                        anyModified = true;
                    }
                    if (string.IsNullOrWhiteSpace(src.Warehouse) && !string.IsNullOrWhiteSpace(only.Warehouse))
                    {
                        src.Warehouse = only.Warehouse;
                        anyModified = true;
                    }
                    if (string.IsNullOrWhiteSpace(src.Location) && !string.IsNullOrWhiteSpace(only.Location))
                    {
                        src.Location = only.Location;
                        anyModified = true;
                    }
                    rebuiltLines.Add(src);
                    continue;
                }

                // Multi-lot split: mutate first existing line in-place and append additional split lines
                anyModified = true;
                double totalSrcQty = src.Quantity;
                double origDiscAmt = src.DiscountAmount;
                double origDiscFlat = src.DiscountAmountFlat;
                double origDisc2 = src.Discount2;
                double origDisc3 = src.Discount3;
                double origVat = src.VatAmount;
                double origTotal = src.Total;

                double accDiscAmt = 0, accDiscFlat = 0, accDisc2 = 0, accDisc3 = 0, accVat = 0, accTotal = 0;

                for (int i = 0; i < chunks.Count; i++)
                {
                    var c = chunks[i];
                    bool isLast = (i == chunks.Count - 1);
                    double ratio = totalSrcQty > 0 ? (c.Qty / totalSrcQty) : 0;

                    double Prorate(double orig, ref double acc)
                    {
                        if (isLast)
                        {
                            return Math.Round(Math.Max(0, orig - acc), 2, MidpointRounding.AwayFromZero);
                        }
                        double share = Math.Round(orig * ratio, 2, MidpointRounding.AwayFromZero);
                        acc += share;
                        return share;
                    }

                    double lDiscAmt = Prorate(origDiscAmt, ref accDiscAmt);
                    double lDiscFlat = Prorate(origDiscFlat, ref accDiscFlat);
                    double lDisc2 = Prorate(origDisc2, ref accDisc2);
                    double lDisc3 = Prorate(origDisc3, ref accDisc3);
                    double lVat = Prorate(origVat, ref accVat);
                    double lTotal = Prorate(origTotal, ref accTotal);

                    if (i == 0)
                    {
                        src.Quantity = c.Qty;
                        src.LotNumber = c.LotNumber;
                        if (!string.IsNullOrWhiteSpace(c.Warehouse)) src.Warehouse = c.Warehouse;
                        if (!string.IsNullOrWhiteSpace(c.Location)) src.Location = c.Location;
                        src.DiscountAmount = lDiscAmt;
                        src.DiscountAmountFlat = lDiscFlat;
                        src.Discount2 = lDisc2;
                        src.Discount3 = lDisc3;
                        src.VatAmount = lVat;
                        src.Total = lTotal;
                        rebuiltLines.Add(src);
                    }
                    else
                    {
                        rebuiltLines.Add(new StagingSalesInvoiceLine
                        {
                            InvoiceId = src.InvoiceId,
                            LineNo = src.LineNo,
                            Sku = src.Sku,
                            Name = src.Name,
                            Quantity = c.Qty,
                            BasePrice = src.BasePrice,
                            DiscountAmount = lDiscAmt,
                            DiscountAmountFlat = lDiscFlat,
                            Discount2 = lDisc2,
                            Discount3 = lDisc3,
                            VatAmount = lVat,
                            Total = lTotal,
                            LotNumber = c.LotNumber,
                            Warehouse = !string.IsNullOrWhiteSpace(c.Warehouse) ? c.Warehouse : src.Warehouse,
                            Location = !string.IsNullOrWhiteSpace(c.Location) ? c.Location : src.Location,
                            SalesUnit = src.SalesUnit,
                            Cce0 = src.Cce0,
                            TaxRule = src.TaxRule,
                            StockStatus = src.StockStatus,
                            ReturnCondition = src.ReturnCondition,
                            ExpiryDate = src.ExpiryDate,
                            IsFoc = src.IsFoc,
                            MainItemSku = src.MainItemSku,
                            OriginLineNo = src.OriginLineNo
                        });
                    }
                }
            }

            if (anyModified)
            {
                int seqLineNo = 1;
                foreach (var l in rebuiltLines)
                {
                    l.LineNo = seqLineNo++;
                }
                invoice.Lines = rebuiltLines;
            }

            return anyModified;
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

                            List<(Dictionary<string, object> Row, string Field)> sDicts = new();
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
                                    if (string.Equals(idVal, "S", StringComparison.OrdinalIgnoreCase))
                                    {
                                        sDicts.Add((ci, fldVal));
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
                                    var layout = new TemplateDetailLayout();
                                    if (dDicts.Any())
                                    {
                                        var sortedD = (verifiedWithLev
                                                ? dDicts.OrderBy(d => TryExtractDecimal(d.Row, "LEV_0", out var lv) ? lv : 0m)
                                                        .ThenBy(d => TryExtractDecimal(d.Row, verifiedRankCol, out var rk) ? rk : 0m)
                                                : dDicts.OrderBy(d => TryExtractDecimal(d.Row, verifiedRankCol, out var rk) ? rk : 0m))
                                            .Select(d => d.Field)
                                            .ToList();
                                        layout.DFields.AddRange(sortedD);
                                        Console.WriteLine($"[SageX3SoapService] Discovered {sortedD.Count} D-line fields for {templateCode} in {candSchema}: {string.Join(", ", sortedD)}");
                                    }
                                    if (sDicts.Any())
                                    {
                                        var sortedS = (verifiedWithLev
                                                ? sDicts.OrderBy(s => TryExtractDecimal(s.Row, "LEV_0", out var lv) ? lv : 0m)
                                                        .ThenBy(s => TryExtractDecimal(s.Row, verifiedRankCol, out var rk) ? rk : 0m)
                                                : sDicts.OrderBy(s => TryExtractDecimal(s.Row, verifiedRankCol, out var rk) ? rk : 0m))
                                            .Select(s => s.Field)
                                            .ToList();
                                        layout.SFields.AddRange(sortedS);
                                        Console.WriteLine($"[SageX3SoapService] Discovered {sortedS.Count} S-line fields for {templateCode} in {candSchema}: {string.Join(", ", sortedS)}");
                                    }
                                    _templateDetailLayoutCache[cacheKey] = layout;
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

        private string ConstructDynamicVHeader(List<string> templateFields, Dictionary<string, string> values, string fallbackHeader) =>
            ConstructDynamicRecord("V", templateFields, values, fallbackHeader, logTag: "Constructed Dynamic V Header");

        private static string ConstructDynamicRecord(
            string recordId,
            List<string> templateFields,
            Dictionary<string, string> values,
            string fallbackRecord,
            string? logTag = null)
        {
            if (templateFields == null || templateFields.Count == 0)
            {
                return fallbackRecord;
            }

            var parts = new List<string> { recordId };
            int repIndex = 0;

            foreach (var rawField in templateFields)
            {
                var f = (rawField ?? string.Empty).Trim();
                if (string.Equals(f, recordId, StringComparison.OrdinalIgnoreCase)) continue;

                // "/" opens the record; a second "/" opens the next record in AOED.
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
            if (!string.IsNullOrEmpty(logTag))
            {
                Console.WriteLine($"[SageX3SoapService] {logTag}: {line}");
            }
            return line;
        }

        private static string ResolveGeneratedDocNumber(StagingSalesInvoiceHeader header, string fallbackReference)
        {
            string candidate = !string.IsNullOrWhiteSpace(header.InvoiceId)
                ? header.InvoiceId.Trim()
                : (!string.IsNullOrWhiteSpace(header.TransactionalId)
                    ? header.TransactionalId.Trim()
                    : (fallbackReference ?? string.Empty).Trim());
            return candidate.Length > 20 ? candidate.Substring(0, 20) : candidate;
        }

        private static bool IsDuplicateKeySoapResult(X3ImportResult res)
        {
            var combined = $"{res.TechnicalError} {string.Join(" ", res.Messages ?? new List<string>())} {res.RawPayload}";
            return combined.Contains("already exists", StringComparison.OrdinalIgnoreCase)
                || combined.Contains("Record already", StringComparison.OrdinalIgnoreCase)
                || combined.Contains("Duplicate", StringComparison.OrdinalIgnoreCase)
                || combined.Contains("existant", StringComparison.OrdinalIgnoreCase);
        }

        private async Task<string?> TryVerifySinvoiceExistsInX3Async(string schema, string docNumber, string? expectedCustomerCode)
        {
            if (string.IsNullOrWhiteSpace(docNumber)) return null;
            try
            {
                using var conn = new SqlConnection(_innodisConnectionString);
                await conn.OpenAsync();
                foreach (var candSchema in new[] { schema, "INLDRYRUN", "INL", "X3" }.Where(s => !string.IsNullOrWhiteSpace(s)).Distinct(StringComparer.OrdinalIgnoreCase))
                {
                    try
                    {
                        var found = await conn.QueryFirstOrDefaultAsync<string>(
                            $@"SELECT TOP 1 LTRIM(RTRIM(NUM_0))
                               FROM x3.{candSchema}.SINVOICE WITH (NOLOCK)
                               WHERE LTRIM(RTRIM(NUM_0)) = @DocNum
                                 AND (@Cust = '' OR LTRIM(RTRIM(BPCINV_0)) = @Cust)",
                            new { DocNum = docNumber.Trim(), Cust = (expectedCustomerCode ?? string.Empty).Trim() });
                        if (!string.IsNullOrWhiteSpace(found))
                        {
                            return found.Trim();
                        }
                    }
                    catch { }
                }
            }
            catch { }
            return null;
        }

        private async Task<string?> TryVerifySmvthExistsInX3Async(string schema, string docNumber, string? vcrDes = null)
        {
            try
            {
                using var verifyConn = new SqlConnection(_innodisConnectionString);
                await verifyConn.OpenAsync();
                foreach (var candSchema in new[] { schema, "INLDRYRUN", "INL", "X3" }.Where(s => !string.IsNullOrWhiteSpace(s)).Distinct(StringComparer.OrdinalIgnoreCase))
                {
                    try
                    {
                        if (!string.IsNullOrWhiteSpace(docNumber))
                        {
                            var byNum = await verifyConn.QueryFirstOrDefaultAsync<string>(
                                $@"SELECT TOP 1 LTRIM(RTRIM(VCRNUM_0))
                                   FROM x3.{candSchema}.SMVTH WITH (NOLOCK)
                                   WHERE VCRTYP_0 = 19
                                     AND LTRIM(RTRIM(VCRNUM_0)) = @DocNum
                                   ORDER BY CREDAT_0 DESC, ROWID DESC",
                                new { DocNum = docNumber.Trim() });
                            if (!string.IsNullOrWhiteSpace(byNum))
                            {
                                return byNum.Trim();
                            }
                        }

                        if (!string.IsNullOrWhiteSpace(vcrDes))
                        {
                            var byDes = await verifyConn.QueryFirstOrDefaultAsync<string>(
                                $@"SELECT TOP 1 LTRIM(RTRIM(VCRNUM_0))
                                   FROM x3.{candSchema}.SMVTH WITH (NOLOCK)
                                   WHERE VCRTYP_0 = 19
                                     AND LTRIM(RTRIM(VCRDES_0)) = @VcrDes
                                   ORDER BY CREDAT_0 DESC, ROWID DESC",
                                new { VcrDes = vcrDes.Trim() });
                            if (!string.IsNullOrWhiteSpace(byDes))
                            {
                                return byDes.Trim();
                            }
                        }
                    }
                    catch { }
                }
            }
            catch { }
            return null;
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

                // Authoritative Tenancy: Use user login site claim as primary Sales Site (SALFCY), then map Shipping/Financial Site (STOFCY)
                var userSiteCode = _httpContextAccessor.HttpContext?.User?.FindFirst("SiteCode")?.Value;
                string requestedSite = (!string.IsNullOrWhiteSpace(userSiteCode) && userSiteCode != "ALL")
                    ? userSiteCode
                    : (!string.IsNullOrWhiteSpace(invoice.SalesSite) && invoice.SalesSite != "ALL" ? invoice.SalesSite : "POD");

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
                    invoice.UserName ?? invoice.CreatedBy,
                    shippingSite);

                // Sage X3 sales invoice type:
                // MICAS for cash transaction on invoice
                // MICRE for credit transaction on invoice
                bool isCreditInvoice = (invoice.Payments != null && invoice.Payments.Any(p => string.Equals(p.PaymentMethod, "CREDIT", StringComparison.OrdinalIgnoreCase)))
                    || string.Equals(invoice.InvoiceType, "CREDIT", StringComparison.OrdinalIgnoreCase)
                    || string.Equals(invoice.PaymentTerm, "CREDIT", StringComparison.OrdinalIgnoreCase);

                string invType = isCreditInvoice ? "MICRE" : "MICAS";

                string originDocNum = !string.IsNullOrWhiteSpace(invoice.OriginInvoiceId) ? invoice.OriginInvoiceId.Trim() : "";
                string docNumber = ResolveGeneratedDocNumber(invoice, reference);

                // Proven 18-position layout matching Syracuse ZSIHWEBA template (Image 2, lines 1-18):
                // Pos 1: V | Pos 2: SALFCY | Pos 3: SIVTYP | Pos 4: STOFCY | Pos 5: INVTYP (1) | Pos 6: NUM (docNumber) | Pos 7: BPCINV | Pos 8: ACCDAT | Pos 9: INVREF (reference)
                // Pos 10: STOMVTFLG (2) | Pos 11: REP | Pos 12: CUR (MUR) | Pos 13: STRDUDDAT | Pos 14: blank | Pos 15: blank | Pos 16: SIHORI (1) | Pos 17: SIHORINUM (originDocNum) | Pos 18: ZTABLETSRC
                string invoiceHeader = $"V;{salesSite};{invType};{shippingSite};1;{docNumber};{invoice.CustomerCode};{invoiceDate};{reference};2;{primarySalesRep};MUR;{dueDate};;;1;{originDocNum};{tabletSource};|";
                fileBuilder.Append(invoiceHeader);

                // Pre-resolve item metadata, valid TABWRH warehouses, ZSIHWEBA AOED layout & STOCK in shippingSite
                string preferredLorry = !string.IsNullOrWhiteSpace(assignedLocation)
                    ? assignedLocation.Trim()
                    : (!string.IsNullOrWhiteSpace(assignedWarehouse) ? assignedWarehouse.Trim() : string.Empty);
                var itemMetadata = await GetItemMetadataAsync(invoice.Lines.Select(l => l.Sku));
                var validWarehouses = await GetValidWarehousesAsync(schema);
                var siteWarehousesMap = await GetSiteWarehousesMapAsync(schema);
                bool isWarehouseManaged = siteWarehousesMap.TryGetValue(shippingSite, out var validSiteWrhs) && validSiteWrhs.Any();
                var siteStockMap = await GetShippingSiteStockAsync(schema, shippingSite, invoice.Lines.Select(l => l.Sku), preferredLorry);

                // Expand/allocate any single multi-lot or unassigned-lot line across actual lorry STOCK lots
                // and keep StagingSalesInvoiceLines synchronized with the split lot breakdown.
                bool wasSplitOrAllocated = AllocateInvoiceLinesByLot(invoice, siteStockMap, assignedWarehouse, assignedLocation);
                if (wasSplitOrAllocated && _context.Entry(invoice).State != EntityState.Detached)
                {
                    await _context.SaveChangesAsync();
                }

                // Trigger AOED introspection once per schema so any ZSIHWEBA D/S lot fields are cached
                await GetTemplateHeaderFieldsAsync("ZSIHWEBA", schema);
                _templateDetailLayoutCache.TryGetValue($"{schema}_ZSIHWEBA".ToUpperInvariant(), out var templateDetailLayout);

                // Pre-identify Source lines (FOCFLG = 2) and Free lines (FOCFLG = 3)
                var freeLines = invoice.Lines
                    .Where(l => l.IsFoc || (l.BasePrice == 0 && l.Quantity > 0))
                    .ToList();

                var sourceLineNos = new HashSet<int>();
                if (freeLines.Any())
                {
                    var linesList = invoice.Lines.ToList();
                    foreach (var fl in freeLines)
                    {
                        // 1. Check by explicit OriginLineNo
                        if (fl.OriginLineNo.HasValue && fl.OriginLineNo.Value > 0)
                        {
                            sourceLineNos.Add(fl.OriginLineNo.Value);
                            continue;
                        }

                        // 2. Check by explicit MainItemSku (mark ALL split paid lot lines for that SKU)
                        if (!string.IsNullOrWhiteSpace(fl.MainItemSku))
                        {
                            var matchedPaid = linesList.Where(l =>
                                !l.IsFoc && l.BasePrice > 0 &&
                                string.Equals(l.Sku, fl.MainItemSku, StringComparison.OrdinalIgnoreCase)).ToList();
                            if (matchedPaid.Any())
                            {
                                foreach (var mp in matchedPaid)
                                {
                                    sourceLineNos.Add(mp.LineNo);
                                }
                                continue;
                            }
                        }

                        // 3. Positional fallback: Preceding promotional paid line(s) in cart
                        int idx = linesList.IndexOf(fl);
                        if (idx > 0)
                        {
                            for (int p = idx - 1; p >= 0; p--)
                            {
                                if (!linesList[p].IsFoc && linesList[p].BasePrice > 0)
                                {
                                    sourceLineNos.Add(linesList[p].LineNo);
                                    break;
                                }
                            }
                        }
                    }
                }

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

                    // Clean 2-dp formatting: Keep integers clean (72, 185, 0) and decimals to 2-dp (1270.88, 29.03)
                    string qty = FormatClean2Dp(line.Quantity);
                    string basePrice = FormatClean2Dp(line.BasePrice);

                    // Discount routing: User confirmed "populate disc amt keep others blank"
                    // DISCRGVAL3 (Position 10) is "Disc - Amt". It receives the discount amount in Rs (e.g. 0.91 or 29.03).
                    // DISCRGVAL1 (Position 8, "Disc1 - %") and DISCRGVAL2 (Position 9, "Disc2 - %") remain 0.
                    double discAmt = line.DiscountAmount > 0 
                        ? line.DiscountAmount 
                        : (line.Discount3 > 0 ? line.Discount3 : (line.DiscountAmountFlat > 0 ? line.DiscountAmountFlat : 0.0));

                    string disc1 = "0";
                    string disc2 = "0";
                    string disc3 = FormatClean2Dp(discAmt);

                    // Authoritative User Selection & Warehouse resolution
                    string locationInput = IsPlaceholderStockToken(line.Location) ? "" : (line.Location ?? "").Trim();
                    string inputWarehouse = IsPlaceholderStockToken(line.Warehouse) ? "" : (line.Warehouse ?? "").Trim();

                    string warehouse = !string.IsNullOrWhiteSpace(inputWarehouse)
                        ? inputWarehouse
                        : (!string.IsNullOrWhiteSpace(assignedWarehouse)
                            ? assignedWarehouse
                            : (!string.IsNullOrWhiteSpace(assignedLocation) ? assignedLocation : "N3"));

                    if (isWarehouseManaged && validSiteWrhs != null && validSiteWrhs.Any())
                    {
                        if (!validSiteWrhs.Contains(warehouse, StringComparer.OrdinalIgnoreCase))
                        {
                            if (!string.IsNullOrWhiteSpace(assignedLocation) && validSiteWrhs.Contains(assignedLocation.Trim(), StringComparer.OrdinalIgnoreCase))
                            {
                                warehouse = assignedLocation.Trim();
                            }
                            else if (!string.IsNullOrWhiteSpace(assignedWarehouse) && validSiteWrhs.Contains(assignedWarehouse.Trim(), StringComparer.OrdinalIgnoreCase))
                            {
                                warehouse = assignedWarehouse.Trim();
                            }
                            else
                            {
                                warehouse = validSiteWrhs.First();
                            }
                        }
                    }

                    string location = "";
                    if (!string.IsNullOrWhiteSpace(locationInput) && !string.Equals(locationInput, warehouse, StringComparison.OrdinalIgnoreCase))
                    {
                        location = locationInput;
                    }

                    // Line Sales Reps: REP1 (Line 32) and REP2 (Line 33)
                    string lineRep1 = !string.IsNullOrWhiteSpace(primarySalesRep) ? primarySalesRep : "";
                    string lineRep2 = !string.IsNullOrWhiteSpace(secondarySalesRep) ? secondarySalesRep : lineRep1;

                    // Sage X3 Local Menu for FOCFLG: 1 = No, 2 = Source (Qualifying Item), 3 = Yes (Free Gift Item)
                    string focFlg;
                    if (line.IsFoc || (line.BasePrice == 0 && line.Quantity > 0))
                    {
                        focFlg = "3"; // Free item (Yes in Sage X3)
                    }
                    else if (sourceLineNos.Contains(line.LineNo))
                    {
                        focFlg = "2"; // Source item (Source in Sage X3)
                    }
                    else
                    {
                        focFlg = "1"; // Regular paid item (No in Sage X3)
                    }

                    string lotNum = (line.LotNumber ?? string.Empty).Trim();

                    // Proven 18-position D-Record layout matching Syracuse ZSIHWEBA (lines 19-36), extended safely when AOED declares D.LOT or an S sub-record
                    string fallbackD = $"D;{lineMultiplier};{sku};{safeLineName};{unit};{qty};{basePrice};{disc1};{disc2};{disc3};{taxRule};;0;{lineRep1};{lineRep2};{warehouse};{location};{focFlg};|";
                    if (templateDetailLayout?.DFields != null &&
                        templateDetailLayout.DFields.Any(f =>
                        {
                            var k = NormalizeTemplateFieldKey(f);
                            return k == "LOT" || k == "LOTNUM";
                        }))
                    {
                        var dValues = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
                        {
                            { "SIDLIN", lineMultiplier.ToString() },
                            { "NUMLIG", lineMultiplier.ToString() },
                            { "ITMREF", sku },
                            { "ITMDES", safeLineName },
                            { "ITMDES1", safeLineName },
                            { "SAU", unit },
                            { "PCU", unit },
                            { "QTY", qty },
                            { "QTYSTU", qty },
                            { "QTYPCU", qty },
                            { "GROPRI", basePrice },
                            { "NETPRI", basePrice },
                            { "DISCRGVAL1", disc1 },
                            { "DISC1", disc1 },
                            { "DISCRGVAL2", disc2 },
                            { "DISC2", disc2 },
                            { "DISCRGVAL3", disc3 },
                            { "DISC3", disc3 },
                            { "VACITM", taxRule },
                            { "ZPRIUOM", "" },
                            { "ZPRIQTY", "0" },
                            { "REP", lineRep1 },
                            { "REP1", lineRep1 },
                            { "REP_1", lineRep2 },
                            { "REP2", lineRep2 },
                            { "WRH", warehouse },
                            { "LOC", location },
                            { "FOCFLG", focFlg },
                            { "LOT", lotNum },
                            { "LOTNUM", lotNum },
                            { "STA", "A" },
                        };
                        fileBuilder.Append(ConstructDynamicRecord("D", templateDetailLayout.DFields, dValues, fallbackD));
                    }
                    else
                    {
                        fileBuilder.Append(fallbackD);
                    }

                    if (templateDetailLayout?.SFields != null &&
                        templateDetailLayout.SFields.Count > 1 &&
                        !string.IsNullOrWhiteSpace(lotNum))
                    {
                        string sLoc = !string.IsNullOrWhiteSpace(locationInput) ? locationInput : warehouse;
                        var sValues = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
                        {
                            { "PCU", unit },
                            { "SAU", unit },
                            { "STU", unit },
                            { "QTYPCU", qty },
                            { "QTYSTU", qty },
                            { "QTY", qty },
                            { "PCUSTUCOE", "1" },
                            { "LOT", lotNum },
                            { "LOTNUM", lotNum },
                            { "LOC", sLoc },
                            { "WRH", warehouse },
                            { "STA", "A" },
                        };
                        fileBuilder.Append(ConstructDynamicRecord("S", templateDetailLayout.SFields, sValues, string.Empty));
                    }

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

                // Verify created document directly in SINVOICE if X3 returned REQ-* or a duplicate-key retry after a crash
                if (!string.IsNullOrWhiteSpace(docNumber) &&
                    ((parsedResult.Success && (string.IsNullOrWhiteSpace(parsedResult.DocumentId) || parsedResult.DocumentId.StartsWith("REQ-", StringComparison.OrdinalIgnoreCase)))
                     || (!parsedResult.Success && IsDuplicateKeySoapResult(parsedResult))))
                {
                    var verifiedNum = await TryVerifySinvoiceExistsInX3Async(schema, docNumber, invoice.CustomerCode);
                    if (!string.IsNullOrWhiteSpace(verifiedNum))
                    {
                        parsedResult.DocumentId = verifiedNum;
                        parsedResult.Success = true;
                    }
                }
                
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
                string requestedCrnSite;
                if (!string.IsNullOrWhiteSpace(creditNote.OriginInvoiceId))
                {
                    // For linked credit note / return, the sales site MUST strictly match the origin invoice
                    string? originSite = null;
                    try
                    {
                        using var originConn = new SqlConnection(_innodisConnectionString);
                        originSite = await originConn.QueryFirstOrDefaultAsync<string>(
                            $"SELECT TOP 1 LTRIM(RTRIM(SALFCY_0)) FROM x3.{crnSchema}.SINVOICE WHERE NUM_0 = @DocId",
                            new { DocId = creditNote.OriginInvoiceId.Trim() });
                    }
                    catch { }

                    requestedCrnSite = !string.IsNullOrWhiteSpace(originSite)
                        ? originSite.Trim()
                        : (!string.IsNullOrWhiteSpace(creditNote.SalesSite) && creditNote.SalesSite != "ALL"
                            ? creditNote.SalesSite.Trim()
                            : (!string.IsNullOrWhiteSpace(userSiteCode) && userSiteCode != "ALL" ? userSiteCode : "POD"));
                }
                else
                {
                    requestedCrnSite = (!string.IsNullOrWhiteSpace(userSiteCode) && userSiteCode != "ALL")
                        ? userSiteCode
                        : (!string.IsNullOrWhiteSpace(creditNote.SalesSite) && creditNote.SalesSite != "ALL" ? creditNote.SalesSite : "POD");
                }

                var (salesSite, shippingSite) = await ResolveSiteMappingAsync(requestedCrnSite, crnSchema);
                // Sage X3 sales invoice type for credit notes AND returns:
                // MRCAS for credit note / return where cash is refunded
                // MRCRE for credit note / return where credit on account is refunded
                bool hasExplicitCreditSettlement = string.Equals(creditNote.SettlementType, "CREDIT", StringComparison.OrdinalIgnoreCase);
                bool isCashRefund = !hasExplicitCreditSettlement && (
                    string.Equals(creditNote.SettlementType, "CASH", StringComparison.OrdinalIgnoreCase)
                    || (creditNote.Payments != null && creditNote.Payments.Any(p =>
                        string.Equals(p.PaymentMethod, "CASH", StringComparison.OrdinalIgnoreCase) ||
                        string.Equals(p.PaymentMethod, "CSH", StringComparison.OrdinalIgnoreCase))));

                string crnType = isCashRefund ? "MRCAS" : "MRCRE";

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
                // Always 1 (No stock movement) on ZSCRWEB because physical stock reinstatement (both Q and A)
                // is explicitly imported via SOAP 3 (ZSMRWEBA) to ensure 100% quantity and quality status isolation.
                int stockTransaction = 1;

                var (tabletSource, crnAssignedWarehouse, _) = await ResolveDeviceIdentityAsync(
                    creditNote.TabletSource,
                    creditNote.DeviceId,
                    creditNote.UserName ?? creditNote.CreatedBy);

                string docNumber = ResolveGeneratedDocNumber(creditNote, reference);

                var crnHeaderValues = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
                {
                    { "SALFCY", salesSite }, // Use mapped financial sales site for Position 2 (SALFCY)
                    { "SIVTYP", crnType },
                    { "STOFCY", shippingSite }, // Use mapped physical shipping site for Position 4 (STOFCY)
                    { "FCY", salesSite },
                    { "INVTYP", category.ToString() },
                    { "NUM", docNumber },
                    { "NUM_0", docNumber },
                    { "INVNUM", docNumber },
                    { "VCRNUM", docNumber },
                    { "SIHNUM", docNumber },
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
                string fallbackCrnHeader = $"V;{salesSite};{crnType};{shippingSite};{category};{docNumber};{creditNote.CustomerCode};{creditNoteDate};{reference};{stockTransaction};3;{primaryCrnRep};MUR;{dueDate};;0;{reason};{sihoriFlag};{sihoriNum};{tabletSource};|";
                fileBuilder.Append(ConstructDynamicVHeader(crnTemplateFields, crnHeaderValues, fallbackCrnHeader));

                // Pre-resolve item metadata (official SalesUnit and TaxLevel from ITMMASTER) & valid TABWRH warehouses
                var candidateSkus = new HashSet<string>(creditNote.Lines.Where(l => !string.IsNullOrEmpty(l.Sku)).Select(l => l.Sku!));
                var itemMetadata = await GetItemMetadataAsync(candidateSkus);
                var validCrnWarehouses = await GetValidWarehousesAsync(crnSchema);
                var crnSiteWarehousesMap = await GetSiteWarehousesMapAsync(crnSchema);
                bool isCrnWarehouseManaged = crnSiteWarehousesMap.TryGetValue(shippingSite, out var validCrnSiteWrhs) && validCrnSiteWrhs.Any();

                int lineMultiplier = 1000;
                foreach (var line in creditNote.Lines)
                {
                    string sku = (line.Sku ?? "").Trim();
                    string name = (line.Name ?? "").Replace(";", " ").Replace("|", " ").Replace("\r", " ").Replace("\n", " ").Trim();
                    string unit = line.SalesUnit ?? "";
                    double price = line.BasePrice;
                    string taxRule = line.TaxRule ?? "";
                    string cce0 = string.IsNullOrWhiteSpace(line.Cce0) ? "COMMERCIAL" : line.Cce0;
                    string inputWarehouse = IsPlaceholderStockToken(line.Warehouse) ? "" : (line.Warehouse ?? "").Trim();
                    string warehouse = "";

                    if (isCrnWarehouseManaged && validCrnSiteWrhs != null && validCrnSiteWrhs.Any())
                    {
                        if (!string.IsNullOrEmpty(inputWarehouse) && validCrnSiteWrhs.Contains(inputWarehouse, StringComparer.OrdinalIgnoreCase))
                        {
                            warehouse = inputWarehouse;
                        }
                        else if (stockTransaction == 2 && !string.IsNullOrWhiteSpace(crnAssignedWarehouse) && validCrnSiteWrhs.Contains(crnAssignedWarehouse.Trim(), StringComparer.OrdinalIgnoreCase))
                        {
                            warehouse = crnAssignedWarehouse.Trim();
                        }
                        else
                        {
                            warehouse = validCrnSiteWrhs.First();
                        }
                    }
                    else if (!isCrnWarehouseManaged)
                    {
                        warehouse = "";
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

                    string qty = FormatClean2Dp(line.Quantity);
                    string basePriceStr = FormatClean2Dp(price);
                    string disc1 = FormatClean2Dp(line.DiscountAmount);
                    var d2Val = line.Discount2 > 0 ? line.Discount2 : line.DiscountAmountFlat;
                    string disc2 = FormatClean2Dp(d2Val);
                    string disc3 = FormatClean2Dp(line.Discount3);

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

                // Verify created document directly in SINVOICE if X3 returned REQ-* or a duplicate-key retry after a crash
                if (!string.IsNullOrWhiteSpace(docNumber) &&
                    ((parsedResult.Success && (string.IsNullOrWhiteSpace(parsedResult.DocumentId) || parsedResult.DocumentId.StartsWith("REQ-", StringComparison.OrdinalIgnoreCase)))
                     || (!parsedResult.Success && IsDuplicateKeySoapResult(parsedResult))))
                {
                    var verifiedNum = await TryVerifySinvoiceExistsInX3Async(crnSchema, docNumber, creditNote.CustomerCode);
                    if (!string.IsNullOrWhiteSpace(verifiedNum))
                    {
                        parsedResult.DocumentId = verifiedNum;
                        parsedResult.Success = true;
                    }
                }

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
                SettlementType = creditNote.SettlementType,
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
                    Cce0 = l.StandaloneCce0,
                    StockStatus = l.StockStatus,
                    ReturnCondition = l.ReturnCondition,
                    ExpiryDate = l.ExpiryDate,
                    Location = l.Location
                });
            }

            return await ImportCreditNoteAsync(invoiceHeader);
        }

        public static string ResolveMiscReceiptStockStatus(
            string? stockStatus,
            string? returnCondition,
            string? headerReason = null)
        {
            string normalizedStatus = (stockStatus ?? string.Empty).Trim().ToUpperInvariant();
            if (normalizedStatus.StartsWith("R")) return "R";
            if (normalizedStatus.StartsWith("Q")) return "Q";

            string reason = (!string.IsNullOrWhiteSpace(returnCondition)
                    ? returnCondition
                    : headerReason ?? string.Empty)
                .Trim()
                .ToUpperInvariant();
            if (reason is "DEF" or "DAMAGED" or "REJECTED" || reason.Contains("DAMAG")) return "R";
            if (reason is "EXP" or "EXPIRED" or "QUARANTINE" || reason.Contains("EXPIR")) return "Q";

            if (normalizedStatus.StartsWith("A")) return "A";
            return "A";
        }

        public static string ResolveMiscReceiptDescription(string sta, string? returnCondition)
        {
            if (!string.IsNullOrWhiteSpace(returnCondition))
            {
                return returnCondition.Trim();
            }

            return sta switch
            {
                "R" => "Damaged Return",
                "Q" => "Expired / Quarantine Return",
                _ => "Restockable Return",
            };
        }

        public async Task<X3ImportResult> ImportMiscReceiptAsync(StagingSalesInvoiceHeader header, List<StagingSalesInvoiceLine> lines)
        {
            var result = new X3ImportResult { Identifier = header.InvoiceId };
            if (lines == null || lines.Count == 0)
            {
                result.Success = true;
                return result;
            }

            string soapEnvelope = string.Empty;
            string responseXml = string.Empty;

            try
            {
                var fileBuilder = new StringBuilder();

                string receiptDate = header.CreatedAt ?? DateTime.UtcNow.ToString("yyyyMMdd");
                receiptDate = receiptDate.Replace("-", "").Replace(" ", "").Replace(":", "");
                if (receiptDate.Length > 8) receiptDate = receiptDate.Substring(0, 8);
                if (string.IsNullOrWhiteSpace(receiptDate)) receiptDate = DateTime.UtcNow.ToString("yyyyMMdd");

                string schema = ResolveX3Schema();

                // Authoritative site resolution: prefer user login SiteCode claim (e.g. SCG/POD) first
                // because header.SalesSite may have been normalized to FinancialSiteCode (e.g. CGD).
                var userSiteCode = _httpContextAccessor.HttpContext?.User?.FindFirst("SiteCode")?.Value;
                string requestedSite = (!string.IsNullOrWhiteSpace(userSiteCode) && userSiteCode != "ALL")
                    ? userSiteCode.Trim()
                    : (!string.IsNullOrWhiteSpace(header.SalesSite) && header.SalesSite != "ALL" ? header.SalesSite.Trim() : "POD");

                var (salesSite, shippingSite) = await ResolveSiteMappingAsync(requestedSite, schema);

                var (tabletSource, assignedWarehouse, assignedLocation) = await ResolveDeviceIdentityAsync(
                    header.TabletSource,
                    header.DeviceId,
                    header.UserName ?? header.CreatedBy,
                    requestedSite);

                // Extract lorry code embedded in HIPO document ID (e.g. HRCGD08112600005 -> 08) as fallback
                string? embeddedLorry = null;
                if (!string.IsNullOrWhiteSpace(header.InvoiceId) && header.InvoiceId.Length >= 12 && header.InvoiceId.StartsWith("H", StringComparison.OrdinalIgnoreCase))
                {
                    string pfx = header.InvoiceId.Substring(0, header.InvoiceId.Length - 5);
                    if (pfx.Length > 6)
                    {
                        string middle = pfx.Substring(2, pfx.Length - 6);
                        var lorryMatch = System.Text.RegularExpressions.Regex.Match(middle, @"^([A-Za-z]+)(\d+)$");
                        if (lorryMatch.Success && lorryMatch.Groups[2].Value != "00")
                        {
                            embeddedLorry = lorryMatch.Groups[2].Value;
                        }
                    }
                }

                string firstLineLoc = lines
                    .Select(l => (l.Location ?? "").Trim())
                    .FirstOrDefault(locVal =>
                        !string.IsNullOrWhiteSpace(locVal)
                        && !string.Equals(locVal, "LOC1", StringComparison.OrdinalIgnoreCase)
                        && !string.Equals(locVal, salesSite, StringComparison.OrdinalIgnoreCase)
                        && !string.Equals(locVal, shippingSite, StringComparison.OrdinalIgnoreCase)) ?? "";

                string candidateLorry = !string.IsNullOrWhiteSpace(assignedLocation)
                    ? assignedLocation.Trim()
                    : (!string.IsNullOrWhiteSpace(firstLineLoc)
                        ? firstLineLoc
                        : (!string.IsNullOrWhiteSpace(embeddedLorry)
                            ? embeddedLorry
                            : (shippingSite == "IPL" ? "IPLCH" : shippingSite)));

                string resolvedLoc = candidateLorry;
                string entCod = "";
                string trsCod = "";

                // Verify (STOFCY, LOC) against STOLOC and (ENTCOD, TRSCOD) against SMVTH / GAUTO in Sage X3
                try
                {
                    using var x3Conn = new SqlConnection(_innodisConnectionString);
                    await x3Conn.OpenAsync();
                    var candidateSchemas = new[] { schema, "INLDRYRUN", "INL", "X3" }
                        .Where(s => !string.IsNullOrWhiteSpace(s))
                        .Distinct(StringComparer.OrdinalIgnoreCase)
                        .ToList();

                    foreach (var candSchema in candidateSchemas)
                    {
                        bool foundStoloc = false;
                        // 1. Verify exact STOFCY_0 where candidateLorry (e.g. N8) is created in STOLOC
                        try
                        {
                            var stolocMatch = await x3Conn.QueryFirstOrDefaultAsync(
                                $@"SELECT TOP 1
                                       LTRIM(RTRIM(STOFCY_0)) AS SiteCode,
                                       LTRIM(RTRIM(LOC_0)) AS LocCode
                                   FROM x3.{candSchema}.STOLOC WITH (NOLOCK)
                                   WHERE LTRIM(RTRIM(LOC_0)) = @Loc
                                   ORDER BY
                                       CASE
                                           WHEN LTRIM(RTRIM(STOFCY_0)) = @ShippingSite THEN 0
                                           WHEN LTRIM(RTRIM(STOFCY_0)) = @RequestedSite THEN 1
                                           WHEN LTRIM(RTRIM(STOFCY_0)) = @SalesSite THEN 2
                                           ELSE 3
                                       END",
                                new
                                {
                                    Loc = candidateLorry,
                                    ShippingSite = shippingSite,
                                    RequestedSite = requestedSite,
                                    SalesSite = salesSite
                                });

                            if (stolocMatch != null)
                            {
                                string matchedSite = ((string?)stolocMatch.SiteCode ?? "").Trim();
                                string matchedLoc = ((string?)stolocMatch.LocCode ?? "").Trim();
                                if (!string.IsNullOrWhiteSpace(matchedSite)) shippingSite = matchedSite;
                                if (!string.IsNullOrWhiteSpace(matchedLoc)) resolvedLoc = matchedLoc;
                                foundStoloc = true;
                            }
                            else
                            {
                                var fallbackLoc = await x3Conn.QueryFirstOrDefaultAsync<string>(
                                    $@"SELECT TOP 1 LTRIM(RTRIM(LOC_0))
                                       FROM x3.{candSchema}.STOLOC WITH (NOLOCK)
                                       WHERE LTRIM(RTRIM(STOFCY_0)) = @ShippingSite
                                         AND LTRIM(RTRIM(ISNULL(LOC_0, ''))) <> ''
                                       ORDER BY CASE WHEN LTRIM(RTRIM(LOC_0)) LIKE @LocPattern THEN 0 ELSE 1 END, LOC_0",
                                    new { ShippingSite = shippingSite, LocPattern = $"%{candidateLorry}%" });
                                if (!string.IsNullOrWhiteSpace(fallbackLoc))
                                {
                                    resolvedLoc = fallbackLoc.Trim();
                                    foundStoloc = true;
                                }
                            }
                        }
                        catch { }

                        // 2. Discover historical SMVTH (VCRTYP_0 = 19) ENTCOD_0 and TRSCOD_0 in its own isolated try/catch
                        try
                        {
                            var smvthSample = await x3Conn.QueryFirstOrDefaultAsync(
                                $@"SELECT TOP 1
                                       LTRIM(RTRIM(ISNULL(ENTCOD_0, ''))) AS EntCod,
                                       LTRIM(RTRIM(ISNULL(TRSCOD_0, ''))) AS TrsCod
                                   FROM x3.{candSchema}.SMVTH WITH (NOLOCK)
                                   WHERE VCRTYP_0 = 19
                                     AND (LTRIM(RTRIM(ISNULL(ENTCOD_0, ''))) <> '' OR LTRIM(RTRIM(ISNULL(TRSCOD_0, ''))) <> '')
                                   ORDER BY
                                       CASE WHEN LTRIM(RTRIM(STOFCY_0)) = @ShippingSite THEN 0 ELSE 1 END,
                                       CREDAT_0 DESC",
                                new { ShippingSite = shippingSite });

                            if (smvthSample != null)
                            {
                                string sampleEnt = ((string?)smvthSample.EntCod ?? "").Trim();
                                string sampleTrs = ((string?)smvthSample.TrsCod ?? "").Trim();
                                if (!string.IsNullOrWhiteSpace(sampleEnt)) entCod = sampleEnt;
                                if (!string.IsNullOrWhiteSpace(sampleTrs)) trsCod = sampleTrs;
                            }
                        }
                        catch { }

                        // 3. Validate/fallback Automatic Journal against GAUTACE in its own isolated try/catch
                        try
                        {
                            var gautaceCodes = (await x3Conn.QueryAsync<string>(
                                $@"SELECT DISTINCT LTRIM(RTRIM(COD_0))
                                   FROM x3.{candSchema}.GAUTACE WITH (NOLOCK)
                                   WHERE LTRIM(RTRIM(ISNULL(COD_0, ''))) <> ''"))
                                .Where(c => !string.IsNullOrWhiteSpace(c))
                                .Select(c => c.Trim())
                                .ToHashSet(StringComparer.OrdinalIgnoreCase);

                            if (gautaceCodes.Count > 0)
                            {
                                if (!string.IsNullOrWhiteSpace(entCod) && !gautaceCodes.Contains(entCod))
                                {
                                    entCod = gautaceCodes.Contains("STK") ? "STK" : "";
                                }
                                else if (string.IsNullOrWhiteSpace(entCod) && gautaceCodes.Contains("STK"))
                                {
                                    entCod = "STK";
                                }
                            }
                        }
                        catch { }

                        if (foundStoloc || !string.IsNullOrWhiteSpace(entCod) || !string.IsNullOrWhiteSpace(trsCod))
                        {
                            break;
                        }
                    }
                }
                catch (Exception metaEx)
                {
                    Console.WriteLine($"[SageX3SoapService] ZSMRWEBA metadata lookup notice: {metaEx.Message}");
                }

                Console.WriteLine($"[SageX3SoapService] ZSMRWEBA resolved STOFCY='{shippingSite}', LOC='{resolvedLoc}', ENTCOD='{entCod}', TRSCOD='{trsCod}'");

                string docNumber = ResolveGeneratedDocNumber(header, header.InvoiceId ?? "");
                string vcrDes = $"Return {header.InvoiceId}".Trim();
                if (vcrDes.Length > 30) vcrDes = vcrDes.Substring(0, 30);

                // --- Record E (Table SMVTH, Lines 1-9) ---
                // 1: E, 2: ENTCOD, 3: VCRTYP, 4: VCRNUM, 5: STOFCY, 6: IPTDAT, 7: VCRDES, 8: PJT, 9: TRSCOD
                fileBuilder.Append($"E;{entCod};19;{docNumber};{shippingSite};{receiptDate};{vcrDes};;{trsCod};|");

                var itemMetadata = await GetItemMetadataAsync(lines.Select(l => l.Sku));

                int vcrLin = 1;
                foreach (var line in lines)
                {
                    if (line.Quantity <= 0) continue;

                    string sku = (line.Sku ?? "").Trim();
                    string unit = !string.IsNullOrWhiteSpace(line.SalesUnit) ? line.SalesUnit.Trim().ToUpperInvariant() : "EA";
                    if (itemMetadata.TryGetValue(sku, out var meta) && !string.IsNullOrWhiteSpace(meta.SalesUnit))
                    {
                        if (string.IsNullOrWhiteSpace(unit) || string.Equals(unit, "EA", StringComparison.OrdinalIgnoreCase))
                        {
                            unit = meta.SalesUnit.Trim().ToUpperInvariant();
                        }
                    }
                    string qtyStr = line.Quantity.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture);
                    string priceStr = line.BasePrice > 0 ? line.BasePrice.ToString("F2", System.Globalization.CultureInfo.InvariantCulture) : "";

                    // --- Record L (Table SMVTD, Lines 10-19) ---
                    // 1: L, 2: VCRLIN, 3: ITMREF, 4: ITMDES1, 5: PCU, 6: QTYPCU, 7: PCUSTUCOE, 8: STU, 9: QTYSTU, 10: PRIORD
                    fileBuilder.Append($"L;{vcrLin};{sku};;{unit};{qtyStr};1;{unit};{qtyStr};{priceStr};|");

                    string lot = (line.LotNumber ?? "").Trim();
                    string expDate = (line.ExpiryDate ?? "").Replace("-", "").Replace(" ", "").Replace(":", "").Trim();
                    if (expDate.Length > 8) expDate = expDate.Substring(0, 8);

                    string loc = resolvedLoc;

                    // Stock Status: "A" (Normal/Sellable), "R" (Damaged/Rejected), "Q" (Expired/Quarantine)
                    string sta = ResolveMiscReceiptStockStatus(
                        line.StockStatus,
                        line.ReturnCondition,
                        header.Reason);

                    string mvtDes = ResolveMiscReceiptDescription(sta, line.ReturnCondition);
                    if (mvtDes.Length > 30) mvtDes = mvtDes.Substring(0, 30);

                    // --- Record S (Table STOJOU, Lines 20-31) ---
                    // 1: S, 2: PCU, 3: QTYPCU, 4: BPSLOT, 5: LOT, 6: SLO, 7: LPNNUM, 8: SHLDAT, 9: LOC, 10: STA, 11: SERNUM, 12: MVTDES
                    fileBuilder.Append($"S;{unit};{qtyStr};;{lot};;;{expDate};{loc};{sta};;{mvtDes}|");

                    vcrLin++;
                }

                fileBuilder.Append("END");
                string iFile = fileBuilder.ToString();

                string inputXmlJson = "{\"GRP1\":{" +
                                      "\"I_MODIMP\":\"ZSMRWEBA\"," +
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

                Console.WriteLine("====== SAGE X3 MISC STOCK RECEIPT SOAP REQUEST (ZSMRWEBA) ======");
                Console.WriteLine(soapEnvelope);
                Console.WriteLine("===============================================================");

                var request = new HttpRequestMessage(HttpMethod.Post, _soapUrl);
                request.Content = new StringContent(soapEnvelope, Encoding.UTF8, "text/xml");

                var authToken = Convert.ToBase64String(Encoding.ASCII.GetBytes($"{_username}:{_password}"));
                request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Basic", authToken);

                request.Headers.TryAddWithoutValidation("SOAPAction", "");
                request.Headers.TryAddWithoutValidation("soapAction", "");

                var response = await _httpClient.SendAsync(request);
                responseXml = await response.Content.ReadAsStringAsync();

                Console.WriteLine("====== SAGE X3 MISC STOCK RECEIPT SOAP RESPONSE (ZSMRWEBA) ======");
                Console.WriteLine(responseXml);
                Console.WriteLine("=================================================================");

                if (!response.IsSuccessStatusCode)
                {
                    result.Success = false;
                    result.TechnicalError = $"HTTP {response.StatusCode}: {responseXml}";
                    await InsertSoapAuditAsync("ImportMiscReceipt", header.InvoiceId, soapEnvelope, responseXml, false, result.TechnicalError);
                    return result;
                }

                var parsedResult = ParseSoapResponse(responseXml, result);

                // If ZSMRWEBA succeeded without emitting a "Creation of ..." trace message (or returned REQ-*),
                // or failed with a duplicate-key retry after a crash, verify directly against x3.<schema>.SMVTH by VCRNUM_0 / VCRDES_0.
                if (string.IsNullOrWhiteSpace(parsedResult.DocumentId)
                    || parsedResult.DocumentId.StartsWith("REQ-", StringComparison.OrdinalIgnoreCase)
                    || (!parsedResult.Success && IsDuplicateKeySoapResult(parsedResult)))
                {
                    var verifiedVcrNum = await TryVerifySmvthExistsInX3Async(schema, docNumber, vcrDes);
                    if (!string.IsNullOrWhiteSpace(verifiedVcrNum))
                    {
                        parsedResult.DocumentId = verifiedVcrNum;
                        parsedResult.Success = true;
                        Console.WriteLine($"[SageX3SoapService] Verified created ZSMRWEBA document in SMVTH: {parsedResult.DocumentId}");
                    }
                }

                await InsertSoapAuditAsync("ImportMiscReceipt", header.InvoiceId, soapEnvelope, responseXml, parsedResult.Success, parsedResult.Success ? null : string.Join(" | ", parsedResult.Messages));
                return parsedResult;
            }
            catch (Exception ex)
            {
                result.Success = false;
                result.TechnicalError = ex.Message;
                await InsertSoapAuditAsync("ImportMiscReceipt", header.InvoiceId, soapEnvelope, responseXml, false, ex.Message);
                return result;
            }
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

        private async Task<bool> IsOpenItemAvailableAsync(string docNum, string schema)
        {
            if (string.IsNullOrWhiteSpace(docNum)) return false;
            try
            {
                using var conn = new SqlConnection(_innodisConnectionString);
                await conn.OpenAsync();
                var count = await conn.ExecuteScalarAsync<int>(
                    $"SELECT COUNT(1) FROM x3.{schema}.GACCDUD WHERE NUM_0 = @docNum AND LIG_0 = 1",
                    new { docNum });
                return count > 0;
            }
            catch
            {
                return false;
            }
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

        private async Task<string> BuildPaymentIFileAsync(List<StagingSalesInvoicePayment> payments, bool forceOnAccount = false)
        {
            var fileBuilder = new StringBuilder();
            string paySchema = ResolveX3Schema();

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

                string targetDocNum = !string.IsNullOrWhiteSpace(payment.X3InvoiceDocumentId) ? payment.X3InvoiceDocumentId.Trim() : "";

                // Check whether an open item exists in GACCDUD
                bool hasOpenItem = false;
                if (!forceOnAccount && !string.IsNullOrWhiteSpace(targetDocNum))
                {
                    hasOpenItem = await IsOpenItemAvailableAsync(targetDocNum, paySchema);
                }

                if (description.Length > 30) description = description.Substring(0, 30);

                // P Header Line:
                // P;[NUM];[TYP];;[BPR];[CPY];[ACC];;[PAM];[FCY];[BAN];[SNS];[CUR];[AMTCUR];[AMT];0;[DATE];[DES]
                fileBuilder.Append($"P;;{entryType};;{customerCode};{company};{controlAccount};;{pam};{fcy};{bank};{sign};{currency};{amtStr};{amtStr};0;{payDate};{description}|");

                // D Detail Line:
                // Pos 19: D | Pos 20: DENCOD | Pos 21: COA | Pos 22: ACC | Pos 23: BPRLIN | Pos 24: VCRTYP | Pos 25: VCRNUM
                // Pos 26: *1 (DUDDAT) | Pos 27: *2 (DUDLIG = 1) | Pos 28: *3 | Pos 29: *4 | Pos 30: CURLIN
                // Pos 31: AMTLIN | Pos 32: VATLIN | Pos 33: QTYLIN (0) | Pos 34: DSP | Pos 35: DESLIN
                if (hasOpenItem)
                {
                    // Allocated directly to verified open item line 1 in GACCDUD
                    fileBuilder.Append($"D;;;{controlAccount};{customerCode};{docCategory};{targetDocNum};{payDate};1;;;{currency};{amtStr};;0;;{description}|");
                }
                else
                {
                    // Unallocated on-account payment: VCRTYP, VCRNUM and DUDLIG left empty; invoice number tracked in description
                    string lineDesc = !string.IsNullOrWhiteSpace(targetDocNum) ? $"{description} {targetDocNum}" : description;
                    if (lineDesc.Length > 30) lineDesc = lineDesc.Substring(0, 30);
                    fileBuilder.Append($"D;;;{controlAccount};{customerCode};;;{payDate};;;;{currency};{amtStr};;0;;{lineDesc}|");
                }
            }

            fileBuilder.Append("END");
            return fileBuilder.ToString();
        }

        private async Task<(bool success, X3ImportResult result, string soapReq, string soapResp)> ExecutePaymentSoapAsync(
            List<StagingSalesInvoicePayment> payments,
            bool forceOnAccount)
        {
            var result = new X3ImportResult();
            var firstPayment = payments.First();
            result.Identifier = firstPayment.DocumentId;
            string soapEnvelope = string.Empty;
            string responseXml = string.Empty;

            try
            {
                string iFile = await BuildPaymentIFileAsync(payments, forceOnAccount);
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

                Console.WriteLine($"====== SAGE X3 PAYMENT SOAP REQUEST (ZPAYWEBA - ForceOnAccount: {forceOnAccount}) ======");
                Console.WriteLine(soapEnvelope);
                Console.WriteLine("=================================================================================");

                var request = new HttpRequestMessage(HttpMethod.Post, _soapUrl);
                request.Content = new StringContent(soapEnvelope, Encoding.UTF8, "text/xml");

                var authToken = Convert.ToBase64String(Encoding.ASCII.GetBytes($"{_username}:{_password}"));
                request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Basic", authToken);
                request.Headers.TryAddWithoutValidation("SOAPAction", "");
                request.Headers.TryAddWithoutValidation("soapAction", "");

                var response = await _httpClient.SendAsync(request);
                responseXml = await response.Content.ReadAsStringAsync();

                Console.WriteLine($"====== SAGE X3 PAYMENT SOAP RESPONSE (ZPAYWEBA - ForceOnAccount: {forceOnAccount}) ======");
                Console.WriteLine(responseXml);
                Console.WriteLine("==================================================================================");

                if (!response.IsSuccessStatusCode)
                {
                    result.Success = false;
                    result.TechnicalError = $"HTTP {response.StatusCode}: {responseXml}";
                    return (false, result, soapEnvelope, responseXml);
                }

                var parsedResult = ParseSoapResponse(responseXml, result);
                return (parsedResult.Success, parsedResult, soapEnvelope, responseXml);
            }
            catch (Exception ex)
            {
                result.Success = false;
                result.TechnicalError = ex.Message;
                return (false, result, soapEnvelope, responseXml);
            }
        }

        private static bool ShouldRetryOnAccount(X3ImportResult res)
        {
            var combined = $"{res.TechnicalError} {string.Join(" ", res.Messages ?? new List<string>())} {res.RawPayload}";
            return combined.Contains("Nonexistent open item", StringComparison.OrdinalIgnoreCase) ||
                   combined.Contains("Accounting journal Non-existent", StringComparison.OrdinalIgnoreCase) ||
                   combined.Contains("Non-existent", StringComparison.OrdinalIgnoreCase) ||
                   combined.Contains("DUDNUM", StringComparison.OrdinalIgnoreCase) ||
                   combined.Contains("VCRTYP", StringComparison.OrdinalIgnoreCase);
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

            // Attempt 1: Standard import (allocated if open item exists in GACCDUD, otherwise on-account)
            var (success, parsedResult, soapReq, soapResp) = await ExecutePaymentSoapAsync(payments, false);

            // Check if failure is due to unposted invoice / nonexistent open item in Sage X3
            if (!parsedResult.Success && ShouldRetryOnAccount(parsedResult))
            {
                Console.WriteLine($"[SageX3SoapService] Payment allocation failed due to nonexistent open item. Retrying as unallocated on-account payment for {result.Identifier}...");
                var (retrySuccess, retryParsedResult, retrySoapReq, retrySoapResp) = await ExecutePaymentSoapAsync(payments, true);
                await InsertSoapAuditAsync("ImportPayment", result.Identifier, retrySoapReq, retrySoapResp, retryParsedResult.Success, retryParsedResult.Success ? null : string.Join(" | ", retryParsedResult.Messages));
                return retryParsedResult;
            }

            await InsertSoapAuditAsync("ImportPayment", result.Identifier, soapReq, soapResp, parsedResult.Success, parsedResult.Success ? null : string.Join(" | ", parsedResult.Messages));
            return parsedResult;
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
                    if (result.Success && !string.IsNullOrWhiteSpace(result.RequestNumber))
                    {
                        result.DocumentId = $"REQ-{result.RequestNumber}";
                    }
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
