using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using EnterpriseAuth.Api.Core.Application.Common;
using EnterpriseAuth.Api.Core.Application.DTOs;
using EnterpriseAuth.Api.Core.Application.Interfaces;
using EnterpriseAuth.Api.Core.Domain.Entities;
using EnterpriseAuth.Api.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace EnterpriseAuth.Api.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    [Authorize]
    [EnterpriseAuth.Api.Infrastructure.Security.ValidateDeviceLicense]
    public class SalesInvoiceController : ControllerBase
    {
        private readonly ISalesInvoiceRepository _repository;
        private readonly ScanProductionDbContext _dbContext;
        private readonly ISageX3SoapService _soapService;
        private readonly ILogger<SalesInvoiceController> _logger;
        private readonly ISiteContextResolver _siteResolver;
        private readonly EnterpriseAuth.Api.Infrastructure.Features.SnapshotManagement.ISnapshotService? _snapshotService;
        private readonly IX3SchemaProvider? _schemaProvider;
        private readonly FiscalSettings _fiscalSettings;

        public SalesInvoiceController(
            ISalesInvoiceRepository repository,
            ScanProductionDbContext dbContext,
            ISageX3SoapService soapService,
            ILogger<SalesInvoiceController> logger,
            ISiteContextResolver siteResolver,
            EnterpriseAuth.Api.Infrastructure.Features.SnapshotManagement.ISnapshotService? snapshotService = null,
            IX3SchemaProvider? schemaProvider = null,
            Microsoft.Extensions.Options.IOptions<FiscalSettings>? fiscalSettings = null)
        {
            _repository = repository;
            _dbContext = dbContext;
            _soapService = soapService;
            _logger = logger;
            _siteResolver = siteResolver;
            _snapshotService = snapshotService;
            _schemaProvider = schemaProvider;
            _fiscalSettings = fiscalSettings?.Value ?? new FiscalSettings();
        }

        private string ResolveSchemaName()
        {
            if (_schemaProvider != null)
            {
                var provided = _schemaProvider.GetSchemaName();
                if (!string.IsNullOrWhiteSpace(provided))
                {
                    return provided.Trim().ToUpperInvariant();
                }
            }

            var headerSchema = Request?.Headers.TryGetValue("X-X3-Schema", out var hSchema) == true
                ? hSchema.ToString().Trim().ToUpperInvariant()
                : null;
            if (!string.IsNullOrEmpty(headerSchema) &&
                System.Text.RegularExpressions.Regex.IsMatch(headerSchema, "^[A-Z0-9_]{1,30}$"))
            {
                return headerSchema;
            }

            return "INLDRYRUN";
        }

        private IActionResult ServeSnapshotResult(EnterpriseAuth.Api.Infrastructure.Features.SnapshotManagement.SnapshotFileResult snapshot)
        {
            var requestETag = Request.Headers.IfNoneMatch.ToString();
            if (!string.IsNullOrEmpty(requestETag) && requestETag.Equals(snapshot.ETag, StringComparison.OrdinalIgnoreCase))
            {
                return StatusCode(304);
            }

            Response.Headers.ETag = snapshot.ETag;
            Response.Headers.LastModified = snapshot.LastModifiedUtc.ToString("R");
            if (snapshot.IsGzip)
            {
                Response.Headers.ContentEncoding = "gzip";
            }

            return PhysicalFile(snapshot.FilePath, "application/json");
        }

        [HttpPost("sync")]
        public async Task<IActionResult> SyncInvoice([FromBody] SalesInvoiceSyncDto payload)
        {
            if (payload == null || string.IsNullOrWhiteSpace(payload.InvoiceId))
                return BadRequest(new { success = false, error = "Invalid payload." });

            var totalAmount = payload.Lines.Sum(l => l.Total > 0 ? l.Total : ((l.Quantity * l.BasePrice) - l.DiscountAmount + l.VatAmount));
            if (payload.Lines.Count == 0 || totalAmount <= 0)
                return BadRequest(new { success = false, error = "Invoice with zero or negative total amount cannot be created." });

            // 0. Idempotency check: Already processed and synced in HIPO?
            var existingHeader = await _dbContext.StagingSalesInvoiceHeaders
                .Include(h => h.Lines)
                .FirstOrDefaultAsync(h => h.InvoiceId == payload.InvoiceId);

            string? recoveredX3DocId = null;
            string? recoveredRawPayload = null;

            if (existingHeader != null)
            {
                var existingTotal = existingHeader.Lines.Sum(l => l.Total > 0 ? l.Total : ((l.Quantity * l.BasePrice) - l.DiscountAmount + l.VatAmount));
                bool customerMatches = string.Equals(existingHeader.CustomerCode?.Trim(), payload.CustomerCode?.Trim(), StringComparison.OrdinalIgnoreCase);
                bool totalMatches = Math.Abs(existingTotal - (double)totalAmount) < 0.05;

                // Collision detection: If customer or total amount does not match, the mobile client generated
                // a duplicate unique invoice number that was already consumed by an existing invoice.
                if (!customerMatches || !totalMatches)
                {
                    _logger.LogError("Conflict: Incoming invoice {InvoiceId} (Customer: {NewCustomer}, Total: {NewTotal}) collides with existing invoice (Customer: {OldCustomer}, Total: {OldTotal}, X3 Document: {X3DocId})",
                        payload.InvoiceId, payload.CustomerCode, totalAmount, existingHeader.CustomerCode, existingTotal, existingHeader.X3DocumentId);

                    return Conflict(new
                    {
                        success = false,
                        invoiceId = payload.InvoiceId,
                        error = $"Invoice unique number '{payload.InvoiceId}' has already been used by an existing invoice in Sage X3 ({existingHeader.X3DocumentId ?? "synced"}). Duplicate unique numbers cannot be processed."
                    });
                }

                // Legitimate network retry: same customer and total, already succeeded in X3
                if (existingHeader.IsProcessedByX3 && !string.IsNullOrEmpty(existingHeader.X3DocumentId))
                {
                    return Ok(new
                    {
                        success = true,
                        invoiceId = payload.InvoiceId,
                        x3DocumentId = existingHeader.X3DocumentId,
                        message = "Invoice already processed and synced."
                    });
                }
            }

            // 1. Idempotency check: Did a previous SOAP request already succeed in Sage X3 for this exact transaction
            //    (including cases where the backend crashed before committing StagingSalesInvoiceHeaders)?
            var priorAudit = await _dbContext.X3SoapAudits
                .Where(a => a.ActionName == "ImportSalesInvoice" && a.Identifier == payload.InvoiceId && a.IsSuccess)
                .OrderByDescending(a => a.CreatedAt)
                .FirstOrDefaultAsync();

            if (priorAudit != null && !string.IsNullOrEmpty(priorAudit.ResponsePayload) && priorAudit.ResponsePayload.Contains("Creation of "))
            {
                var idx = priorAudit.ResponsePayload.IndexOf("Creation of ");
                var sub = priorAudit.ResponsePayload.Substring(idx + "Creation of ".Length);
                var endIdx = sub.IndexOfAny(new[] { '<', '"', '\r', '\n', ' ' });
                recoveredX3DocId = endIdx > 0 ? sub.Substring(0, endIdx).Trim() : sub.Trim();
                recoveredRawPayload = priorAudit.ResponsePayload;
            }

            // Hard fiscalisation gate: reject X3 SOAP sync unless document is marked fiscalised in HepFiscalInvoices
            if (_fiscalSettings.EnforceX3Gate && string.IsNullOrEmpty(recoveredX3DocId))
            {
                var isFiscalised = await _dbContext.HepFiscalInvoices
                    .AsNoTracking()
                    .AnyAsync(f => f.DocumentNo == payload.InvoiceId && f.IsFiscalised);
                if (!isFiscalised)
                {
                    _logger.LogWarning("X3 Gate rejected un-fiscalised invoice {InvoiceId}", payload.InvoiceId);
                    return Conflict(new
                    {
                        success = false,
                        invoiceId = payload.InvoiceId,
                        errorCode = "ERR_NOT_FISCALISED",
                        error = $"Invoice '{payload.InvoiceId}' cannot be integrated into Sage X3 because it has not been fiscalised in HEP."
                    });
                }
            }

            var userSiteCode = User.FindFirst("SiteCode")?.Value;
            var (invSiteCtx, _) = await _siteResolver.ResolveSiteContextAsync(User, payload.SalesSite, allowAll: true);
            if (invSiteCtx != null && !string.IsNullOrWhiteSpace(invSiteCtx.FinancialSiteCode))
            {
                payload.SalesSite = invSiteCtx.FinancialSiteCode;
                if (string.IsNullOrWhiteSpace(payload.ShippingSite))
                {
                    payload.ShippingSite = invSiteCtx.ShippingSiteCode;
                }
            }
            else if (string.IsNullOrWhiteSpace(payload.SalesSite) || payload.SalesSite == "ALL")
            {
                payload.SalesSite = "POD";
            }

            var resolvedTabletSource = await ResolveTabletSourceAsync(
                payload.TabletSource,
                payload.DeviceId,
                payload.UserName ?? payload.CreatedBy ?? User.Identity?.Name);

            var targetShippingSite = !string.IsNullOrWhiteSpace(payload.ShippingSite)
                ? payload.ShippingSite.Trim()
                : (!string.IsNullOrWhiteSpace(payload.SalesSite) ? payload.SalesSite.Trim() : "POD");
            var lorryScope = await ResolveCallerLorryScopeAsync(targetShippingSite, payload.DeviceId);
            if (lorryScope.HasDeviceContext)
            {
                if (string.IsNullOrEmpty(lorryScope.AssignedLorry))
                {
                    return BadRequest(new
                    {
                        success = false,
                        error = "No lorry is assigned to this tablet. Assign a lorry before syncing sales invoices."
                    });
                }

                foreach (var l in payload.Lines)
                {
                    if (!string.IsNullOrWhiteSpace(l.StockStatus) &&
                        !l.StockStatus.Trim().StartsWith("A", StringComparison.OrdinalIgnoreCase))
                    {
                        return BadRequest(new
                        {
                            success = false,
                            error = $"Line '{l.Sku}' has stock status '{l.StockStatus}'. Only status 'A' (Approved) stock can be sold."
                        });
                    }

                    if (!IsLineAllowedForLorry(l, lorryScope))
                    {
                        return StatusCode(StatusCodes.Status403Forbidden, new
                        {
                            success = false,
                            error = $"Line '{l.Sku}' references '{l.Location}/{l.Warehouse}', which does not match this tablet's assigned lorry '{lorryScope.AssignedLorry}'."
                        });
                    }

                    if (string.IsNullOrWhiteSpace(l.Warehouse))
                    {
                        l.Warehouse = lorryScope.AssignedWarehouse ?? lorryScope.AssignedLorry;
                    }
                    if (string.IsNullOrWhiteSpace(l.Location))
                    {
                        l.Location = lorryScope.AssignedLorry;
                    }
                }
            }
            else
            {
                foreach (var l in payload.Lines)
                {
                    if (!string.IsNullOrWhiteSpace(l.StockStatus) &&
                        !l.StockStatus.Trim().StartsWith("A", StringComparison.OrdinalIgnoreCase))
                    {
                        return BadRequest(new
                        {
                            success = false,
                            error = $"Line '{l.Sku}' has stock status '{l.StockStatus}'. Only status 'A' (Approved) stock can be sold."
                        });
                    }
                }
            }

            // Process one invoice at a time, transactionally
            using var transaction = await _dbContext.Database.BeginTransactionAsync();
            try
            {
                if (existingHeader == null)
                {
                    existingHeader = new StagingSalesInvoiceHeader
                    {
                        InvoiceId = payload.InvoiceId,
                        SalesSite = payload.SalesSite,
                        CustomerCode = payload.CustomerCode,
                        PricingRule = payload.PricingRule,
                        DueDate = payload.DueDate,
                        CreatedAt = payload.CreatedAt,
                        Reference = payload.Reference,
                        InvoiceType = !string.IsNullOrEmpty(payload.InvoiceType) ? payload.InvoiceType : "STD",
                        IsProcessedByX3 = false,
                        SyncedAt = DateTime.UtcNow,
                        UserName = !string.IsNullOrWhiteSpace(payload.UserName) ? payload.UserName : (User.Identity?.Name ?? "system"),
                        CreatedBy = !string.IsNullOrWhiteSpace(payload.CreatedBy) ? payload.CreatedBy : (!string.IsNullOrWhiteSpace(payload.UserName) ? payload.UserName : (User.Identity?.Name ?? "system")),
                        DeviceId = !string.IsNullOrWhiteSpace(payload.DeviceId) ? payload.DeviceId : User.FindFirst("DeviceId")?.Value,
                        SalesRep = payload.SalesRep,
                        PaymentTerm = payload.PaymentTerm,
                        TransactionalId = !string.IsNullOrWhiteSpace(payload.TransactionalId) ? payload.TransactionalId : payload.InvoiceId,
                        TabletSource = resolvedTabletSource
                    };

                    var usedLineNos = new HashSet<int>();
                    int nextLineNo = 1;
                    foreach (var l in payload.Lines)
                    {
                        var resolvedLineNo = (l.LineNo > 0 && usedLineNos.Add(l.LineNo))
                            ? l.LineNo
                            : nextLineNo;
                        while (!usedLineNos.Add(resolvedLineNo))
                        {
                            resolvedLineNo++;
                        }
                        if (resolvedLineNo >= nextLineNo) nextLineNo = resolvedLineNo + 1;

                        var lineTotal = l.Total > 0 ? l.Total : ((l.Quantity * l.BasePrice) - l.DiscountAmount + l.VatAmount);
                        var disc2 = l.Discount2 > 0 ? l.Discount2 : l.DiscountAmountFlat;
                        existingHeader.Lines.Add(new StagingSalesInvoiceLine
                        {
                            InvoiceId = payload.InvoiceId,
                            Sku = l.Sku,
                            Name = l.Name,
                            LineNo = resolvedLineNo,
                            Quantity = (double)l.Quantity,
                            BasePrice = (double)l.BasePrice,
                            DiscountAmount = (double)l.DiscountAmount,
                            DiscountAmountFlat = (double)l.DiscountAmountFlat,
                            Discount2 = (double)disc2,
                            Discount3 = (double)l.Discount3,
                            VatAmount = (double)l.VatAmount,
                            Total = (double)lineTotal,
                            LotNumber = l.LotNumber,
                            Warehouse = l.Warehouse,
                            Location = l.Location,
                            SalesUnit = l.SalesUnit,
                            Cce0 = l.Cce0,
                            TaxRule = l.TaxRule,
                            IsFoc = l.IsFoc,
                            MainItemSku = l.MainItemSku
                        });
                    }

                    _dbContext.StagingSalesInvoiceHeaders.Add(existingHeader);
                    await _dbContext.SaveChangesAsync(); // Generate IDs and save locally
                }
                else
                {
                    // Repopulate [NotMapped] properties (Location, IsFoc, MainItemSku, Discount3, DiscountAmountFlat) from incoming payload when retrying
                    foreach (var line in existingHeader.Lines)
                    {
                        var matched = payload.Lines.FirstOrDefault(p => p.LineNo > 0 && p.LineNo == line.LineNo)
                            ?? payload.Lines.FirstOrDefault(p =>
                                !string.IsNullOrEmpty(p.Sku) &&
                                string.Equals(p.Sku, line.Sku, StringComparison.OrdinalIgnoreCase) &&
                                string.Equals(p.LotNumber ?? "", line.LotNumber ?? "", StringComparison.OrdinalIgnoreCase) &&
                                p.IsFoc == line.IsFoc);
                        if (matched != null)
                        {
                            line.IsFoc = matched.IsFoc;
                            line.MainItemSku = matched.MainItemSku;
                            line.Discount3 = matched.Discount3;
                            line.DiscountAmountFlat = matched.DiscountAmountFlat;
                            if (!string.IsNullOrEmpty(matched.Location))
                            {
                                line.Location = matched.Location;
                            }
                            if (string.IsNullOrWhiteSpace(line.LotNumber) && !string.IsNullOrWhiteSpace(matched.LotNumber))
                            {
                                line.LotNumber = matched.LotNumber;
                            }
                        }
                    }
                }

                // Populate [NotMapped] Payments from incoming payload so SOAP service knows if transaction is CASH (MICAS) or CREDIT (MICRE)
                if (payload.Payments != null && payload.Payments.Count > 0)
                {
                    existingHeader.Payments.Clear();
                    foreach (var p in payload.Payments)
                    {
                        existingHeader.Payments.Add(new StagingSalesInvoicePayment
                        {
                            DocumentType = "INVOICE",
                            DocumentId = payload.InvoiceId,
                            PaymentMethod = p.Method,
                            Amount = p.Amount,
                            BankCode = p.BankCode,
                            BankName = p.BankName,
                            ChequeNumber = p.ChequeNumber,
                            ChequeDate = p.ChequeDate,
                            QrTransactionRef = p.QrTransactionRef,
                            LocalPaymentId = p.LocalPaymentId,
                            SalesSite = existingHeader.SalesSite ?? "",
                            CustomerCode = existingHeader.CustomerCode ?? ""
                        });
                    }
                }

                // Always assign [NotMapped] TabletSource even when retrying an existing staging header
                existingHeader.TabletSource = resolvedTabletSource;

                string? x3DocId = recoveredX3DocId;
                string? x3ReqNum = null;
                string? x3RawPayload = recoveredRawPayload;
                X3ImportResult? importResult = null;

                // 2. Sync to X3 using SOAP service if not already recovered from a previous successful call
                if (string.IsNullOrEmpty(x3DocId))
                {
                    importResult = await _soapService.ImportSalesInvoiceAsync(existingHeader);

                    bool isSuccess = importResult.Success || 
                        (!string.IsNullOrEmpty(importResult.RawPayload) && importResult.RawPayload.Contains("Creation of ", StringComparison.OrdinalIgnoreCase));

                    if (!isSuccess)
                    {
                        await transaction.RollbackAsync();
                        string errorMsg = !string.IsNullOrWhiteSpace(importResult.TechnicalError) 
                            ? importResult.TechnicalError 
                            : string.Join(" | ", importResult.Messages);

                        return BadRequest(new 
                        { 
                            success = false, 
                            invoiceId = payload.InvoiceId, 
                            error = errorMsg, 
                            rawPayload = importResult.RawPayload,
                            messages = importResult.Messages != null && importResult.Messages.Count > 0 ? importResult.Messages : new List<string> { errorMsg }
                        });
                    }

                    x3DocId = importResult.DocumentId;
                    x3ReqNum = importResult.RequestNumber;
                    x3RawPayload = importResult.RawPayload;
                }

                existingHeader.IsProcessedByX3 = true;
                if (!string.IsNullOrEmpty(x3DocId))
                {
                    existingHeader.X3DocumentId = x3DocId;
                }
                await _dbContext.SaveChangesAsync();

                // 3. Commit invoice transaction IMMEDIATELY so confirmed invoice is never lost in HIPO
                await transaction.CommitAsync();

                // Update HepFiscalInvoices X3 sync status for troubleshooting tracking
                try
                {
                    var fiscalRow = await _dbContext.HepFiscalInvoices
                        .FirstOrDefaultAsync(f => f.DocumentNo == payload.InvoiceId);
                    if (fiscalRow != null)
                    {
                        fiscalRow.X3Synced = true;
                        if (!string.IsNullOrWhiteSpace(x3DocId)) fiscalRow.X3DocumentId = x3DocId;
                        fiscalRow.X3SyncedAt = DateTime.UtcNow;
                        await _dbContext.SaveChangesAsync();
                    }
                }
                catch (Exception fEx)
                {
                    _logger.LogWarning(fEx, "Failed updating HepFiscalInvoices X3Synced for {InvoiceId}", payload.InvoiceId);
                }

                // 4. Decoupled Payment Sync Phase: Staging and SOAP invocation outside invoice transaction
                bool paymentSynced = false;
                string? x3PaymentId = null;
                string? paymentError = null;

                if (payload.Payments != null && payload.Payments.Count > 0)
                {
                    var stagingPayments = payload.Payments.Select(p => new StagingSalesInvoicePayment
                    {
                        DocumentType = "INVOICE",
                        DocumentId = payload.InvoiceId,
                        X3DocumentType = "SINV",
                        X3EntryType = "REC",
                        X3Sign = 2,
                        X3InvoiceDocumentId = existingHeader.X3DocumentId,
                        SalesSite = existingHeader.SalesSite ?? (!string.IsNullOrWhiteSpace(userSiteCode) && userSiteCode != "ALL" ? userSiteCode : "POD"),
                        CustomerCode = existingHeader.CustomerCode ?? "",
                        CustomerName = existingHeader.CustomerName,
                        PaymentMethod = p.Method,
                        Amount = p.Amount,
                        BankCode = string.Equals(p.Method, "CREDIT", StringComparison.OrdinalIgnoreCase) ? null : p.BankCode,
                        BankName = string.Equals(p.Method, "CREDIT", StringComparison.OrdinalIgnoreCase) ? null : p.BankName,
                        ChequeNumber = p.ChequeNumber,
                        ChequeDate = p.ChequeDate,
                        QrTransactionRef = p.QrTransactionRef,
                        LocalPaymentId = p.LocalPaymentId,
                        CreatedAt = payload.CreatedAt,
                        CreatedBy = existingHeader.CreatedBy,
                        UserName = existingHeader.UserName,
                        DeviceId = existingHeader.DeviceId,
                        IsProcessedByX3 = false,
                        IsSynced = 0,
                        SyncedAt = DateTime.UtcNow
                    }).ToList();

                    // Payment SOAP trigger temporarily deactivated per business requirement.
                    // Payments are persisted to MSSQL staging tables with IsProcessedByX3 = false, IsSynced = 0.
                    try
                    {
                        _dbContext.StagingSalesInvoicePayments.AddRange(stagingPayments);
                        await _dbContext.SaveChangesAsync();
                        paymentSynced = true;
                    }
                    catch (Exception payDbEx)
                    {
                        _logger.LogError(payDbEx, "Failed to persist StagingSalesInvoicePayments for Invoice {InvoiceId}: {Message}", payload.InvoiceId, payDbEx.InnerException?.Message ?? payDbEx.Message);
                    }
                }

                var syncSite = !string.IsNullOrWhiteSpace(userSiteCode) && userSiteCode != "ALL" 
                    ? userSiteCode 
                    : (!string.IsNullOrWhiteSpace(payload.SalesSite) ? payload.SalesSite : "IPL");
                var syncUser = User.Claims.FirstOrDefault(c => c.Type == "username")?.Value ?? User.Identity?.Name ?? payload.UserName ?? "sales-user";
                var syncDevId = !string.IsNullOrWhiteSpace(payload.DeviceId) ? payload.DeviceId : syncUser;
                try
                {
                    _dbContext.AuditLogs.Add(new AuditLog
                    {
                        EntityName = "DeviceSync",
                        EntityIdString = syncDevId,
                        ActionType = "SYNC_SALES_INVOICE",
                        Site = syncSite,
                        Payload = $"{{\"InvoiceId\":\"{payload.InvoiceId}\",\"X3DocId\":\"{x3DocId}\"}}",
                        PerformedBy = syncUser,
                        PerformedAt = DateTime.UtcNow,
                        DeviceId = syncDevId
                    });
                    await _dbContext.SaveChangesAsync();
                }
                catch (Exception auditEx)
                {
                    _logger.LogWarning("Failed to write DeviceSync audit for Invoice {InvoiceId}: {Msg}", payload.InvoiceId, auditEx.Message);
                }

                return Ok(new
                {
                    success = true,
                    invoiceId = payload.InvoiceId,
                    x3Request = x3ReqNum,
                    x3DocumentId = x3DocId,
                    rawPayload = x3RawPayload,
                    messages = importResult?.Messages != null && importResult.Messages.Count > 0 
                        ? importResult.Messages 
                        : new List<string> { $"Created in Sage X3: {x3DocId}" },
                    paymentSynced,
                    x3PaymentId,
                    paymentError
                });
            }
            catch (Exception ex)
            {
                try { await transaction.RollbackAsync(); } catch { }
                var detailedError = ex.InnerException != null ? $"{ex.Message} --> {ex.InnerException.Message}" : ex.Message;
                _logger.LogError(ex, "Failed to sync sales invoice {InvoiceId}: {Error}", payload.InvoiceId, detailedError);
                return StatusCode(500, new { success = false, invoiceId = payload.InvoiceId, error = detailedError });
            }
        }

        [HttpPost("sync-credit-note")]
        public async Task<IActionResult> SyncCreditNote([FromBody] CreditNoteSyncDto payload)
        {
            if (payload == null || string.IsNullOrWhiteSpace(payload.CreditNoteId))
                return BadRequest(new { success = false, error = "Invalid credit note payload." });

            if (payload.GrandTotal <= 0)
                return BadRequest(new { success = false, error = "Credit note with zero or negative total amount cannot be created." });

            try
            {
                // 0. Idempotency check: Already processed and synced in HIPO?
                var existingHeader = await _dbContext.StagingSalesInvoiceHeaders
                    .Include(h => h.Lines)
                    .FirstOrDefaultAsync(h => h.InvoiceId == payload.CreditNoteId);

                string? recoveredX3DocId = null;
                string? recoveredRawPayload = null;

                if (existingHeader != null)
                {
                    bool customerMatches = string.Equals(existingHeader.CustomerCode?.Trim(), payload.CustomerCode?.Trim(), StringComparison.OrdinalIgnoreCase);
                    var existingTotal = existingHeader.Lines.Sum(l => l.Total > 0 ? l.Total : ((l.Quantity * l.BasePrice) - l.DiscountAmount + l.VatAmount));
                    bool totalMatches = Math.Abs(existingTotal - (double)payload.GrandTotal) < 0.05;

                    // Collision detection: If customer or grand total does not match, reject conflict
                    if (!customerMatches || !totalMatches)
                    {
                        _logger.LogError("Conflict: Incoming credit note {CreditNoteId} (Customer: {NewCustomer}, Total: {NewTotal}) collides with existing document (Customer: {OldCustomer}, Total: {OldTotal}, X3 Document: {X3DocId})",
                            payload.CreditNoteId, payload.CustomerCode, payload.GrandTotal, existingHeader.CustomerCode, existingTotal, existingHeader.X3DocumentId);

                        return Conflict(new
                        {
                            success = false,
                            creditNoteId = payload.CreditNoteId,
                            error = $"Credit note unique number '{payload.CreditNoteId}' is already used by an existing document in Sage X3 ({existingHeader.X3DocumentId ?? "synced"}). Duplicate unique numbers cannot be processed."
                        });
                    }

                    // Legitimate retry of existing credit note
                    if (existingHeader.IsProcessedByX3 && !string.IsNullOrEmpty(existingHeader.X3DocumentId))
                    {
                        return Ok(new
                        {
                            success = true,
                            creditNoteId = payload.CreditNoteId,
                            x3DocumentId = existingHeader.X3DocumentId,
                            message = "Credit note already processed and synced."
                        });
                    }
                }

                // 1. Idempotency check: Did a previous SOAP request already succeed in Sage X3
                //    (including cases where the backend crashed before committing StagingSalesInvoiceHeaders)?
                var priorAudit = await _dbContext.X3SoapAudits
                    .Where(a => a.ActionName == "ImportCreditNote" && a.Identifier == payload.CreditNoteId && a.IsSuccess)
                    .OrderByDescending(a => a.CreatedAt)
                    .FirstOrDefaultAsync();

                if (priorAudit != null && !string.IsNullOrEmpty(priorAudit.ResponsePayload) && priorAudit.ResponsePayload.Contains("Creation of "))
                {
                    var idx = priorAudit.ResponsePayload.IndexOf("Creation of ");
                    var sub = priorAudit.ResponsePayload.Substring(idx + "Creation of ".Length);
                    var endIdx = sub.IndexOfAny(new[] { '<', '"', '\r', '\n', ' ' });
                    recoveredX3DocId = endIdx > 0 ? sub.Substring(0, endIdx).Trim() : sub.Trim();
                    recoveredRawPayload = priorAudit.ResponsePayload;
                }

                // Hard fiscalisation gate: reject X3 SOAP sync unless credit note / return is fiscalised in HepFiscalInvoices
                if (_fiscalSettings.EnforceX3Gate && string.IsNullOrEmpty(recoveredX3DocId))
                {
                    var isFiscalised = await _dbContext.HepFiscalInvoices
                        .AsNoTracking()
                        .AnyAsync(f => f.DocumentNo == payload.CreditNoteId && f.IsFiscalised);
                    if (!isFiscalised)
                    {
                        _logger.LogWarning("X3 Gate rejected un-fiscalised credit note/return {CreditNoteId}", payload.CreditNoteId);
                        return Conflict(new
                        {
                            success = false,
                            creditNoteId = payload.CreditNoteId,
                            errorCode = "ERR_NOT_FISCALISED",
                            error = $"Credit note / return '{payload.CreditNoteId}' cannot be integrated into Sage X3 because it has not been fiscalised in HEP."
                        });
                    }
                }

                var userSiteCode = User.FindFirst("SiteCode")?.Value;
                var (crnSiteCtx, _) = await _siteResolver.ResolveSiteContextAsync(User, payload.SalesSite, allowAll: true);
                if (crnSiteCtx != null && !string.IsNullOrWhiteSpace(crnSiteCtx.FinancialSiteCode))
                {
                    payload.SalesSite = crnSiteCtx.FinancialSiteCode;
                    if (string.IsNullOrWhiteSpace(payload.ShippingSite))
                    {
                        payload.ShippingSite = crnSiteCtx.ShippingSiteCode;
                    }
                }
                else if (string.IsNullOrWhiteSpace(payload.SalesSite) || payload.SalesSite == "ALL")
                {
                    payload.SalesSite = "POD";
                }

                var resolvedCrnTabletSource = await ResolveTabletSourceAsync(
                    payload.TabletSource,
                    payload.DeviceId,
                    payload.UserName ?? payload.CreatedBy ?? User.Identity?.Name);

                // Atomic transaction: rollback on failure, commit only on confirmed X3 success
                using var transaction = await _dbContext.Database.BeginTransactionAsync();
                try
                {
                if (existingHeader == null)
                {
                    // Resolve real Sage X3 Document ID from HIPO Staging table if linked to an invoice
                    string resolvedOriginX3Id = payload.OriginalInvoiceId ?? "";
                    if (!string.IsNullOrWhiteSpace(payload.OriginalInvoiceId))
                    {
                        var matchingInvoice = await _dbContext.StagingSalesInvoiceHeaders
                            .AsNoTracking()
                            .FirstOrDefaultAsync(h => h.InvoiceId == payload.OriginalInvoiceId 
                                                   || h.TransactionalId == payload.OriginalInvoiceId
                                                   || h.X3DocumentId == payload.OriginalInvoiceId);

                        if (matchingInvoice != null && !string.IsNullOrWhiteSpace(matchingInvoice.X3DocumentId))
                        {
                            resolvedOriginX3Id = matchingInvoice.X3DocumentId;
                        }
                    }

                    // Map to normalized StagingSalesInvoiceHeader
                    string categoryStr = payload.Category > 0 ? payload.Category.ToString() : (payload.CreditNoteType == "RETURN" ? "3" : "2");
                    existingHeader = new StagingSalesInvoiceHeader
                    {
                        InvoiceId = payload.CreditNoteId,
                        InvoiceType = categoryStr, // "2" for Credit Note, "3" for Return
                        SalesSite = payload.SalesSite,
                        CustomerCode = payload.CustomerCode,
                        CustomerName = payload.CustomerName,
                        SalesRep = payload.SalesRep,
                        DueDate = payload.DueDate ?? payload.CreatedAt ?? DateTime.UtcNow.ToString("yyyyMMdd"),
                        CreatedAt = payload.CreatedAt ?? DateTime.UtcNow.ToString("yyyyMMdd"),
                        CreatedBy = !string.IsNullOrWhiteSpace(payload.CreatedBy) ? payload.CreatedBy : (User.Identity?.Name ?? "system"),
                        UserName = !string.IsNullOrWhiteSpace(payload.UserName) ? payload.UserName : (!string.IsNullOrWhiteSpace(payload.CreatedBy) ? payload.CreatedBy : (User.Identity?.Name ?? "system")),
                        DeviceId = !string.IsNullOrWhiteSpace(payload.DeviceId) ? payload.DeviceId : User.FindFirst("DeviceId")?.Value,
                        TransactionalId = !string.IsNullOrWhiteSpace(payload.TransactionalId) ? payload.TransactionalId : payload.CreditNoteId,
                        Reference = payload.Reference ?? "",
                        OriginInvoiceId = resolvedOriginX3Id,
                        Reason = payload.Reason,
                        SettlementType = payload.SettlementType,
                        TransactionMode = payload.TransactionMode ?? (string.IsNullOrEmpty(resolvedOriginX3Id) ? "1" : "4"),
                        TabletSource = resolvedCrnTabletSource,
                        IsProcessedByX3 = false,
                        SyncedAt = DateTime.UtcNow
                    };

                    if (payload.Refunds != null && payload.Refunds.Count > 0)
                    {
                        foreach (var r in payload.Refunds)
                        {
                            existingHeader.Payments.Add(new StagingSalesInvoicePayment
                            {
                                DocumentType = "CREDIT_NOTE",
                                DocumentId = payload.CreditNoteId,
                                PaymentMethod = r.Method,
                                Amount = (decimal)r.Amount,
                                BankCode = r.BankCode
                            });
                        }
                    }

                    foreach (var line in payload.Lines)
                    {
                        existingHeader.Lines.Add(new StagingSalesInvoiceLine
                        {
                            InvoiceId = payload.CreditNoteId,
                            LineNo = line.LineNo,
                            Sku = line.Sku ?? line.StandaloneSku,
                            Name = line.Name ?? line.StandaloneName,
                            Quantity = line.Quantity,
                            BasePrice = line.BasePrice ?? line.StandalonePrice ?? 0.0,
                            DiscountAmount = line.DiscountAmount ?? 0.0,
                            Discount2 = line.Discount2 ?? 0.0,
                            Discount3 = line.Discount3 ?? 0.0,
                            TaxRule = line.TaxRule ?? line.StandaloneTaxRule ?? "VAT0",
                            SalesUnit = line.SalesUnit ?? line.StandaloneSalesUnit ?? "UN",
                            Warehouse = line.Warehouse ?? line.StandaloneWarehouse ?? "",
                            LotNumber = line.LotNumber ?? line.StandaloneLot ?? "",
                            Cce0 = line.Cce0 ?? line.StandaloneCce0 ?? "COMMERCIAL",
                            OriginLineNo = line.OriginLineNo,
                            StockStatus = !string.IsNullOrWhiteSpace(line.StockStatus) ? line.StockStatus.Trim().ToUpperInvariant() : "A",
                            ReturnCondition = line.ReturnCondition,
                            ExpiryDate = line.ExpiryDate,
                            Location = line.Location
                        });
                    }

                    _dbContext.StagingSalesInvoiceHeaders.Add(existingHeader);
                    await _dbContext.SaveChangesAsync();
                }
                else
                {
                    // Re-hydrate [NotMapped] properties and update line quality metadata on retry
                    string resolvedOriginX3Id = payload.OriginalInvoiceId ?? "";
                    if (!string.IsNullOrWhiteSpace(payload.OriginalInvoiceId))
                    {
                        var matchingInvoice = await _dbContext.StagingSalesInvoiceHeaders
                            .AsNoTracking()
                            .FirstOrDefaultAsync(h => h.InvoiceId == payload.OriginalInvoiceId 
                                                   || h.TransactionalId == payload.OriginalInvoiceId
                                                   || h.X3DocumentId == payload.OriginalInvoiceId);

                        if (matchingInvoice != null && !string.IsNullOrWhiteSpace(matchingInvoice.X3DocumentId))
                        {
                            resolvedOriginX3Id = matchingInvoice.X3DocumentId;
                        }
                    }

                    existingHeader.OriginInvoiceId = resolvedOriginX3Id;
                    existingHeader.Reason = payload.Reason;
                    existingHeader.SettlementType = payload.SettlementType;
                    existingHeader.TransactionMode = payload.TransactionMode ?? (string.IsNullOrEmpty(resolvedOriginX3Id) ? "1" : "4");
                    existingHeader.CustomerName = payload.CustomerName ?? existingHeader.CustomerName;
                    existingHeader.TabletSource = resolvedCrnTabletSource;

                    if (payload.Refunds != null && payload.Refunds.Count > 0)
                    {
                        existingHeader.Payments.Clear();
                        foreach (var r in payload.Refunds)
                        {
                            existingHeader.Payments.Add(new StagingSalesInvoicePayment
                            {
                                DocumentType = "CREDIT_NOTE",
                                DocumentId = payload.CreditNoteId,
                                PaymentMethod = r.Method,
                                Amount = (decimal)r.Amount,
                                BankCode = r.BankCode
                            });
                        }
                    }
                    if (!string.IsNullOrWhiteSpace(payload.SalesSite))
                    {
                        existingHeader.SalesSite = payload.SalesSite;
                    }
                    if (payload.Category > 0)
                    {
                        existingHeader.InvoiceType = payload.Category.ToString();
                    }

                    if (payload.Lines != null && payload.Lines.Count > 0)
                    {
                        foreach (var pl in payload.Lines)
                        {
                            var existingLine = existingHeader.Lines.FirstOrDefault(l => l.LineNo == pl.LineNo || l.Sku == pl.Sku);
                            if (existingLine != null)
                            {
                                if (!string.IsNullOrWhiteSpace(pl.StockStatus)) existingLine.StockStatus = pl.StockStatus.Trim().ToUpperInvariant();
                                if (!string.IsNullOrWhiteSpace(pl.ReturnCondition)) existingLine.ReturnCondition = pl.ReturnCondition;
                                if (!string.IsNullOrWhiteSpace(pl.ExpiryDate)) existingLine.ExpiryDate = pl.ExpiryDate;
                                if (!string.IsNullOrWhiteSpace(pl.Location)) existingLine.Location = pl.Location;
                            }
                            else
                            {
                                existingHeader.Lines.Add(new StagingSalesInvoiceLine
                                {
                                    InvoiceId = payload.CreditNoteId,
                                    LineNo = pl.LineNo,
                                    Sku = pl.Sku ?? pl.StandaloneSku,
                                    Name = pl.Name ?? pl.StandaloneName,
                                    Quantity = pl.Quantity,
                                    BasePrice = pl.BasePrice ?? pl.StandalonePrice ?? 0.0,
                                    DiscountAmount = pl.DiscountAmount ?? 0.0,
                                    Discount2 = pl.Discount2 ?? 0.0,
                                    Discount3 = pl.Discount3 ?? 0.0,
                                    TaxRule = pl.TaxRule ?? pl.StandaloneTaxRule ?? "VAT0",
                                    SalesUnit = pl.SalesUnit ?? pl.StandaloneSalesUnit ?? "UN",
                                    Warehouse = pl.Warehouse ?? pl.StandaloneWarehouse ?? "",
                                    LotNumber = pl.LotNumber ?? pl.StandaloneLot ?? "",
                                    Cce0 = pl.Cce0 ?? pl.StandaloneCce0 ?? "COMMERCIAL",
                                    OriginLineNo = pl.OriginLineNo,
                                    StockStatus = !string.IsNullOrWhiteSpace(pl.StockStatus) ? pl.StockStatus.Trim().ToUpperInvariant() : "A",
                                    ReturnCondition = pl.ReturnCondition,
                                    ExpiryDate = pl.ExpiryDate,
                                    Location = pl.Location
                                });
                            }
                        }
                    }
                    await _dbContext.SaveChangesAsync();
                }

                // Always assign [NotMapped] TabletSource even when retrying an existing staging header
                existingHeader.TabletSource = resolvedCrnTabletSource;

                string? x3DocId = recoveredX3DocId;
                string? x3ReqNum = null;
                string? x3RawPayload = recoveredRawPayload;
                X3ImportResult? importResult = null;

                // 2. Invoke Sage X3 SOAP if not already recovered
                if (string.IsNullOrEmpty(x3DocId))
                {
                    importResult = await _soapService.ImportCreditNoteAsync(existingHeader);

                    bool isSuccess = importResult.Success ||
                        (!string.IsNullOrEmpty(importResult.RawPayload) && importResult.RawPayload.Contains("Creation of ", StringComparison.OrdinalIgnoreCase));

                    if (!isSuccess)
                    {
                        await transaction.RollbackAsync();
                        string errorMsg = !string.IsNullOrWhiteSpace(importResult.TechnicalError)
                            ? importResult.TechnicalError
                            : string.Join(" | ", importResult.Messages);

                        return BadRequest(new
                        {
                            success = false,
                            creditNoteId = payload.CreditNoteId,
                            error = errorMsg,
                            rawPayload = importResult.RawPayload,
                            messages = importResult.Messages != null && importResult.Messages.Count > 0 ? importResult.Messages : new List<string> { errorMsg }
                        });
                    }

                    x3DocId = importResult.DocumentId;
                    x3ReqNum = importResult.RequestNumber;
                    x3RawPayload = importResult.RawPayload;
                }

                existingHeader.IsProcessedByX3 = true;
                if (!string.IsNullOrEmpty(x3DocId))
                {
                    existingHeader.X3DocumentId = x3DocId;
                }
                await _dbContext.SaveChangesAsync();

                // 3. Commit credit note transaction IMMEDIATELY so confirmed credit note is saved in HIPO
                await transaction.CommitAsync();

                // Update HepFiscalInvoices X3 sync status for troubleshooting tracking
                try
                {
                    var fiscalRow = await _dbContext.HepFiscalInvoices
                        .FirstOrDefaultAsync(f => f.DocumentNo == payload.CreditNoteId);
                    if (fiscalRow != null)
                    {
                        fiscalRow.X3Synced = true;
                        if (!string.IsNullOrWhiteSpace(x3DocId)) fiscalRow.X3DocumentId = x3DocId;
                        fiscalRow.X3SyncedAt = DateTime.UtcNow;
                        await _dbContext.SaveChangesAsync();
                    }
                }
                catch (Exception fEx)
                {
                    _logger.LogWarning(fEx, "Failed updating HepFiscalInvoices X3Synced for {CreditNoteId}", payload.CreditNoteId);
                }

                // 4. Decoupled Refund Phase: If Credit Note has Cash or Cheque refunds, disburse via ZPAYWEBA (REM, Sign 1, SCRN)
                bool refundSynced = false;
                string? x3RefundPaymentId = null;
                string? refundError = null;

                if (payload.Refunds != null && payload.Refunds.Count > 0 &&
                    (string.Equals(payload.SettlementType, "CASH", StringComparison.OrdinalIgnoreCase) ||
                     string.Equals(payload.SettlementType, "CHEQUE", StringComparison.OrdinalIgnoreCase)))
                {
                    var stagingRefundPayments = payload.Refunds.Select(r => new StagingSalesInvoicePayment
                    {
                        DocumentType = "CREDIT_NOTE",
                        DocumentId = payload.CreditNoteId,
                        X3DocumentType = "SCRN",
                        X3EntryType = "REM",
                        X3Sign = 1,
                        X3InvoiceDocumentId = existingHeader.X3DocumentId,
                        SalesSite = existingHeader.SalesSite ?? (!string.IsNullOrWhiteSpace(userSiteCode) && userSiteCode != "ALL" ? userSiteCode : "POD"),
                        CustomerCode = existingHeader.CustomerCode ?? "",
                        CustomerName = existingHeader.CustomerName,
                        PaymentMethod = r.Method,
                        Amount = (decimal)r.Amount,
                        BankCode = r.BankCode,
                        BankName = r.BankName,
                        ChequeNumber = r.ChequeNumber,
                        ChequeDate = r.ChequeDate,
                        LocalPaymentId = r.LocalRefundId,
                        CreatedAt = payload.CreatedAt,
                        CreatedBy = existingHeader.CreatedBy,
                        UserName = existingHeader.UserName,
                        DeviceId = existingHeader.DeviceId,
                        IsProcessedByX3 = false,
                        IsSynced = 0,
                        SyncedAt = DateTime.UtcNow
                    }).ToList();

                    // Refund SOAP trigger temporarily deactivated per business requirement.
                    // Refunds are persisted to MSSQL staging tables with IsProcessedByX3 = false, IsSynced = 0.
                    try
                    {
                        _dbContext.StagingSalesInvoicePayments.AddRange(stagingRefundPayments);
                        await _dbContext.SaveChangesAsync();
                        refundSynced = true;
                    }
                    catch (Exception refDbEx)
                    {
                        _logger.LogError(refDbEx, "Failed to persist StagingSalesInvoicePayments for Credit Note {CreditNoteId}: {Message}", payload.CreditNoteId, refDbEx.InnerException?.Message ?? refDbEx.Message);
                    }
                }

                // 5. Stock Reinstatement Phase: If this is a Customer Return, physically import stock via ZSMRWEBA (SOAP 3)
                bool stockReceiptSynced = false;
                string? x3StockReceiptId = null;
                string? stockReceiptError = null;
                var stockReceiptMessages = new List<string>();

                bool isCustomerReturn = payload.Category == 3
                    || payload.StockTransaction == 1
                    || string.Equals(payload.CreditNoteType, "RETURN", StringComparison.OrdinalIgnoreCase)
                    || string.Equals(existingHeader.InvoiceType, "3", StringComparison.OrdinalIgnoreCase);

                if (isCustomerReturn && existingHeader.Lines.Any(l => l.Quantity > 0))
                {
                    try
                    {
                        var miscResult = await _soapService.ImportMiscReceiptAsync(existingHeader, existingHeader.Lines.ToList());
                        if (miscResult.Success || (!string.IsNullOrEmpty(miscResult.RawPayload) && miscResult.RawPayload.Contains("Creation of ", StringComparison.OrdinalIgnoreCase)))
                        {
                            stockReceiptSynced = true;
                            x3StockReceiptId = !string.IsNullOrWhiteSpace(miscResult.DocumentId)
                                ? miscResult.DocumentId
                                : (!string.IsNullOrWhiteSpace(miscResult.RequestNumber) ? $"REQ-{miscResult.RequestNumber}" : "ZSMRWEBA-OK");
                            existingHeader.X3StockReceiptId = x3StockReceiptId;
                            await _dbContext.SaveChangesAsync();

                            stockReceiptMessages.Add($"Misc Stock Receipt (ZSMRWEBA) created in Sage X3: {x3StockReceiptId}");
                            if (miscResult.Messages != null && miscResult.Messages.Count > 0)
                            {
                                stockReceiptMessages.AddRange(miscResult.Messages);
                            }
                        }
                        else
                        {
                            stockReceiptError = !string.IsNullOrWhiteSpace(miscResult.TechnicalError)
                                ? miscResult.TechnicalError
                                : string.Join(" | ", miscResult.Messages);
                            if (string.IsNullOrWhiteSpace(stockReceiptError))
                            {
                                stockReceiptError = "Sage X3 ZSMRWEBA import returned unsuccessful status.";
                            }
                            stockReceiptMessages.Add($"Misc Stock Receipt (ZSMRWEBA) failed: {stockReceiptError}");
                            _logger.LogWarning("ZSMRWEBA Stock Receipt returned notice for {CreditNoteId}: {Error}", payload.CreditNoteId, stockReceiptError);
                        }
                    }
                    catch (Exception smrEx)
                    {
                        stockReceiptError = smrEx.Message;
                        stockReceiptMessages.Add($"Misc Stock Receipt (ZSMRWEBA) error: {stockReceiptError}");
                        _logger.LogError(smrEx, "Exception during ZSMRWEBA Miscellaneous Stock Receipt for {CreditNoteId}: {Error}", payload.CreditNoteId, smrEx.Message);
                    }
                }

                var syncSite = !string.IsNullOrWhiteSpace(userSiteCode) && userSiteCode != "ALL" 
                    ? userSiteCode 
                    : (!string.IsNullOrWhiteSpace(payload.SalesSite) ? payload.SalesSite : "IPL");
                var syncUser = User.Claims.FirstOrDefault(c => c.Type == "username")?.Value ?? User.Identity?.Name ?? payload.UserName ?? "sales-user";
                var syncDevId = !string.IsNullOrWhiteSpace(payload.DeviceId) ? payload.DeviceId : syncUser;
                try
                {
                    _dbContext.AuditLogs.Add(new AuditLog
                    {
                        EntityName = "DeviceSync",
                        EntityIdString = syncDevId,
                        ActionType = "SYNC_CREDIT_NOTE",
                        Site = syncSite,
                        Payload = $"{{\"CreditNoteId\":\"{payload.CreditNoteId}\",\"X3DocId\":\"{x3DocId}\",\"X3StockReceiptId\":\"{x3StockReceiptId}\"}}",
                        PerformedBy = syncUser,
                        PerformedAt = DateTime.UtcNow,
                        DeviceId = syncDevId
                    });
                    await _dbContext.SaveChangesAsync();
                }
                catch (Exception auditEx)
                {
                    _logger.LogWarning("Failed to write DeviceSync audit for Credit Note {CreditNoteId}: {Msg}", payload.CreditNoteId, auditEx.Message);
                }

                var combinedMessages = new List<string> { $"Created in Sage X3: {x3DocId}" };
                if (importResult?.Messages != null && importResult.Messages.Count > 0)
                {
                    combinedMessages.AddRange(importResult.Messages);
                }
                if (stockReceiptMessages.Count > 0)
                {
                    combinedMessages.AddRange(stockReceiptMessages);
                }

                return Ok(new
                {
                    success = true,
                    creditNoteId = payload.CreditNoteId,
                    x3Request = x3ReqNum,
                    x3DocumentId = x3DocId,
                    rawPayload = x3RawPayload,
                    messages = combinedMessages,
                    refundSynced,
                    x3RefundPaymentId,
                    refundError,
                    stockReceiptSynced,
                    x3StockReceiptId,
                    stockReceiptError,
                    stockReceiptMessages
                });
            }
            catch (Exception ex)
            {
                try { await transaction.RollbackAsync(); } catch { }
                var detailedError = ex.InnerException != null ? $"{ex.Message} --> {ex.InnerException.Message}" : ex.Message;
                _logger.LogError(ex, "Failed to sync credit note {CreditNoteId}: {Error}", payload.CreditNoteId, detailedError);
                return StatusCode(500, new { success = false, creditNoteId = payload.CreditNoteId, error = detailedError });
            }
            }
            catch (Exception outerEx)
            {
                var detailedError = outerEx.InnerException != null ? $"{outerEx.Message} --> {outerEx.InnerException.Message}" : outerEx.Message;
                _logger.LogError(outerEx, "Outer error syncing credit note {CreditNoteId}: {Error}", payload.CreditNoteId, detailedError);
                return StatusCode(500, new { success = false, creditNoteId = payload.CreditNoteId, error = detailedError });
            }
        }

        [HttpPost("sync-payments")]
        public async Task<IActionResult> SyncPayments([FromBody] List<SalesInvoicePaymentSyncDto> payload)
        {
            if (payload == null || payload.Count == 0)
                return BadRequest(new { success = false, error = "Empty payment payload." });

            var userSiteCode = User.FindFirst("SiteCode")?.Value;
            var userName = User.Identity?.Name ?? "system";
            var deviceId = User.FindFirst("DeviceId")?.Value;

            var results = new List<object>();

            var groups = payload.GroupBy(p => new { p.DocumentType, p.DocumentId, p.X3InvoiceDocumentId });

            foreach (var grp in groups)
            {
                var docType = string.IsNullOrWhiteSpace(grp.Key.DocumentType) ? "INVOICE" : grp.Key.DocumentType.ToUpper();
                var isInvoice = docType == "INVOICE";
                var x3DocId = grp.Key.X3InvoiceDocumentId;

                if (string.IsNullOrWhiteSpace(x3DocId) && !string.IsNullOrWhiteSpace(grp.Key.DocumentId))
                {
                    var header = await _dbContext.StagingSalesInvoiceHeaders
                        .AsNoTracking()
                        .FirstOrDefaultAsync(h => h.InvoiceId == grp.Key.DocumentId && h.IsProcessedByX3 && !string.IsNullOrEmpty(h.X3DocumentId));
                    x3DocId = header?.X3DocumentId;
                }

                if (string.IsNullOrWhiteSpace(x3DocId))
                {
                    results.Add(new
                    {
                        documentId = grp.Key.DocumentId,
                        success = false,
                        error = "Cannot sync payment: Parent Sage X3 document number is missing or unverified."
                    });
                    continue;
                }

                var stagingPayments = grp.Select(p => new StagingSalesInvoicePayment
                {
                    DocumentType = docType,
                    DocumentId = grp.Key.DocumentId ?? x3DocId,
                    X3DocumentType = isInvoice ? "SINV" : "SCRN",
                    X3EntryType = isInvoice ? "REC" : "REM",
                    X3Sign = (short)(isInvoice ? 2 : 1),
                    X3InvoiceDocumentId = x3DocId,
                    SalesSite = !string.IsNullOrWhiteSpace(userSiteCode) && userSiteCode != "ALL"
                        ? userSiteCode
                        : (!string.IsNullOrWhiteSpace(p.SalesSite) ? p.SalesSite : "POD"),
                    CustomerCode = p.CustomerCode ?? "",
                    CustomerName = p.CustomerName,
                    PaymentMethod = p.Method,
                    Amount = p.Amount,
                    BankCode = string.Equals(p.Method, "CREDIT", StringComparison.OrdinalIgnoreCase) ? null : p.BankCode,
                    BankName = string.Equals(p.Method, "CREDIT", StringComparison.OrdinalIgnoreCase) ? null : p.BankName,
                    ChequeNumber = p.ChequeNumber,
                    ChequeDate = p.ChequeDate,
                    QrTransactionRef = p.QrTransactionRef,
                    LocalPaymentId = p.LocalPaymentId,
                    CreatedAt = DateTime.UtcNow.ToString("yyyyMMdd"),
                    CreatedBy = userName,
                    UserName = userName,
                    DeviceId = deviceId,
                    IsProcessedByX3 = false,
                    IsSynced = 0,
                    SyncedAt = DateTime.UtcNow
                }).ToList();

                try
                {
                    // Payment SOAP trigger temporarily deactivated per business requirement.
                    // Payments are persisted to MSSQL staging tables with IsProcessedByX3 = false, IsSynced = 0.
                    _dbContext.StagingSalesInvoicePayments.AddRange(stagingPayments);
                    await _dbContext.SaveChangesAsync();

                    results.Add(new
                    {
                        documentId = grp.Key.DocumentId,
                        x3InvoiceDocumentId = x3DocId,
                        success = true,
                        message = "Payment staged locally (SOAP trigger temporarily deactivated)."
                    });
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Error syncing standalone payments for document {DocumentId}", grp.Key.DocumentId);
                    results.Add(new
                    {
                        documentId = grp.Key.DocumentId,
                        x3InvoiceDocumentId = x3DocId,
                        success = false,
                        error = ex.Message
                    });
                }
            }

            return Ok(new { success = true, results });
        }

        [HttpGet("customers")]
        public async Task<IActionResult> GetCustomers([FromQuery] string? sitecode = null)
        {
            var (siteCtx, error) = await _siteResolver.ResolveSiteContextAsync(User, sitecode, allowAll: true);
            if (error != null)
            {
                return error;
            }

            try
            {
                if (_snapshotService != null)
                {
                    var snapshot = await _snapshotService.GetOrUpdateSnapshotAsync(
                        string.IsNullOrWhiteSpace(siteCtx!.FinancialSiteCode) ? "GLOBAL" : siteCtx.FinancialSiteCode,
                        "Customers",
                        () => _repository.GetCustomersWatermarkAsync(),
                        () => _repository.GetCustomersAsync(siteCtx.FinancialSiteCode, bypassCache: true));

                    return ServeSnapshotResult(snapshot);
                }

                var customers = await _repository.GetCustomersAsync(siteCtx!.FinancialSiteCode);
                return Ok(customers);
            }
            catch (System.Exception)
            {
                return StatusCode(500, new { error = "An internal error occurred while retrieving customer records." });
            }
        }

        [HttpGet("Products")]
        public async Task<IActionResult> GetProducts([FromQuery] string? sitecode = null)
        {
            var (siteCtx, error) = await _siteResolver.ResolveSiteContextAsync(User, sitecode);
            if (error != null)
            {
                return error;
            }

            try
            {
                var targetSite = siteCtx!.ShippingSiteCode;
                var lorryScope = await ResolveCallerLorryScopeAsync(targetSite);
                if (lorryScope.HasDeviceContext)
                {
                    if (string.IsNullOrEmpty(lorryScope.AssignedLorry))
                    {
                        Response.Headers["X-Lorry-Required"] = "true";
                        return Ok(Array.Empty<SalesInvoiceProductDto>());
                    }

                    Response.Headers["X-Assigned-Lorry"] = lorryScope.AssignedLorry;
                    var lorryProducts = await _repository.GetProductsAsync(targetSite, lorryScope.AssignedLorry);
                    return Ok(lorryProducts);
                }

                var products = await _repository.GetProductsAsync(targetSite);
                return Ok(products);
            }
            catch (System.Exception)
            {
                return StatusCode(500, new { error = "An internal error occurred while retrieving products." });
            }
        }

        [HttpGet("itemstockdetails")]
        public async Task<IActionResult> GetItemStockDetails([FromQuery] string? sitecode = null)
        {
            var (siteCtx, error) = await _siteResolver.ResolveSiteContextAsync(User, sitecode);
            if (error != null)
            {
                return error;
            }

            var targetSite = siteCtx!.ShippingSiteCode;
            try
            {
                var lorryScope = await ResolveCallerLorryScopeAsync(targetSite);
                if (lorryScope.HasDeviceContext && string.IsNullOrEmpty(lorryScope.AssignedLorry))
                {
                    Response.Headers["X-Lorry-Required"] = "true";
                    return Ok(Array.Empty<SalesInvoiceItemStockDto>());
                }

                if (_snapshotService != null)
                {
                    var schemaName = ResolveSchemaName();
                    var snapshot = await _snapshotService.GetOrUpdateSnapshotAsync(
                        targetSite,
                        $"StockDetails_{schemaName}",
                        () => _repository.GetStockWatermarkAsync(targetSite),
                        () => _repository.GetItemStockDetailsAsync(targetSite));

                    if (!lorryScope.HasDeviceContext)
                    {
                        return ServeSnapshotResult(snapshot);
                    }

                    Response.Headers["X-Assigned-Lorry"] = lorryScope.AssignedLorry!;
                    if (!string.IsNullOrEmpty(lorryScope.AssignedWarehouse))
                    {
                        Response.Headers["X-Assigned-Warehouse"] = lorryScope.AssignedWarehouse;
                    }

                    var baseEtag = snapshot.ETag.Trim('"');
                    var lorryEtag = $"\"{baseEtag}_{schemaName}_{lorryScope.AssignedLorry!.ToUpperInvariant()}\"";
                    var requestETag = Request.Headers.IfNoneMatch.ToString();
                    if (!string.IsNullOrEmpty(requestETag) && requestETag.Equals(lorryEtag, StringComparison.OrdinalIgnoreCase))
                    {
                        return StatusCode(304);
                    }

                    List<SalesInvoiceItemStockDto>? allItems;
                    await using (var fs = new FileStream(snapshot.FilePath, FileMode.Open, FileAccess.Read, FileShare.Read, 65536, useAsync: true))
                    await using (var gzip = new GZipStream(fs, CompressionMode.Decompress))
                    {
                        allItems = await JsonSerializer.DeserializeAsync<List<SalesInvoiceItemStockDto>>(gzip, new JsonSerializerOptions
                        {
                            PropertyNameCaseInsensitive = true
                        });
                    }

                    var filtered = (allItems ?? new List<SalesInvoiceItemStockDto>())
                        .Where(d => MatchesLorryScope(d, lorryScope, targetSite))
                        .ToList();

                    Response.Headers.ETag = lorryEtag;
                    Response.Headers.LastModified = snapshot.LastModifiedUtc.ToString("R");
                    return Ok(filtered);
                }

                var details = await _repository.GetItemStockDetailsAsync(targetSite);
                if (lorryScope.HasDeviceContext)
                {
                    Response.Headers["X-Assigned-Lorry"] = lorryScope.AssignedLorry!;
                    if (!string.IsNullOrEmpty(lorryScope.AssignedWarehouse))
                    {
                        Response.Headers["X-Assigned-Warehouse"] = lorryScope.AssignedWarehouse;
                    }
                    details = details.Where(d => MatchesLorryScope(d, lorryScope, targetSite)).ToList();
                }

                return Ok(details);
            }
            catch (System.Exception ex)
            {
                _logger.LogError(ex, "Error retrieving stock details for site {Site}", targetSite);
                return StatusCode(500, new { error = "An internal error occurred while retrieving stock details." });
            }
        }

        [HttpGet("tax-determinations")]
        public async Task<IActionResult> GetTaxDeterminations()
        {
            try
            {
                var data = await _repository.GetTaxDeterminationsAsync();
                return Ok(data);
            }
            catch (System.Exception)
            {
                return StatusCode(500, new { error = "An internal error occurred while retrieving tax determinations." });
            }
        }

        [HttpGet("tax-rates")]
        public async Task<IActionResult> GetTaxRates()
        {
            try
            {
                var data = await _repository.GetTaxRatesAsync();
                return Ok(data);
            }
            catch (System.Exception)
            {
                return StatusCode(500, new { error = "An internal error occurred while retrieving tax rates." });
            }
        }

        [HttpGet("price-lists")]
        public async Task<IActionResult> GetPriceLists()
        {
            try
            {
                if (_snapshotService != null)
                {
                    var snapshot = await _snapshotService.GetOrUpdateSnapshotAsync(
                        "GLOBAL",
                        "PriceLists",
                        () => _repository.GetPriceListsWatermarkAsync(),
                        () => _repository.GetPriceListsAsync());

                    return ServeSnapshotResult(snapshot);
                }

                var data = await _repository.GetPriceListsAsync();
                return Ok(data);
            }
            catch (System.Exception ex)
            {
                _logger.LogError(ex, "Error retrieving price lists");
                return StatusCode(500, new { error = "An internal error occurred while retrieving price lists." });
            }
        }

        [HttpGet("customer/{customerNo}/live-credit")]
        public async Task<IActionResult> GetCustomerLiveCredit(string customerNo)
        {
            if (string.IsNullOrWhiteSpace(customerNo))
            {
                return BadRequest(new { error = "Customer number is required." });
            }

            try
            {
                var liveCredit = await _repository.GetCustomerLiveCreditAsync(customerNo);
                if (liveCredit == null)
                {
                    return NotFound(new { error = $"Customer '{customerNo}' not found." });
                }

                return Ok(liveCredit);
            }
            catch (System.Exception ex)
            {
                _logger.LogError(ex, "Error retrieving live credit for customer {CustomerNo}", customerNo);
                return StatusCode(500, new { error = "An internal error occurred while retrieving live credit." });
            }
        }

        [HttpGet("customer/{customerNo}")]
        public async Task<IActionResult> GetCustomerByCode(string customerNo)
        {
            if (string.IsNullOrWhiteSpace(customerNo))
            {
                return BadRequest(new { error = "Customer number is required." });
            }

            try
            {
                var customer = await _repository.GetCustomerByCodeAsync(customerNo);
                if (customer == null)
                {
                    return NotFound(new { error = $"Customer '{customerNo}' not found." });
                }

                return Ok(customer);
            }
            catch (System.Exception ex)
            {
                _logger.LogError(ex, "Error retrieving customer {CustomerNo}", customerNo);
                return StatusCode(500, new { error = "An internal error occurred while retrieving customer." });
            }
        }

        [HttpGet("product/{productCode}/live-stock")]
        public async Task<IActionResult> GetProductLiveStock(string productCode, [FromQuery] string? sitecode = null)
        {
            if (string.IsNullOrWhiteSpace(productCode))
            {
                return BadRequest(new { error = "Product code is required." });
            }

            var (siteCtx, error) = await _siteResolver.ResolveSiteContextAsync(User, sitecode);
            if (error != null)
            {
                return error;
            }

            try
            {
                var targetSite = siteCtx!.ShippingSiteCode;
                var lorryScope = await ResolveCallerLorryScopeAsync(targetSite);
                if (lorryScope.HasDeviceContext)
                {
                    if (string.IsNullOrEmpty(lorryScope.AssignedLorry))
                    {
                        Response.Headers["X-Lorry-Required"] = "true";
                        return Ok(new ProductLiveStockDto
                        {
                            ProductCode = productCode,
                            SiteCode = targetSite,
                            PhysicalStock = 0,
                            AllocatedStock = 0,
                            LiveAvailableStock = 0
                        });
                    }

                    Response.Headers["X-Assigned-Lorry"] = lorryScope.AssignedLorry;
                    var lorryLiveStock = await _repository.GetProductLiveStockAsync(productCode, targetSite, lorryScope.AssignedLorry);
                    return Ok(lorryLiveStock);
                }

                var liveStock = await _repository.GetProductLiveStockAsync(productCode, targetSite);
                return Ok(liveStock);
            }
            catch (System.Exception ex)
            {
                _logger.LogError(ex, "Error retrieving live stock for product {ProductCode} at site {Site}", productCode, siteCtx!.ShippingSiteCode);
                return StatusCode(500, new { error = "An internal error occurred while retrieving live stock." });
            }
        }

        [HttpGet("salesreps")]
        public async Task<IActionResult> GetSalesReps([FromQuery] string? sitecode = null)
        {
            var (siteCtx, error) = await _siteResolver.ResolveSiteContextAsync(User, sitecode, allowAll: true);
            if (error != null) return error;

            try
            {
                var target = string.IsNullOrWhiteSpace(siteCtx!.FinancialSiteCode) ? null : siteCtx.FinancialSiteCode;
                var data = await _repository.GetSalesRepsAsync(target);
                return Ok(data);
            }
            catch (System.Exception)
            {
                return StatusCode(500, new { error = "An internal error occurred while retrieving sales representatives." });
            }
        }

        [HttpGet("open-invoices")]
        public async Task<IActionResult> GetOpenInvoices(
            [FromQuery] string? sitecode = null, 
            [FromQuery] string? customerno = null,
            [FromQuery] int daysCutoff = 0)
        {
            var (siteCtx, errorResult) = await _siteResolver.ResolveSiteContextAsync(User, sitecode);
            if (errorResult != null) return errorResult;

            var targetSite = siteCtx!.FinancialSiteCode;

            try
            {
                if (_snapshotService != null && string.IsNullOrWhiteSpace(customerno) && daysCutoff <= 0)
                {
                    var snapshot = await _snapshotService.GetOrUpdateSnapshotAsync(
                        targetSite,
                        "OpenInvoices",
                        () => _repository.GetOpenInvoicesWatermarkAsync(targetSite, daysCutoff),
                        () => _repository.GetOpenInvoicesAsync(targetSite, customerno, daysCutoff));

                    return ServeSnapshotResult(snapshot);
                }

                var data = await _repository.GetOpenInvoicesAsync(targetSite, customerno, daysCutoff);
                return Ok(data);
            }
            catch (System.Exception ex)
            {
                _logger.LogError(ex, "Error retrieving open invoices for site {Site}", targetSite);
                return StatusCode(500, new { error = "An internal error occurred while retrieving open invoices." });
            }
        }

        [HttpGet("x3-history")]
        public async Task<IActionResult> GetX3History(
            [FromQuery] string? sitecode = null,
            [FromQuery] string? customercode = null,
            [FromQuery] int months = 6)
        {
            var (siteCtx, errorResult) = await _siteResolver.ResolveSiteContextAsync(User, sitecode);
            if (errorResult != null) return errorResult;

            var targetSite = siteCtx!.FinancialSiteCode;

            try
            {
                if (_snapshotService != null && string.IsNullOrWhiteSpace(customercode) && months == 6)
                {
                    var snapshot = await _snapshotService.GetOrUpdateSnapshotAsync(
                        targetSite,
                        "X3History",
                        () => _repository.GetX3HistoryWatermarkAsync(targetSite),
                        () => _repository.GetX3HistoryAsync(targetSite, customercode, months));

                    return ServeSnapshotResult(snapshot);
                }

                var data = await _repository.GetX3HistoryAsync(targetSite, customercode, months);
                return Ok(data);
            }
            catch (System.Exception ex)
            {
                _logger.LogError(ex, "Error retrieving X3 history for site {Site}, customer {Customer}", targetSite, customercode);
                return StatusCode(500, new { error = "An internal error occurred while retrieving X3 history." });
            }
        }

        [HttpGet("credit-note-reasons")]
        public async Task<IActionResult> GetCreditNoteReasons()
        {
            try
            {
                var data = await _repository.GetCreditNoteReasonsAsync();
                return Ok(data);
            }
            catch (System.Exception ex)
            {
                _logger.LogError(ex, "Error retrieving Sage X3 credit note reasons (Table 8)");
                return StatusCode(500, new { error = "An internal error occurred while retrieving credit note reasons." });
            }
        }

        [HttpGet("banks")]
        public async Task<IActionResult> GetBanks()
        {
            try
            {
                var data = await _repository.GetBanksAsync();
                return Ok(data);
            }
            catch (System.Exception ex)
            {
                _logger.LogError(ex, "Error retrieving Sage X3 banks");
                return StatusCode(500, new { error = "An internal error occurred while retrieving banks." });
            }
        }

        [HttpGet("facilities")]
        public async Task<IActionResult> GetFacilities()
        {
            try
            {
                var data = await _repository.GetFacilitiesAsync();
                return Ok(data);
            }
            catch (System.Exception ex)
            {
                _logger.LogError(ex, "Error retrieving Sage X3 facilities");
                return StatusCode(500, new { error = "An internal error occurred while retrieving facilities." });
            }
        }

        [HttpPost("open-invoices/payments/sync")]
        public async Task<IActionResult> SyncOpenInvoicePayments([FromBody] List<OpenInvoicePaymentSyncDto> payments)
        {
            if (payments == null || payments.Count == 0)
                return Ok(new { success = true, syncedCount = 0 });

            try
            {
                var (siteCtx, _) = await _siteResolver.ResolveSiteContextAsync(User, null, allowAll: true);
                var resolvedSite = siteCtx != null && !string.IsNullOrWhiteSpace(siteCtx.FinancialSiteCode)
                    ? siteCtx.FinancialSiteCode
                    : "POD";
                var userName = User.Identity?.Name ?? "MobileUser";

                foreach (var payment in payments)
                {
                    if (string.IsNullOrWhiteSpace(payment.SiteCode) || payment.SiteCode == "ALL")
                    {
                        payment.SiteCode = resolvedSite;
                    }
                    payment.UserName = userName;
                }

                _logger.LogInformation("Received {Count} open invoice payment allocations for synchronization from user {User}.", payments.Count, userName);
                return Ok(new { success = true, syncedCount = payments.Count, paymentIds = payments.Select(p => p.PaymentId).ToList() });
            }
            catch (System.Exception ex)
            {
                _logger.LogError(ex, "Error synchronizing open invoice payments");
                return StatusCode(500, new { error = "An internal error occurred while synchronizing open invoice payments." });
            }
        }

        [HttpGet("sync-responses/latest")]
        public async Task<IActionResult> GetLatestSyncResponses([FromQuery] string? siteCode = null, [FromQuery] int limit = 20)
        {
            try
            {
                var query = _dbContext.X3SoapAudits.AsNoTracking();
                var audits = await query
                    .OrderByDescending(a => a.CreatedAt)
                    .Take(Math.Min(limit, 50))
                    .ToListAsync();

                var results = audits.Select(a => {
                    string? docId = null;
                    if (!string.IsNullOrEmpty(a.ResponsePayload) && a.ResponsePayload.Contains("Creation of "))
                    {
                        var idx = a.ResponsePayload.IndexOf("Creation of ");
                        var sub = a.ResponsePayload.Substring(idx + "Creation of ".Length);
                        var parts = sub.Split(new[] { '<', '"', '\r', '\n', ' ' }, StringSplitOptions.RemoveEmptyEntries);
                        docId = parts.FirstOrDefault()?.Trim();
                    }

                    var msgs = new List<string>();
                    if (!string.IsNullOrWhiteSpace(a.ErrorMessage))
                    {
                        msgs.Add(a.ErrorMessage);
                    }
                    if (docId != null)
                    {
                        msgs.Add($"Sage X3 Document: {docId}");
                    }
                    else if (a.IsSuccess)
                    {
                        msgs.Add($"Imported in Sage X3 ({a.ActionName})");
                    }

                    return new
                    {
                        id = a.Id,
                        actionName = a.ActionName,
                        identifier = a.Identifier,
                        isSuccess = a.IsSuccess,
                        errorMessage = a.ErrorMessage,
                        documentId = docId,
                        triggeredBy = a.TriggeredBy,
                        deviceId = a.DeviceId,
                        createdAt = a.CreatedAt,
                        messages = msgs
                    };
                }).ToList();

                return Ok(results);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to retrieve latest sync responses");
                return StatusCode(500, new { error = "Failed to retrieve sync responses." });
            }
        }

        [HttpGet("document-sequences")]
        public async Task<IActionResult> GetDocumentSequences([FromQuery] string? siteCode = null)
        {
            try
            {
                var (siteCtx, _) = await _siteResolver.ResolveSiteContextAsync(User, siteCode, allowAll: true);
                var cleanSite = siteCtx?.FinancialSiteCode ?? siteCode?.Trim().ToUpperInvariant() ?? "";

                // Query all HIPO invoice, credit note, and return IDs from BOTH HIPO Staging AND Sage X3 (SINVOICE + SMVTH)
                // so that even after a backend crash or staging DB reset, sequence high-water marks never reset.
                var query = _dbContext.StagingSalesInvoiceHeaders.AsNoTracking();
                if (!string.IsNullOrWhiteSpace(cleanSite) && cleanSite != "ALL")
                {
                    query = query.Where(h => h.SalesSite == cleanSite || h.InvoiceId.Contains(cleanSite));
                }

                var stagingIds = await query
                    .Select(h => h.InvoiceId)
                    .ToListAsync();

                var x3Ids = await _repository.GetExistingHipoDocumentIdsFromX3Async(cleanSite);
                var candidateIds = stagingIds
                    .Concat(x3Ids)
                    .Where(id => !string.IsNullOrWhiteSpace(id))
                    .Distinct(StringComparer.OrdinalIgnoreCase)
                    .ToList();

                var prefixes = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
                foreach (var id in candidateIds)
                {
                    if (string.IsNullOrWhiteSpace(id) || id.Length < 12 || !id.StartsWith("H", StringComparison.OrdinalIgnoreCase))
                        continue;

                    string prefix = id.Substring(0, id.Length - 5);
                    string seqStr = id.Substring(id.Length - 5);
                    if (int.TryParse(seqStr, out int seqNum))
                    {
                        if (!prefixes.TryGetValue(prefix, out int currMax) || seqNum > currMax)
                        {
                            prefixes[prefix] = seqNum;
                        }
                    }
                }

                var result = prefixes.Select(p => {
                    string pfx = p.Key;
                    string typeCode = pfx.Length >= 2 ? (pfx[1] == 'C' ? "CRN" : (pfx[1] == 'R' ? "RTN" : "INV")) : "INV";
                    string ym = pfx.Length >= 4 ? pfx.Substring(pfx.Length - 4) : "";
                    string middle = pfx.Length > 6 ? pfx.Substring(2, pfx.Length - 6) : "";

                    string finSite = middle;
                    string lorry = "00";
                    var match = System.Text.RegularExpressions.Regex.Match(middle, @"^([A-Za-z]+)(\d+)$");
                    if (match.Success)
                    {
                        finSite = match.Groups[1].Value;
                        lorry = match.Groups[2].Value;
                    }

                    return new
                    {
                        prefix = pfx,
                        docType = typeCode,
                        financialSite = finSite,
                        lorryCode = lorry,
                        yearMonth = ym,
                        lastSequence = p.Value
                    };
                }).ToList();

                return Ok(result);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to retrieve document sequences high-water mark");
                return StatusCode(500, new { error = "Failed to retrieve document sequences." });
            }
        }

        private async Task<string> ResolveTabletSourceAsync(string? rawTabletSource, string? rawDeviceId, string? userName)
        {
            var headerDeviceId = Request.Headers.TryGetValue("X-Device-Id", out var hDev) ? hDev.ToString().Trim() : null;
            var claimDeviceId = User.FindFirst("DeviceId")?.Value?.Trim();
            var cleanTablet = (rawTabletSource ?? string.Empty).Trim();
            var cleanDeviceId = !string.IsNullOrWhiteSpace(rawDeviceId)
                ? rawDeviceId.Trim()
                : (!string.IsNullOrWhiteSpace(headerDeviceId) ? headerDeviceId : (claimDeviceId ?? string.Empty));
            var cleanUser = (userName ?? string.Empty).Trim();

            try
            {
                var activeDevices = await _dbContext.DeviceLocations
                    .AsNoTracking()
                    .Where(d => d.IsActive)
                    .ToListAsync();

                // 1. Exact DeviceId or X-Device-Id match
                if (!string.IsNullOrEmpty(cleanDeviceId))
                {
                    var byId = activeDevices.FirstOrDefault(d =>
                        string.Equals(d.DeviceId, cleanDeviceId, StringComparison.OrdinalIgnoreCase) ||
                        (!string.IsNullOrWhiteSpace(headerDeviceId) && string.Equals(d.DeviceId, headerDeviceId, StringComparison.OrdinalIgnoreCase)));
                    if (byId != null && !string.IsNullOrWhiteSpace(byId.DeviceName))
                    {
                        return byId.DeviceName.Trim().ToUpperInvariant();
                    }
                }

                // 2. Explicit HM* / registered DeviceName match
                if (!string.IsNullOrEmpty(cleanTablet))
                {
                    var byName = activeDevices.FirstOrDefault(d =>
                        string.Equals(d.DeviceName, cleanTablet, StringComparison.OrdinalIgnoreCase));
                    if (byName != null && !string.IsNullOrWhiteSpace(byName.DeviceName))
                    {
                        return byName.DeviceName.Trim().ToUpperInvariant();
                    }
                }

                // 3. HardwareModel match (e.g. "Infinix X6528 (Infinix X6528)")
                if (!string.IsNullOrEmpty(cleanDeviceId))
                {
                    var byHw = activeDevices.FirstOrDefault(d =>
                        !string.IsNullOrWhiteSpace(d.HardwareModel) &&
                        (string.Equals(d.HardwareModel.Trim(), cleanDeviceId, StringComparison.OrdinalIgnoreCase) ||
                         cleanDeviceId.Contains(d.HardwareModel.Trim(), StringComparison.OrdinalIgnoreCase) ||
                         d.HardwareModel.Contains(cleanDeviceId, StringComparison.OrdinalIgnoreCase)));
                    if (byHw != null && !string.IsNullOrWhiteSpace(byHw.DeviceName))
                    {
                        return byHw.DeviceName.Trim().ToUpperInvariant();
                    }
                }

                // 4. AssignedUserName match
                if (!string.IsNullOrEmpty(cleanUser))
                {
                    var byUser = activeDevices.FirstOrDefault(d =>
                        !string.IsNullOrWhiteSpace(d.AssignedUserName) &&
                        string.Equals(d.AssignedUserName.Trim(), cleanUser, StringComparison.OrdinalIgnoreCase));
                    if (byUser != null && !string.IsNullOrWhiteSpace(byUser.DeviceName))
                    {
                        return byUser.DeviceName.Trim().ToUpperInvariant();
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "ResolveTabletSourceAsync lookup warning; falling back to HM pattern check.");
            }

            if (!string.IsNullOrEmpty(cleanTablet) &&
                System.Text.RegularExpressions.Regex.IsMatch(cleanTablet, @"^HM\d+$", System.Text.RegularExpressions.RegexOptions.IgnoreCase))
            {
                return cleanTablet.ToUpperInvariant();
            }

            return "HM1";
        }

        private sealed record LorryScope(
            bool HasDeviceContext,
            string? AssignedLorry,
            string? AssignedWarehouse,
            string? SiteCode);

        private async Task<LorryScope> ResolveCallerLorryScopeAsync(string effectiveSiteCode, string? payloadDeviceId = null)
        {
            var headerDeviceId = Request?.Headers.TryGetValue("X-Device-Id", out var hDev) == true
                ? hDev.ToString().Trim()
                : null;
            var headerHardwareId = Request?.Headers.TryGetValue("X-Device-Hardware-Id", out var hHw) == true
                ? hHw.ToString().Trim()
                : null;
            var queryDeviceId = Request?.Query.TryGetValue("deviceId", out var qDev) == true
                ? qDev.ToString().Trim()
                : null;
            var claimDeviceId = User?.FindFirst("DeviceId")?.Value?.Trim();

            var requestedDeviceId = !string.IsNullOrWhiteSpace(headerDeviceId)
                ? headerDeviceId
                : (!string.IsNullOrWhiteSpace(payloadDeviceId)
                    ? payloadDeviceId.Trim()
                    : (!string.IsNullOrWhiteSpace(queryDeviceId) ? queryDeviceId : claimDeviceId));

            var cleanSite = (effectiveSiteCode ?? string.Empty).Trim().ToUpperInvariant();
            var username = User?.Claims.FirstOrDefault(c => c.Type == "username")?.Value
                           ?? User?.Identity?.Name
                           ?? string.Empty;
            var hasAnyDeviceHint = !string.IsNullOrWhiteSpace(requestedDeviceId) || !string.IsNullOrWhiteSpace(headerHardwareId);

            DeviceLocation? device = null;
            if (!string.IsNullOrWhiteSpace(requestedDeviceId))
            {
                var cleanDev = requestedDeviceId.Trim();
                device = await _dbContext.DeviceLocations.AsNoTracking().FirstOrDefaultAsync(d =>
                    d.IsActive &&
                    (d.DeviceId == cleanDev || d.DeviceName == cleanDev || d.HardwareIdentifier == cleanDev));
            }

            if (device == null && !string.IsNullOrWhiteSpace(headerHardwareId))
            {
                var cleanHw = headerHardwareId.Trim();
                device = await _dbContext.DeviceLocations.AsNoTracking()
                    .Where(d => d.IsActive && d.HardwareIdentifier == cleanHw)
                    .OrderByDescending(d => (cleanSite == string.Empty || cleanSite == "ALL" || d.SiteCode == cleanSite) ? 1 : 0)
                    .ThenByDescending(d => d.UpdatedAt)
                    .FirstOrDefaultAsync();
            }

            if (device == null && !string.IsNullOrWhiteSpace(requestedDeviceId))
            {
                var cleanModel = requestedDeviceId.Trim();
                device = await _dbContext.DeviceLocations.AsNoTracking()
                    .Where(d => d.IsActive &&
                                d.HardwareModel != null &&
                                d.HardwareModel == cleanModel &&
                                (cleanSite == string.Empty || cleanSite == "ALL" || d.SiteCode == cleanSite))
                    .OrderByDescending(d => d.UpdatedAt)
                    .FirstOrDefaultAsync();
            }

            if (device == null && !string.IsNullOrWhiteSpace(username))
            {
                var cleanUser = username.Trim();
                device = await _dbContext.DeviceLocations.AsNoTracking()
                    .Where(d => d.IsActive &&
                                d.AssignedUserName != null &&
                                d.AssignedUserName == cleanUser &&
                                (cleanSite == string.Empty || cleanSite == "ALL" || d.SiteCode == cleanSite))
                    .OrderByDescending(d => d.UpdatedAt)
                    .FirstOrDefaultAsync();
            }

            if (device == null)
            {
                return new LorryScope(hasAnyDeviceHint, null, null, cleanSite);
            }

            var devSite = (device.SiteCode ?? cleanSite).Trim().ToUpperInvariant();
            var loc = (device.LocationCode ?? string.Empty).Trim().ToUpperInvariant();
            var wrh = (device.WarehouseCode ?? string.Empty).Trim().ToUpperInvariant();

            bool hasConcreteLoc = !string.IsNullOrEmpty(loc) && loc != devSite && loc != "ALL";
            bool hasConcreteWrh = !string.IsNullOrEmpty(wrh) && wrh != devSite && wrh != "ALL";

            if (!hasConcreteLoc && !hasConcreteWrh)
            {
                return new LorryScope(true, null, null, devSite);
            }

            var assignedLorry = hasConcreteLoc ? loc : wrh;
            var assignedWrh = hasConcreteWrh ? wrh : assignedLorry;
            return new LorryScope(true, assignedLorry, assignedWrh, devSite);
        }

        private static bool MatchesLorryCode(string? value, LorryScope scope)
        {
            if (string.IsNullOrWhiteSpace(value) || string.IsNullOrEmpty(scope.AssignedLorry))
            {
                return false;
            }

            var clean = value.Trim().ToUpperInvariant();
            return string.Equals(clean, scope.AssignedLorry, StringComparison.OrdinalIgnoreCase)
                || (!string.IsNullOrEmpty(scope.AssignedWarehouse) &&
                    string.Equals(clean, scope.AssignedWarehouse, StringComparison.OrdinalIgnoreCase));
        }

        private static bool MatchesLorryScope(SalesInvoiceItemStockDto d, LorryScope scope, string targetSite)
        {
            if (!string.IsNullOrWhiteSpace(targetSite) &&
                !string.Equals(targetSite, "ALL", StringComparison.OrdinalIgnoreCase) &&
                !string.IsNullOrWhiteSpace(d.SiteCode) &&
                !string.Equals(d.SiteCode.Trim(), targetSite.Trim(), StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }

            return MatchesLorryCode(d.Location, scope) || MatchesLorryCode(d.Warehouse, scope);
        }

        private static bool IsLineAllowedForLorry(SalesInvoiceLineDto line, LorryScope scope)
        {
            if (!string.IsNullOrWhiteSpace(line.Location) && !MatchesLorryCode(line.Location, scope))
            {
                return false;
            }
            if (!string.IsNullOrWhiteSpace(line.Warehouse) && !MatchesLorryCode(line.Warehouse, scope))
            {
                return false;
            }
            return true;
        }
    }
}
