using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.Threading.Tasks;
using EnterpriseAuth.Api.Core.Application.Interfaces;
using EnterpriseAuth.Api.Infrastructure.Persistence;
using EnterpriseAuth.Api.Core.Domain.Entities;
using EnterpriseAuth.Api.Core.Application.DTOs;
using Microsoft.EntityFrameworkCore;
using System;
using Microsoft.Extensions.Logging;
using Microsoft.AspNetCore.Http;

namespace EnterpriseAuth.Api.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    [Authorize]
    public class SalesInvoiceController : ControllerBase
    {
        private readonly ISalesInvoiceRepository _repository;
        private readonly ScanProductionDbContext _dbContext;
        private readonly ISageX3SoapService _soapService;
        private readonly ILogger<SalesInvoiceController> _logger;

        public SalesInvoiceController(
            ISalesInvoiceRepository repository,
            ScanProductionDbContext dbContext,
            ISageX3SoapService soapService,
            ILogger<SalesInvoiceController> logger)
        {
            _repository = repository;
            _dbContext = dbContext;
            _soapService = soapService;
            _logger = logger;
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

            if (existingHeader != null && existingHeader.IsProcessedByX3 && !string.IsNullOrEmpty(existingHeader.X3DocumentId))
            {
                return Ok(new
                {
                    success = true,
                    invoiceId = payload.InvoiceId,
                    x3DocumentId = existingHeader.X3DocumentId,
                    message = "Invoice already processed and synced."
                });
            }

            // 1. Idempotency check: Did a previous SOAP request already succeed in Sage X3?
            string? recoveredX3DocId = null;
            string? recoveredRawPayload = null;

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

            var userSiteCode = User.FindFirst("SiteCode")?.Value;
            if (!string.IsNullOrEmpty(userSiteCode) && userSiteCode != "ALL")
            {
                payload.SalesSite = userSiteCode;
            }
            else if (string.IsNullOrEmpty(payload.SalesSite) || payload.SalesSite == "ALL")
            {
                payload.SalesSite = "POD";
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
                        TransactionalId = !string.IsNullOrWhiteSpace(payload.TransactionalId) ? payload.TransactionalId : payload.InvoiceId
                    };

                    foreach (var l in payload.Lines)
                    {
                        var lineTotal = l.Total > 0 ? l.Total : ((l.Quantity * l.BasePrice) - l.DiscountAmount + l.VatAmount);
                        var disc2 = l.Discount2 > 0 ? l.Discount2 : l.DiscountAmountFlat;
                        existingHeader.Lines.Add(new StagingSalesInvoiceLine
                        {
                            InvoiceId = payload.InvoiceId,
                            Sku = l.Sku,
                            Name = l.Name,
                            LineNo = l.LineNo,
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
                            TaxRule = l.TaxRule
                        });
                    }

                    _dbContext.StagingSalesInvoiceHeaders.Add(existingHeader);
                    await _dbContext.SaveChangesAsync(); // Generate IDs and save locally
                }

                string? x3DocId = recoveredX3DocId;
                string? x3ReqNum = null;
                string? x3RawPayload = recoveredRawPayload;

                // 2. Sync to X3 using SOAP service if not already recovered from a previous successful call
                if (string.IsNullOrEmpty(x3DocId))
                {
                    var importResult = await _soapService.ImportSalesInvoiceAsync(existingHeader);

                    bool isSuccess = importResult.Success || 
                        (!string.IsNullOrEmpty(importResult.RawPayload) && importResult.RawPayload.Contains("Creation of ", StringComparison.OrdinalIgnoreCase));

                    if (!isSuccess)
                    {
                        await transaction.RollbackAsync();
                        string errorMsg = !string.IsNullOrWhiteSpace(importResult.TechnicalError) 
                            ? importResult.TechnicalError 
                            : string.Join(" | ", importResult.Messages);

                        return BadRequest(new { success = false, invoiceId = payload.InvoiceId, error = errorMsg, rawPayload = importResult.RawPayload });
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
                        BankCode = p.BankCode,
                        BankName = p.BankName,
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

                    try
                    {
                        var payResult = await _soapService.ImportPaymentAsync(stagingPayments);
                        if (payResult.Success || (!string.IsNullOrEmpty(payResult.RawPayload) && payResult.RawPayload.Contains("Creation of ", StringComparison.OrdinalIgnoreCase)))
                        {
                            paymentSynced = true;
                            x3PaymentId = payResult.DocumentId;
                            foreach (var sp in stagingPayments)
                            {
                                sp.IsProcessedByX3 = true;
                                sp.IsSynced = 1;
                                sp.X3PaymentId = payResult.DocumentId;
                                sp.SoapRequestNumber = payResult.RequestNumber;
                            }
                        }
                        else
                        {
                            paymentError = !string.IsNullOrWhiteSpace(payResult.TechnicalError)
                                ? payResult.TechnicalError
                                : string.Join(" | ", payResult.Messages);
                            foreach (var sp in stagingPayments)
                            {
                                sp.SoapError = paymentError;
                            }
                        }
                    }
                    catch (Exception payEx)
                    {
                        paymentError = payEx.Message;
                        foreach (var sp in stagingPayments)
                        {
                            sp.SoapError = payEx.Message;
                        }
                    }

                    if (paymentSynced)
                    {
                        try
                        {
                            _dbContext.StagingSalesInvoicePayments.AddRange(stagingPayments);
                            await _dbContext.SaveChangesAsync();
                        }
                        catch (Exception payDbEx)
                        {
                            _logger.LogError(payDbEx, "Failed to persist StagingSalesInvoicePayments for Invoice {InvoiceId}: {Message}", payload.InvoiceId, payDbEx.InnerException?.Message ?? payDbEx.Message);
                        }
                    }
                    else
                    {
                        _logger.LogWarning("Payment SOAP failed for Invoice {InvoiceId}: {Error}. StagingSalesInvoicePayments will NOT be inserted into MSSQL.", payload.InvoiceId, paymentError);
                    }
                }

                return Ok(new
                {
                    success = true,
                    invoiceId = payload.InvoiceId,
                    x3Request = x3ReqNum,
                    x3DocumentId = x3DocId,
                    rawPayload = x3RawPayload,
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

            // 0. Idempotency check: Already processed and synced in HIPO?
            var existingHeader = await _dbContext.StagingSalesInvoiceHeaders
                .Include(h => h.Lines)
                .FirstOrDefaultAsync(h => h.InvoiceId == payload.CreditNoteId);

            if (existingHeader != null && existingHeader.IsProcessedByX3 && !string.IsNullOrEmpty(existingHeader.X3DocumentId))
            {
                return Ok(new
                {
                    success = true,
                    creditNoteId = payload.CreditNoteId,
                    x3DocumentId = existingHeader.X3DocumentId,
                    message = "Credit note already processed and synced."
                });
            }

            // 1. Idempotency check: Did a previous SOAP request already succeed in Sage X3?
            string? recoveredX3DocId = null;
            string? recoveredRawPayload = null;

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

            var userSiteCode = User.FindFirst("SiteCode")?.Value;
            if (!string.IsNullOrEmpty(userSiteCode) && userSiteCode != "ALL")
            {
                payload.SalesSite = userSiteCode;
            }
            else if (string.IsNullOrEmpty(payload.SalesSite) || payload.SalesSite == "ALL")
            {
                payload.SalesSite = "POD";
            }

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
                        TransactionMode = payload.TransactionMode ?? (string.IsNullOrEmpty(resolvedOriginX3Id) ? "1" : "4"),
                        IsProcessedByX3 = false,
                        SyncedAt = DateTime.UtcNow
                    };

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
                            OriginLineNo = line.OriginLineNo
                        });
                    }

                    _dbContext.StagingSalesInvoiceHeaders.Add(existingHeader);
                    await _dbContext.SaveChangesAsync();
                }

                string? x3DocId = recoveredX3DocId;
                string? x3ReqNum = null;
                string? x3RawPayload = recoveredRawPayload;

                // 2. Invoke Sage X3 SOAP if not already recovered
                if (string.IsNullOrEmpty(x3DocId))
                {
                    var importResult = await _soapService.ImportCreditNoteAsync(existingHeader);

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
                            rawPayload = importResult.RawPayload
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

                    try
                    {
                        var refundResult = await _soapService.ImportPaymentAsync(stagingRefundPayments);
                        if (refundResult.Success || (!string.IsNullOrEmpty(refundResult.RawPayload) && refundResult.RawPayload.Contains("Creation of ", StringComparison.OrdinalIgnoreCase)))
                        {
                            refundSynced = true;
                            x3RefundPaymentId = refundResult.DocumentId;
                            foreach (var srp in stagingRefundPayments)
                            {
                                srp.IsProcessedByX3 = true;
                                srp.IsSynced = 1;
                                srp.X3PaymentId = refundResult.DocumentId;
                                srp.SoapRequestNumber = refundResult.RequestNumber;
                            }
                        }
                        else
                        {
                            refundError = !string.IsNullOrWhiteSpace(refundResult.TechnicalError)
                                ? refundResult.TechnicalError
                                : string.Join(" | ", refundResult.Messages);
                            foreach (var srp in stagingRefundPayments)
                            {
                                srp.SoapError = refundError;
                            }
                        }
                    }
                    catch (Exception refEx)
                    {
                        refundError = refEx.Message;
                        foreach (var srp in stagingRefundPayments)
                        {
                            srp.SoapError = refEx.Message;
                        }
                    }

                    if (refundSynced)
                    {
                        try
                        {
                            _dbContext.StagingSalesInvoicePayments.AddRange(stagingRefundPayments);
                            await _dbContext.SaveChangesAsync();
                        }
                        catch (Exception refDbEx)
                        {
                            _logger.LogError(refDbEx, "Failed to persist StagingSalesInvoicePayments for Credit Note {CreditNoteId}: {Message}", payload.CreditNoteId, refDbEx.InnerException?.Message ?? refDbEx.Message);
                        }
                    }
                    else
                    {
                        _logger.LogWarning("Refund SOAP failed for Credit Note {CreditNoteId}: {Error}. StagingSalesInvoicePayments will NOT be inserted into MSSQL.", payload.CreditNoteId, refundError);
                    }
                }

                return Ok(new
                {
                    success = true,
                    creditNoteId = payload.CreditNoteId,
                    x3Request = x3ReqNum,
                    x3DocumentId = x3DocId,
                    rawPayload = x3RawPayload,
                    refundSynced,
                    x3RefundPaymentId,
                    refundError
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
                    BankCode = p.BankCode,
                    BankName = p.BankName,
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
                    var payResult = await _soapService.ImportPaymentAsync(stagingPayments);
                    bool isSuccess = payResult.Success || (!string.IsNullOrEmpty(payResult.RawPayload) && payResult.RawPayload.Contains("Creation of ", StringComparison.OrdinalIgnoreCase));

                    if (isSuccess)
                    {
                        foreach (var sp in stagingPayments)
                        {
                            sp.IsProcessedByX3 = true;
                            sp.IsSynced = 1;
                            sp.X3PaymentId = payResult.DocumentId;
                            sp.SoapRequestNumber = payResult.RequestNumber;
                        }
                    }
                    else
                    {
                        var paymentError = !string.IsNullOrWhiteSpace(payResult.TechnicalError)
                            ? payResult.TechnicalError
                            : string.Join(" | ", payResult.Messages);
                        foreach (var sp in stagingPayments)
                        {
                            sp.SoapError = paymentError;
                        }
                    }

                    if (isSuccess)
                    {
                        _dbContext.StagingSalesInvoicePayments.AddRange(stagingPayments);
                        await _dbContext.SaveChangesAsync();
                    }
                    else
                    {
                        _logger.LogWarning("Standalone payment SOAP failed for document {DocumentId}. StagingSalesInvoicePayments will NOT be inserted into MSSQL.", grp.Key.DocumentId);
                    }

                    results.Add(new
                    {
                        documentId = grp.Key.DocumentId,
                        x3InvoiceDocumentId = x3DocId,
                        success = isSuccess,
                        x3PaymentId = payResult.DocumentId,
                        x3Request = payResult.RequestNumber,
                        error = isSuccess ? null : (!string.IsNullOrWhiteSpace(payResult.TechnicalError) ? payResult.TechnicalError : string.Join(" | ", payResult.Messages))
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
            var (effectiveSiteCode, error) = ResolveEffectiveSiteCode(sitecode);
            if (error != null)
            {
                return error;
            }

            try
            {
                var customers = await _repository.GetCustomersAsync(effectiveSiteCode ?? string.Empty);
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
            var (effectiveSiteCode, error) = ResolveEffectiveSiteCode(sitecode);
            if (error != null)
            {
                return error;
            }

            try
            {
                var products = await _repository.GetProductsAsync(effectiveSiteCode!);
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
            var (effectiveSiteCode, error) = ResolveEffectiveSiteCode(sitecode);
            if (error != null)
            {
                return error;
            }

            try
            {
                var details = await _repository.GetItemStockDetailsAsync(effectiveSiteCode!);
                return Ok(details);
            }
            catch (System.Exception)
            {
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
                var data = await _repository.GetPriceListsAsync();
                return Ok(data);
            }
            catch (System.Exception)
            {
                return StatusCode(500, new { error = "An internal error occurred while retrieving price lists." });
            }
        }

        [HttpGet("salesreps")]
        public async Task<IActionResult> GetSalesReps([FromQuery] string? sitecode = null)
        {
            var userSiteCode = User.FindFirst("SiteCode")?.Value;
            bool isMultiSiteAdmin = string.Equals(userSiteCode, "ALL", StringComparison.OrdinalIgnoreCase) 
                                    || User.IsInRole("Admin") 
                                    || User.IsInRole("SuperAdmin");

            string? effectiveSite = null;
            if (!string.IsNullOrWhiteSpace(userSiteCode) && !string.Equals(userSiteCode, "ALL", StringComparison.OrdinalIgnoreCase))
            {
                if (!string.IsNullOrWhiteSpace(sitecode) && 
                    !string.Equals(sitecode, userSiteCode, StringComparison.OrdinalIgnoreCase))
                {
                    _logger.LogWarning("Security: User {User} assigned to {UserSite} attempted to query sales reps for unauthorized site {RequestedSite}.",
                        User.Identity?.Name, userSiteCode, sitecode);
                }
                effectiveSite = userSiteCode;
            }
            else if (isMultiSiteAdmin)
            {
                effectiveSite = string.Equals(sitecode, "ALL", StringComparison.OrdinalIgnoreCase) ? null : sitecode;
            }
            else
            {
                _logger.LogWarning("Security: Unassigned user {User} attempted to access sales reps.", User.Identity?.Name);
                return StatusCode(StatusCodes.Status403Forbidden, new { error = "User account is not assigned to a valid site." });
            }

            try
            {
                var data = await _repository.GetSalesRepsAsync(effectiveSite);
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
            [FromQuery] int daysCutoff = 90)
        {
            var (effectiveSite, errorResult) = ResolveEffectiveSiteCode(sitecode);
            if (errorResult != null) return errorResult;

            try
            {
                var data = await _repository.GetOpenInvoicesAsync(effectiveSite, customerno, daysCutoff);
                return Ok(data);
            }
            catch (System.Exception ex)
            {
                _logger.LogError(ex, "Error retrieving open invoices for site {Site}", effectiveSite);
                return StatusCode(500, new { error = "An internal error occurred while retrieving open invoices." });
            }
        }

        [HttpGet("x3-history")]
        public async Task<IActionResult> GetX3History(
            [FromQuery] string? sitecode = null,
            [FromQuery] string? customercode = null,
            [FromQuery] int months = 6)
        {
            var (effectiveSite, errorResult) = ResolveEffectiveSiteCode(sitecode);
            if (errorResult != null) return errorResult;

            try
            {
                var data = await _repository.GetX3HistoryAsync(effectiveSite ?? "", customercode, months);
                return Ok(data);
            }
            catch (System.Exception ex)
            {
                _logger.LogError(ex, "Error retrieving X3 history for site {Site}, customer {Customer}", effectiveSite, customercode);
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

        [HttpPost("open-invoices/payments/sync")]
        public async Task<IActionResult> SyncOpenInvoicePayments([FromBody] List<OpenInvoicePaymentSyncDto> payments)
        {
            if (payments == null || payments.Count == 0)
                return Ok(new { success = true, syncedCount = 0 });

            try
            {
                var userSiteCode = User.FindFirst("SiteCode")?.Value;
                var userName = User.Identity?.Name ?? "MobileUser";

                foreach (var payment in payments)
                {
                    if (!string.IsNullOrWhiteSpace(userSiteCode) && userSiteCode != "ALL")
                    {
                        payment.SiteCode = userSiteCode;
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

        private (string? EffectiveSiteCode, IActionResult? Error) ResolveEffectiveSiteCode(string? requestedSiteCode)
        {
            var userSiteCode = User.FindFirst("SiteCode")?.Value;
            bool isMultiSiteAdmin = string.Equals(userSiteCode, "ALL", StringComparison.OrdinalIgnoreCase) 
                                    || User.IsInRole("Admin") 
                                    || User.IsInRole("SuperAdmin");

            // Case 1: Standard user bound to a specific site
            if (!string.IsNullOrWhiteSpace(userSiteCode) && !string.Equals(userSiteCode, "ALL", StringComparison.OrdinalIgnoreCase))
            {
                if (!string.IsNullOrWhiteSpace(requestedSiteCode) && 
                    !string.Equals(requestedSiteCode, userSiteCode, StringComparison.OrdinalIgnoreCase))
                {
                    _logger.LogWarning("Security: User {User} assigned to {UserSite} attempted to query unauthorized site {RequestedSite}.",
                        User.Identity?.Name, userSiteCode, requestedSiteCode);
                }

                return (userSiteCode, null);
            }

            // Case 2: Multi-site administrator
            if (isMultiSiteAdmin)
            {
                if (string.IsNullOrWhiteSpace(requestedSiteCode) || string.Equals(requestedSiteCode, "ALL", StringComparison.OrdinalIgnoreCase))
                {
                    return (null, BadRequest(new { error = "An explicit sitecode is required to fetch records. 'ALL' is not permitted." }));
                }

                return (requestedSiteCode, null);
            }

            // Case 3: Unassigned / unauthorized user
            _logger.LogWarning("Security: Unassigned user {User} attempted to access site-scoped resource.", User.Identity?.Name);
            return (null, StatusCode(StatusCodes.Status403Forbidden, new { error = "User account is not assigned to a valid site." }));
        }
    }
}
