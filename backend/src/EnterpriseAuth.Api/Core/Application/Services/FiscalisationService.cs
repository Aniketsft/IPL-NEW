using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Dapper;
using EnterpriseAuth.Api.Core.Application.Common;
using EnterpriseAuth.Api.Core.Application.DTOs;
using EnterpriseAuth.Api.Core.Application.Interfaces;
using EnterpriseAuth.Api.Core.Domain.Entities;
using EnterpriseAuth.Api.Infrastructure.Persistence;
using EnterpriseAuth.Api.Infrastructure.Security;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace EnterpriseAuth.Api.Core.Application.Services
{
    public class FiscalisationService : IFiscalisationService
    {
        private static readonly JsonSerializerOptions WireJsonOptions = new()
        {
            PropertyNamingPolicy = null,
            Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping
        };

        private static readonly JsonSerializerOptions DebugPrettyJsonOptions = new()
        {
            PropertyNamingPolicy = null,
            WriteIndented = true,
            Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping
        };

        private readonly ScanProductionDbContext _dbContext;
        private readonly ISalesInvoiceRepository _salesInvoiceRepository;
        private readonly IHepSecretProtector _secretProtector;
        private readonly IHttpClientFactory _httpClientFactory;
        private readonly FiscalSettings _fiscalSettings;
        private readonly SyncSettings _syncSettings;
        private readonly IX3SchemaProvider? _schemaProvider;
        private readonly string? _innodisConnectionString;
        private readonly ILogger<FiscalisationService> _logger;

        public FiscalisationService(
            ScanProductionDbContext dbContext,
            ISalesInvoiceRepository salesInvoiceRepository,
            IHepSecretProtector secretProtector,
            IHttpClientFactory httpClientFactory,
            IOptions<FiscalSettings> fiscalSettings,
            IOptions<SyncSettings> syncSettings,
            IConfiguration configuration,
            ILogger<FiscalisationService> logger,
            IX3SchemaProvider? schemaProvider = null)
        {
            _dbContext = dbContext;
            _salesInvoiceRepository = salesInvoiceRepository;
            _secretProtector = secretProtector;
            _httpClientFactory = httpClientFactory;
            _fiscalSettings = fiscalSettings.Value;
            _syncSettings = syncSettings.Value;
            _schemaProvider = schemaProvider;
            _innodisConnectionString = configuration.GetConnectionString("Innodis");
            _logger = logger;
        }

        public async Task<(int HttpStatusCode, FiscaliseResultDto Result)> FiscaliseAsync(
            FiscaliseDocumentRequestDto request,
            string? headerDeviceId,
            string? userName,
            string? userSiteCode,
            CancellationToken cancellationToken = default)
        {
            var sw = Stopwatch.StartNew();
            var docNo = (request.DocumentNo ?? string.Empty).Trim();
            var docCategory = string.IsNullOrWhiteSpace(request.DocumentCategory)
                ? "INVOICE"
                : request.DocumentCategory.Trim().ToUpperInvariant();
            var docType = FiscalInvoiceMapper.ResolveInvoiceTypeDesc(request.InvoiceType, docCategory);

            if (string.IsNullOrWhiteSpace(docNo))
            {
                return (400, new FiscaliseResultDto
                {
                    Success = false,
                    DocumentNo = docNo,
                    StatusMessage = "DocumentNo is required.",
                    Errors = { new FiscalErrorItemDto { Code = "PRE_DOC_ID", Description = "DocumentNo is required." } }
                });
            }

            // 1. Idempotency: return stored fiscal credentials if already fiscalised
            var existing = await _dbContext.HepFiscalInvoices
                .AsNoTracking()
                .FirstOrDefaultAsync(f => f.DocumentNo == docNo && f.IsFiscalised, cancellationToken);

            if (existing != null)
            {
                return (200, ToResultDto(existing, hepStatusOverride: "duplicate"));
            }

            // 2. Resolve calling device & decrypt per-device HEP credentials
            var device = await ResolveDeviceAsync(request.DeviceId, headerDeviceId, userName, cancellationToken);
            if (device == null)
            {
                const string msg = "Device could not be resolved. Register/sync device before fiscalising.";
                await RecordFailureAsync(
                    docNo, docType, docCategory, request.DeviceId ?? headerDeviceId, null,
                    userSiteCode ?? request.SalesSite, userName, request.CustomerCode,
                    null, null, null, null, null, "hepError", msg, null, null, null,
                    "PRE_DEVICE", msg, null, (int)sw.ElapsedMilliseconds, cancellationToken);

                return (400, new FiscaliseResultDto
                {
                    Success = false,
                    DocumentNo = docNo,
                    HepStatus = "hepError",
                    StatusMessage = msg,
                    Errors = { new FiscalErrorItemDto { Code = "PRE_DEVICE", Description = msg } }
                });
            }

            var profileId = new string((device.HepProfileId ?? string.Empty).Where(c => !char.IsWhiteSpace(c)).ToArray());
            var apiKey = _secretProtector.UnprotectOrPlaintext(device.HepApiKey);
            var isEncryptedAtRest = !string.IsNullOrWhiteSpace(device.HepApiKey)
                && device.HepApiKey.Trim().StartsWith("dp:", StringComparison.Ordinal);
            if (string.IsNullOrWhiteSpace(profileId) || string.IsNullOrWhiteSpace(apiKey))
            {
                const string msg = "Device is not configured for fiscalisation (missing HEP Profile ID or API Key in Devices module).";
                await RecordFailureAsync(
                    docNo, docType, docCategory, device.DeviceId, profileId,
                    device.SiteCode, userName, request.CustomerCode,
                    null, null, null, null, null, "hepError", msg, null, null, null,
                    "PRE_DEVICE_CONFIG", msg, null, (int)sw.ElapsedMilliseconds, cancellationToken);

                return (400, new FiscaliseResultDto
                {
                    Success = false,
                    DocumentNo = docNo,
                    HepStatus = "hepError",
                    StatusMessage = msg,
                    Errors = { new FiscalErrorItemDto { Code = "PRE_DEVICE_CONFIG", Description = msg } }
                });
            }

            var ebsCounterNo = string.IsNullOrWhiteSpace(device.EbsCounterNo) ? "1" : device.EbsCounterNo.Trim();
            var baseUrl = (_fiscalSettings.BaseUrl ?? string.Empty).TrimEnd('/');
            var requestUrl = $"{baseUrl}/api/v1/connectors/{Uri.EscapeDataString(profileId)}/ingest";

            // 3. Resolve Seller, Buyer, Item Natures, Tax Codes, Reason, and Origin Reference
            var effectiveSite = !string.IsNullOrWhiteSpace(request.SalesSite) && !string.Equals(request.SalesSite, "ALL", StringComparison.OrdinalIgnoreCase)
                ? request.SalesSite.Trim().ToUpperInvariant()
                : (!string.IsNullOrWhiteSpace(device.SiteCode) ? device.SiteCode.Trim().ToUpperInvariant() : "POD");

            var seller = await ResolveSellerAsync(effectiveSite);
            var buyer = await ResolveBuyerAsync(request.CustomerCode, request.CustomerName);
            var (itemNatures, itemTaxLevels) = await ResolveItemMetadataAsync(request.Lines.Select(l => l.Sku));
            var resolvedTaxCodes = await ResolveMissingTaxCodesAsync(request.Lines, buyer.PersonType, itemTaxLevels);
            var resolvedReason = docType == "CRN" ? await ResolveReasonTextAsync(request.Reason) : string.Empty;

            if (docType == "CRN" && !string.IsNullOrWhiteSpace(request.OriginalInvoiceId))
            {
                var origHeader = await _dbContext.StagingSalesInvoiceHeaders
                    .AsNoTracking()
                    .FirstOrDefaultAsync(h => h.InvoiceId == request.OriginalInvoiceId.Trim(), cancellationToken);
                if (origHeader != null && !string.IsNullOrWhiteSpace(origHeader.X3DocumentId))
                {
                    request.OriginalInvoiceId = origHeader.X3DocumentId;
                }
            }

            // 4. Build MRA/HEP payload & pre-validate
            var mapped = FiscalInvoiceMapper.Map(
                request,
                seller,
                buyer,
                ebsCounterNo,
                itemNatures,
                resolvedTaxCodes,
                resolvedReason);

            var payloadArray = new[] { mapped.Document };
            var payloadJson = JsonSerializer.Serialize(payloadArray, WireJsonOptions);
            var debugPrettyJson = JsonSerializer.Serialize(payloadArray, DebugPrettyJsonOptions);
            var maskedKey = _secretProtector.MaskApiKey(apiKey);
            var keyHasWhitespace = apiKey.Any(char.IsWhiteSpace);

            _logger.LogInformation(
                "[FISCAL-HEP] >>> POST {RequestUrl} | Doc={DocumentNo} Category={Category} Type={DocType} | Device={DeviceId} Profile={ProfileId} ApiKey={MaskedKey} (Len={KeyLen}, Whitespace={HasWhitespace}, Encrypted={IsEncrypted})\n[FISCAL-HEP] >>> PAYLOAD ({ByteCount} bytes):\n{PayloadJson}",
                requestUrl,
                docNo,
                docCategory,
                mapped.Document.InvoiceTypeDesc,
                device.DeviceId,
                profileId,
                maskedKey,
                apiKey.Length,
                keyHasWhitespace,
                isEncryptedAtRest,
                Encoding.UTF8.GetByteCount(payloadJson),
                debugPrettyJson);

            var preErrors = FiscalInvoiceMapper.ValidateBeforeSend(mapped.Document);
            if (preErrors.Count > 0)
            {
                var errCodes = string.Join(", ", preErrors.Select(e => e.Code).Where(c => !string.IsNullOrEmpty(c)));
                var errMsgs = string.Join(" | ", preErrors.Select(e => e.Description));
                _logger.LogWarning(
                    "[FISCAL-HEP] !!! PRE-VALIDATION FAILED for {DocumentNo}: [{ErrCodes}] {ErrMsgs}",
                    docNo, errCodes, errMsgs);
                await RecordFailureAsync(
                    docNo, mapped.Document.InvoiceTypeDesc, docCategory, device.DeviceId, profileId,
                    effectiveSite, userName, buyer.Code,
                    requestUrl, payloadJson, null, null, null, "preValidationError", errMsgs, null, null, null,
                    errCodes, errMsgs, null, (int)sw.ElapsedMilliseconds, cancellationToken);

                return (400, new FiscaliseResultDto
                {
                    Success = false,
                    DocumentNo = docNo,
                    HepStatus = "preValidationError",
                    StatusMessage = errMsgs,
                    Errors = preErrors
                });
            }

            // 5. POST to HEP connector
            int? httpStatus = null;
            string? responseBody = null;
            string? exceptionText = null;

            try
            {
                var client = _httpClientFactory.CreateClient("HepClient");
                client.Timeout = TimeSpan.FromSeconds(Math.Clamp(_fiscalSettings.TimeoutSeconds, 5, 120));

                using var httpReq = new HttpRequestMessage(HttpMethod.Post, requestUrl);
                httpReq.Headers.TryAddWithoutValidation("X-API-Key", apiKey);
                httpReq.Content = new StringContent(payloadJson, Encoding.UTF8, "application/json");

                using var httpResp = await client.SendAsync(httpReq, cancellationToken);
                httpStatus = (int)httpResp.StatusCode;
                responseBody = await httpResp.Content.ReadAsStringAsync(cancellationToken);

                _logger.LogInformation(
                    "[FISCAL-HEP] <<< HTTP {HttpStatus} ({ElapsedMs}ms) for {DocumentNo} | Body:\n{ResponseBody}",
                    httpStatus,
                    sw.ElapsedMilliseconds,
                    docNo,
                    string.IsNullOrWhiteSpace(responseBody) ? "<empty>" : responseBody);
            }
            catch (TaskCanceledException tex) when (!cancellationToken.IsCancellationRequested)
            {
                exceptionText = $"HEP request timed out: {tex.Message}";
                _logger.LogError(tex, "HEP fiscalisation timeout for {DocumentNo} on device {DeviceId}", docNo, device.DeviceId);
            }
            catch (Exception ex)
            {
                exceptionText = $"HEP communication error: {ex.Message}";
                _logger.LogError(ex, "HEP fiscalisation HTTP failure for {DocumentNo} on device {DeviceId}", docNo, device.DeviceId);
            }

            if (!string.IsNullOrEmpty(exceptionText))
            {
                await RecordFailureAsync(
                    docNo, mapped.Document.InvoiceTypeDesc, docCategory, device.DeviceId, profileId,
                    effectiveSite, userName, buyer.Code,
                    requestUrl, payloadJson, httpStatus, responseBody, null, "networkError", exceptionText, null, null, null,
                    "HEP_NETWORK", exceptionText, exceptionText, (int)sw.ElapsedMilliseconds, cancellationToken);

                return (504, new FiscaliseResultDto
                {
                    Success = false,
                    DocumentNo = docNo,
                    HepStatus = "networkError",
                    StatusMessage = exceptionText,
                    Errors = { new FiscalErrorItemDto { Code = "HEP_NETWORK", Description = exceptionText } }
                });
            }

            // 6. Parse HEP response
            var parsed = FiscalInvoiceMapper.ParseHepResponse(responseBody, httpStatus);
            if (!parsed.IsSuccess)
            {
                var errCodes = string.Join(", ", parsed.Errors.Select(e => e.Code).Where(c => !string.IsNullOrEmpty(c)));
                var errMsgs = string.Join(" | ", parsed.Errors.Select(e => string.IsNullOrEmpty(e.Code) ? e.Description : $"{e.Code}: {e.Description}"));
                var statusMsg = !string.IsNullOrWhiteSpace(parsed.HepStatusMessage) ? parsed.HepStatusMessage! : errMsgs;

                await RecordFailureAsync(
                    docNo, mapped.Document.InvoiceTypeDesc, docCategory, device.DeviceId, profileId,
                    effectiveSite, userName, buyer.Code,
                    requestUrl, payloadJson, httpStatus, responseBody, parsed.HepId, parsed.HepStatus, statusMsg,
                    parsed.MraStatus, parsed.MraRequestId, parsed.MraResponseId,
                    errCodes, errMsgs, null, (int)sw.ElapsedMilliseconds, cancellationToken);

                var outHttp = string.Equals(parsed.HepStatus, "hepError", StringComparison.OrdinalIgnoreCase) ? 502 : 422;
                return (outHttp, new FiscaliseResultDto
                {
                    Success = false,
                    DocumentNo = docNo,
                    IsFiscalised = false,
                    HepId = parsed.HepId,
                    HepStatus = parsed.HepStatus,
                    StatusMessage = statusMsg,
                    MraStatus = parsed.MraStatus,
                    MraEnvironment = parsed.MraEnvironment,
                    MraRequestId = parsed.MraRequestId,
                    MraResponseId = parsed.MraResponseId,
                    Errors = parsed.Errors
                });
            }

            // 7. Insert ONLY on success into HepFiscalInvoices
            var nowUtc = DateTime.UtcNow;
            var entity = new HepFiscalInvoice
            {
                Id = Guid.NewGuid(),
                DocumentNo = docNo,
                DocumentType = mapped.Document.InvoiceTypeDesc,
                DocumentCategory = docCategory,
                RefDocumentNo = string.IsNullOrWhiteSpace(mapped.Document.InvoiceRefIdentifier) ? null : mapped.Document.InvoiceRefIdentifier,
                Reason = string.IsNullOrWhiteSpace(mapped.Document.ReasonStated) ? null : mapped.Document.ReasonStated,
                IsFiscalised = true,
                FiscalisedAt = nowUtc,
                DeviceId = device.DeviceId,
                ProfileId = profileId,
                EbsCounterNo = ebsCounterNo,
                SiteCode = effectiveSite,
                UserName = userName,
                CustomerCode = buyer.Code,
                CustomerName = buyer.Name,
                BuyerTan = buyer.Tan,
                BuyerBrn = buyer.Brn,
                BuyerNic = buyer.Nic,
                BuyerType = mapped.Document.Buyer.BuyerType,
                PersonType = mapped.Document.PersonType,
                BuyerAddress = buyer.BusinessAddr,
                TransactionType = mapped.Document.TransactionType,
                SalesTransactions = mapped.Document.SalesTransactions,
                Currency = mapped.Document.Currency,
                InvoiceDate = mapped.InvoiceDateFormatted,
                TotalAmtWoVatCur = mapped.TotalAmtWoVatCur,
                TotalAmtWoVatMur = mapped.TotalAmtWoVatMur,
                TotalVatAmount = mapped.TotalVatAmount,
                InvoiceTotal = mapped.InvoiceTotal,
                DiscountTotal = mapped.DiscountTotal,
                TotalAmountPaid = mapped.TotalAmountPaid,
                LineCount = mapped.Document.ItemList.Count,
                RequestUrl = requestUrl,
                RequestPayload = payloadJson,
                ResponsePayload = responseBody,
                HttpStatus = httpStatus,
                HepId = parsed.HepId,
                HepStatus = parsed.HepStatus,
                HepStatusMessage = parsed.HepStatusMessage,
                MraStatus = parsed.MraStatus,
                MraRequestId = parsed.MraRequestId,
                MraResponseId = parsed.MraResponseId,
                MraEnvironment = parsed.MraEnvironment,
                MraResponseDateTime = parsed.MraResponseDateTime,
                Irn = parsed.Irn,
                QrBase64 = parsed.QrBase64,
                X3Synced = false
            };

            try
            {
                _dbContext.HepFiscalInvoices.Add(entity);
                await _dbContext.SaveChangesAsync(cancellationToken);
            }
            catch (DbUpdateException dbEx)
            {
                // Race condition: concurrent retry inserted the same DocumentNo
                _dbContext.Entry(entity).State = EntityState.Detached;
                var raced = await _dbContext.HepFiscalInvoices
                    .AsNoTracking()
                    .FirstOrDefaultAsync(f => f.DocumentNo == docNo && f.IsFiscalised, cancellationToken);
                if (raced != null)
                {
                    return (200, ToResultDto(raced, hepStatusOverride: "duplicate"));
                }
                _logger.LogError(dbEx, "Failed saving HepFiscalInvoice for {DocumentNo}", docNo);
                throw;
            }

            _logger.LogInformation(
                "Fiscalised {DocumentNo} ({DocType}) via HEP {HepId}, IRN={Irn}, Env={Env}, DurationMs={Ms}",
                docNo, mapped.Document.InvoiceTypeDesc, parsed.HepId, parsed.Irn, parsed.MraEnvironment, sw.ElapsedMilliseconds);

            return (200, ToResultDto(entity));
        }

        public Task<HepFiscalInvoice?> GetFiscalInvoiceAsync(string documentNo, CancellationToken cancellationToken = default)
        {
            if (string.IsNullOrWhiteSpace(documentNo)) return Task.FromResult<HepFiscalInvoice?>(null);
            var clean = documentNo.Trim();
            return _dbContext.HepFiscalInvoices
                .AsNoTracking()
                .FirstOrDefaultAsync(f => f.DocumentNo == clean && f.IsFiscalised, cancellationToken);
        }

        public Task<bool> IsDocumentFiscalisedAsync(string documentNo, CancellationToken cancellationToken = default)
        {
            if (string.IsNullOrWhiteSpace(documentNo)) return Task.FromResult(false);
            var clean = documentNo.Trim();
            return _dbContext.HepFiscalInvoices
                .AsNoTracking()
                .AnyAsync(f => f.DocumentNo == clean && f.IsFiscalised, cancellationToken);
        }

        public async Task MarkX3SyncedAsync(string documentNo, string? x3DocumentId, CancellationToken cancellationToken = default)
        {
            if (string.IsNullOrWhiteSpace(documentNo)) return;
            var clean = documentNo.Trim();
            var row = await _dbContext.HepFiscalInvoices
                .FirstOrDefaultAsync(f => f.DocumentNo == clean, cancellationToken);
            if (row != null)
            {
                row.X3Synced = true;
                if (!string.IsNullOrWhiteSpace(x3DocumentId))
                {
                    row.X3DocumentId = x3DocumentId.Trim();
                }
                row.X3SyncedAt = DateTime.UtcNow;
                await _dbContext.SaveChangesAsync(cancellationToken);
            }
        }

        public Task<List<HepFiscalInvoice>> GetPendingX3SyncAsync(int limit = 100, CancellationToken cancellationToken = default)
        {
            return _dbContext.HepFiscalInvoices
                .AsNoTracking()
                .Where(f => f.IsFiscalised && !f.X3Synced)
                .OrderByDescending(f => f.FiscalisedAt)
                .Take(Math.Clamp(limit, 1, 500))
                .ToListAsync(cancellationToken);
        }

        public Task<List<HepFiscalFailureLog>> GetFailureLogsAsync(string? documentNo = null, int limit = 100, CancellationToken cancellationToken = default)
        {
            var query = _dbContext.HepFiscalFailureLogs.AsNoTracking();
            if (!string.IsNullOrWhiteSpace(documentNo))
            {
                var clean = documentNo.Trim();
                query = query.Where(f => f.DocumentNo == clean);
            }
            return query
                .OrderByDescending(f => f.CreatedAt)
                .Take(Math.Clamp(limit, 1, 500))
                .ToListAsync(cancellationToken);
        }

        private async Task<DeviceLocation?> ResolveDeviceAsync(
            string? requestDeviceId,
            string? headerDeviceId,
            string? userName,
            CancellationToken cancellationToken)
        {
            var candidateId = !string.IsNullOrWhiteSpace(headerDeviceId)
                ? headerDeviceId.Trim()
                : (!string.IsNullOrWhiteSpace(requestDeviceId) ? requestDeviceId.Trim() : null);

            if (!string.IsNullOrWhiteSpace(candidateId))
            {
                var match = await _dbContext.DeviceLocations
                    .AsNoTracking()
                    .FirstOrDefaultAsync(d =>
                        d.IsActive &&
                        (d.DeviceId == candidateId || d.DeviceName == candidateId || d.HardwareIdentifier == candidateId),
                        cancellationToken);
                if (match != null) return match;
            }

            if (!string.IsNullOrWhiteSpace(requestDeviceId) && !string.Equals(requestDeviceId.Trim(), candidateId, StringComparison.OrdinalIgnoreCase))
            {
                var clean = requestDeviceId.Trim();
                var match = await _dbContext.DeviceLocations
                    .AsNoTracking()
                    .FirstOrDefaultAsync(d =>
                        d.IsActive &&
                        (d.DeviceId == clean || d.DeviceName == clean || d.HardwareIdentifier == clean),
                        cancellationToken);
                if (match != null) return match;
            }

            if (!string.IsNullOrWhiteSpace(userName))
            {
                var cleanUser = userName.Trim();
                return await _dbContext.DeviceLocations
                    .AsNoTracking()
                    .Where(d => d.IsActive && d.AssignedUserName == cleanUser)
                    .OrderByDescending(d => d.UpdatedAt)
                    .FirstOrDefaultAsync(cancellationToken);
            }

            return null;
        }

        private async Task<FiscalSellerContext> ResolveSellerAsync(string siteCode)
        {
            var fallback = _fiscalSettings.Seller ?? new FiscalSellerFallbackSettings();
            var seller = new FiscalSellerContext
            {
                Name = fallback.Name,
                TradeName = string.IsNullOrWhiteSpace(fallback.TradeName) ? fallback.Name : fallback.TradeName,
                Tan = fallback.Tan,
                Brn = fallback.Brn,
                BusinessAddr = fallback.BusinessAddr,
                BusinessPhoneNo = fallback.BusinessPhoneNo
            };

            if (string.IsNullOrWhiteSpace(_innodisConnectionString))
            {
                return seller;
            }

            try
            {
                var schema = _schemaProvider?.GetSchemaName() ?? _syncSettings.X3SchemaName;
                var dbName = _syncSettings.X3DatabaseName;
                var companyCode = _syncSettings.X3CompanyCode;

                using var db = new SqlConnection(_innodisConnectionString);
                var cols = await db.QueryFirstOrDefaultAsync(
                    $@"SELECT
                        COL_LENGTH('{dbName}.{schema}.COMPANY', 'ZVAT_0') AS HasZvat,
                        COL_LENGTH('{dbName}.{schema}.COMPANY', 'EECNUM_0') AS HasEecNum");

                string tanExpr = cols?.HasZvat != null
                    ? "LTRIM(RTRIM(COALESCE(c.ZVAT_0, '')))"
                    : (cols?.HasEecNum != null ? "LTRIM(RTRIM(COALESCE(c.EECNUM_0, '')))" : "''");

                string sql = $@"
                    SELECT TOP 1
                        LTRIM(RTRIM(COALESCE(c.CPYNAM_0, ''))) AS Name,
                        LTRIM(RTRIM(COALESCE(c.CRN_0, ''))) AS Brn,
                        {tanExpr} AS Tan,
                        LTRIM(RTRIM(COALESCE(
                            NULLIF(CONCAT_WS(', ', NULLIF(LTRIM(RTRIM(a.BPAADDLIG_0)), ''), NULLIF(LTRIM(RTRIM(a.BPAADDLIG_1)), ''), NULLIF(LTRIM(RTRIM(a.CTY_0)), '')), ''),
                            ''
                        ))) AS BusinessAddr
                    FROM {dbName}.{schema}.COMPANY c WITH (NOLOCK)
                    OUTER APPLY (
                        SELECT TOP 1 bp.BPAADDLIG_0, bp.BPAADDLIG_1, bp.CTY_0
                        FROM {dbName}.{schema}.BPADDRESS bp WITH (NOLOCK)
                        WHERE bp.BPANUM_0 = c.CPY_0
                        ORDER BY CASE WHEN bp.BPATYP_0 = 2 THEN 0 ELSE 1 END, bp.BPAADD_0
                    ) a
                    WHERE c.CPY_0 = COALESCE(
                        (SELECT TOP 1 NULLIF(LTRIM(RTRIM(f.LEGCPY_0)), '') FROM {dbName}.{schema}.FACILITY f WITH (NOLOCK) WHERE LTRIM(RTRIM(f.FCY_0)) = @SiteCode),
                        @CompanyCode
                    )";

                var row = await db.QueryFirstOrDefaultAsync(sql, new { SiteCode = siteCode, CompanyCode = companyCode });
                if (row != null)
                {
                    if (!string.IsNullOrWhiteSpace((string?)row.Name))
                    {
                        seller.Name = ((string)row.Name).Trim();
                        seller.TradeName = seller.Name;
                    }
                    if (!string.IsNullOrWhiteSpace((string?)row.Tan)) seller.Tan = ((string)row.Tan).Trim();
                    if (!string.IsNullOrWhiteSpace((string?)row.Brn)) seller.Brn = ((string)row.Brn).Trim();
                    if (!string.IsNullOrWhiteSpace((string?)row.BusinessAddr)) seller.BusinessAddr = ((string)row.BusinessAddr).Trim();
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Falling back to configured seller details for site {Site}", siteCode);
            }

            return seller;
        }

        private async Task<FiscalBuyerContext> ResolveBuyerAsync(string customerCode, string? fallbackName)
        {
            var cleanCode = (customerCode ?? string.Empty).Trim();
            SalesInvoiceCustomerDto? cust = null;
            if (!string.IsNullOrEmpty(cleanCode))
            {
                try
                {
                    cust = await _salesInvoiceRepository.GetCustomerByCodeAsync(cleanCode);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Failed to load customer {CustomerCode} from X3 repository", cleanCode);
                }
            }

            var personType = cust?.TaxRule?.Trim() ?? string.Empty;
            var brn = cust?.Brn?.Trim() ?? string.Empty;
            var tan = cust?.Tan?.Trim() ?? string.Empty;

            return new FiscalBuyerContext
            {
                Code = cleanCode,
                Name = !string.IsNullOrWhiteSpace(cust?.Name) ? cust!.Name.Trim() : (fallbackName ?? string.Empty).Trim(),
                Tan = tan,
                Brn = brn,
                Nic = cust?.Nic?.Trim() ?? string.Empty,
                BusinessAddr = cust?.Address?.Trim() ?? string.Empty,
                PersonType = personType,
                BuyerType = personType,
                TransactionType = FiscalInvoiceMapper.NormalizeTransactionType(cust?.TransactionType, brn, tan)
            };
        }

        private async Task<(Dictionary<string, string> Natures, Dictionary<string, string> TaxLevels)> ResolveItemMetadataAsync(IEnumerable<string> skus)
        {
            var natures = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            var taxLevels = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

            var cleanSkus = skus.Where(s => !string.IsNullOrWhiteSpace(s)).Select(s => s.Trim()).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
            if (cleanSkus.Count == 0 || string.IsNullOrWhiteSpace(_innodisConnectionString))
            {
                return (natures, taxLevels);
            }

            try
            {
                var schema = _schemaProvider?.GetSchemaName() ?? _syncSettings.X3SchemaName;
                using var db = new SqlConnection(_innodisConnectionString);
                var rows = await db.QueryAsync(
                    $@"SELECT
                        LTRIM(RTRIM(ITMREF_0)) AS Sku,
                        COALESCE(STOMGTCOD_0, 2) AS Stomgtcod,
                        LTRIM(RTRIM(COALESCE(VACITM_0, ''))) AS TaxLevel
                       FROM {_syncSettings.X3DatabaseName}.{schema}.ITMMASTER WITH (NOLOCK)
                       WHERE ITMREF_0 IN @Skus",
                    new { Skus = cleanSkus });

                foreach (var r in rows)
                {
                    var sku = ((string)r.Sku).Trim();
                    int stomgt = Convert.ToInt32(r.Stomgtcod);
                    natures[sku] = stomgt == 2 ? "GOODS" : "SERVICES";
                    var lvl = ((string?)r.TaxLevel ?? string.Empty).Trim();
                    if (!string.IsNullOrEmpty(lvl))
                    {
                        taxLevels[sku] = lvl;
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Could not resolve ITMMASTER STOMGTCOD/VACITM for fiscalisation items");
            }

            return (natures, taxLevels);
        }

        private async Task<Dictionary<string, string>> ResolveMissingTaxCodesAsync(
            List<FiscaliseLineDto> lines,
            string buyerPersonType,
            Dictionary<string, string> itemTaxLevels)
        {
            var resolved = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            bool anyMissing = lines.Any(l => string.IsNullOrWhiteSpace(l.TaxCode) && string.IsNullOrWhiteSpace(l.TaxRule));
            if (!anyMissing) return resolved;

            try
            {
                var matrix = (await _salesInvoiceRepository.GetTaxDeterminationsAsync()).ToList();
                foreach (var line in lines)
                {
                    var sku = (line.Sku ?? string.Empty).Trim();
                    if (!string.IsNullOrWhiteSpace(line.TaxCode) || !string.IsNullOrWhiteSpace(line.TaxRule)) continue;
                    if (itemTaxLevels.TryGetValue(sku, out var itemLvl))
                    {
                        var match = matrix.FirstOrDefault(m =>
                            string.Equals(m.CustomerTaxRule, buyerPersonType, StringComparison.OrdinalIgnoreCase) &&
                            string.Equals(m.ItemTaxLevel, itemLvl, StringComparison.OrdinalIgnoreCase));
                        if (match != null && !string.IsNullOrWhiteSpace(match.TaxCode))
                        {
                            resolved[sku] = match.TaxCode.Trim();
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed resolving missing tax codes from TABVAC");
            }

            return resolved;
        }

        private async Task<string> ResolveReasonTextAsync(string? rawReason)
        {
            var clean = (rawReason ?? string.Empty).Trim();
            if (string.IsNullOrEmpty(clean)) return string.Empty;

            try
            {
                var reasons = await _salesInvoiceRepository.GetCreditNoteReasonsAsync();
                var match = reasons.FirstOrDefault(r => string.Equals(r.Code?.Trim(), clean, StringComparison.OrdinalIgnoreCase));
                if (match != null && !string.IsNullOrWhiteSpace(match.Description))
                {
                    return match.Description.Trim();
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Could not look up reason description for '{Reason}'", clean);
            }

            return clean;
        }

        private async Task RecordFailureAsync(
            string docNo,
            string docType,
            string docCategory,
            string? deviceId,
            string? profileId,
            string? siteCode,
            string? userName,
            string? customerCode,
            string? requestUrl,
            string? requestPayload,
            int? httpStatus,
            string? responsePayload,
            string? hepId,
            string? hepStatus,
            string? hepStatusMessage,
            string? mraStatus,
            string? mraRequestId,
            string? mraResponseId,
            string? errorCodes,
            string? errorMessages,
            string? exceptionText,
            int durationMs,
            CancellationToken cancellationToken)
        {
            _logger.LogWarning(
                "HEP fiscalisation failed for {DocumentNo} ({DocType}, Device={DeviceId}, Profile={ProfileId}): {Status} - {Msg}",
                docNo, docType, deviceId, profileId, hepStatus, errorMessages ?? hepStatusMessage ?? exceptionText);

            try
            {
                _dbContext.HepFiscalFailureLogs.Add(new HepFiscalFailureLog
                {
                    Id = Guid.NewGuid(),
                    DocumentNo = docNo,
                    DocumentType = docType,
                    DocumentCategory = docCategory,
                    DeviceId = deviceId,
                    ProfileId = profileId,
                    SiteCode = siteCode,
                    UserName = userName,
                    CustomerCode = customerCode,
                    RequestUrl = requestUrl,
                    RequestPayload = requestPayload,
                    HttpStatus = httpStatus,
                    ResponsePayload = responsePayload,
                    HepId = hepId,
                    HepStatus = hepStatus,
                    HepStatusMessage = Truncate(hepStatusMessage, 500),
                    MraStatus = mraStatus,
                    MraRequestId = mraRequestId,
                    MraResponseId = mraResponseId,
                    ErrorCodes = Truncate(errorCodes, 500),
                    ErrorMessages = Truncate(errorMessages, 2000),
                    ExceptionText = Truncate(exceptionText, 2000),
                    DurationMs = durationMs,
                    CreatedAt = DateTime.UtcNow
                });
                await _dbContext.SaveChangesAsync(cancellationToken);
            }
            catch (Exception logEx)
            {
                _logger.LogError(logEx, "Failed writing HepFiscalFailureLog for {DocumentNo}", docNo);
            }
        }

        private static string? Truncate(string? value, int maxLen)
        {
            if (string.IsNullOrEmpty(value)) return value;
            return value.Length <= maxLen ? value : value.Substring(0, maxLen);
        }

        private static FiscaliseResultDto ToResultDto(HepFiscalInvoice entity, string? hepStatusOverride = null)
        {
            return new FiscaliseResultDto
            {
                Success = true,
                DocumentNo = entity.DocumentNo,
                IsFiscalised = entity.IsFiscalised,
                HepId = entity.HepId,
                HepStatus = hepStatusOverride ?? entity.HepStatus,
                StatusMessage = hepStatusOverride == "duplicate"
                    ? $"Invoice '{entity.DocumentNo}' has already been fiscalised. Returning existing fiscal credentials."
                    : entity.HepStatusMessage,
                Irn = entity.Irn,
                QrBase64 = entity.QrBase64,
                MraStatus = entity.MraStatus,
                MraEnvironment = entity.MraEnvironment,
                MraRequestId = entity.MraRequestId,
                MraResponseId = entity.MraResponseId,
                FiscalisedAt = entity.FiscalisedAt
            };
        }
    }
}
