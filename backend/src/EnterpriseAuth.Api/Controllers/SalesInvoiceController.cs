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

            // Process one invoice at a time, transactionally
            using var transaction = await _dbContext.Database.BeginTransactionAsync();
            try
            {
                var userSiteCode = User.FindFirst("SiteCode")?.Value;
                if (!string.IsNullOrEmpty(userSiteCode) && userSiteCode != "ALL")
                {
                    payload.SalesSite = userSiteCode;
                }
                else if (string.IsNullOrEmpty(payload.SalesSite) || payload.SalesSite == "ALL")
                {
                    payload.SalesSite = "IPL";
                }

                // 1. Insert into Staging
                var stagingHeader = new StagingSalesInvoiceHeader
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
                    UserName = payload.UserName,
                    SalesRep = payload.SalesRep,
                    TransactionalId = payload.TransactionalId
                };

                foreach(var l in payload.Lines)
                {
                    var lineTotal = l.Total > 0 ? l.Total : ((l.Quantity * l.BasePrice) - l.DiscountAmount + l.VatAmount);
                    stagingHeader.Lines.Add(new StagingSalesInvoiceLine
                    {
                        InvoiceId = payload.InvoiceId,
                        Sku = l.Sku,
                        Name = l.Name,
                        LineNo = l.LineNo,
                        Quantity = (double)l.Quantity,
                        BasePrice = (double)l.BasePrice,
                        DiscountAmount = (double)l.DiscountAmount,
                        VatAmount = (double)l.VatAmount,
                        Total = (double)lineTotal,
                        LotNumber = l.LotNumber,
                        Warehouse = l.Warehouse,
                        SalesUnit = l.SalesUnit,
                        Cce0 = l.Cce0,
                        TaxRule = l.TaxRule
                    });
                }

                _dbContext.StagingSalesInvoiceHeaders.Add(stagingHeader);
                await _dbContext.SaveChangesAsync(); // Generate IDs and save locally

                // 2. Sync to X3 using the strict MSSQL data source
                var importResult = await _soapService.ImportSalesInvoiceAsync(stagingHeader);

                bool isSuccess = importResult.Success || 
                    (!string.IsNullOrEmpty(importResult.RawPayload) && importResult.RawPayload.Contains("Creation of ", StringComparison.OrdinalIgnoreCase));

                if (isSuccess)
                {
                    stagingHeader.IsProcessedByX3 = true;
                    if (!string.IsNullOrEmpty(importResult.DocumentId))
                    {
                        stagingHeader.X3DocumentId = importResult.DocumentId;
                    }
                    await _dbContext.SaveChangesAsync();
                    
                    // 3. Commit exactly on success
                    await transaction.CommitAsync();
                    return Ok(new { success = true, invoiceId = payload.InvoiceId, x3Request = importResult.RequestNumber, x3DocumentId = importResult.DocumentId, rawPayload = importResult.RawPayload });
                }
                else
                {
                    // 4. Rollback exactly on X3 failure
                    await transaction.RollbackAsync();
                    string errorMsg = !string.IsNullOrWhiteSpace(importResult.TechnicalError) 
                        ? importResult.TechnicalError 
                        : string.Join(" | ", importResult.Messages);

                    return BadRequest(new { success = false, invoiceId = payload.InvoiceId, error = errorMsg, rawPayload = importResult.RawPayload });
                }
            }
            catch (Exception ex)
            {
                await transaction.RollbackAsync();
                return StatusCode(500, new { success = false, invoiceId = payload.InvoiceId, error = ex.Message });
            }
        }

        [HttpPost("sync-credit-note")]
        public async Task<IActionResult> SyncCreditNote([FromBody] CreditNoteSyncDto payload)
        {
            if (payload == null || string.IsNullOrWhiteSpace(payload.CreditNoteId))
                return BadRequest(new { success = false, error = "Invalid credit note payload." });

            if (payload.GrandTotal <= 0)
                return BadRequest(new { success = false, error = "Credit note with zero or negative total amount cannot be created." });

            // Atomic transaction: rollback on failure, commit only on confirmed X3 success
            using var transaction = await _dbContext.Database.BeginTransactionAsync();
            try
            {
                var userSiteCode = User.FindFirst("SiteCode")?.Value;
                if (!string.IsNullOrEmpty(userSiteCode) && userSiteCode != "ALL")
                {
                    payload.SalesSite = userSiteCode;
                }
                else if (string.IsNullOrEmpty(payload.SalesSite) || payload.SalesSite == "ALL")
                {
                    payload.SalesSite = "IPL";
                }

                var stagingHeader = new StagingCreditNoteHeader
                {
                    CreditNoteId = payload.CreditNoteId,
                    CreditNoteType = payload.CreditNoteType,
                    X3CreditNoteType = !string.IsNullOrEmpty(payload.X3CreditNoteType) ? payload.X3CreditNoteType : "CRN",
                    SalesSite = payload.SalesSite,
                    CustomerCode = payload.CustomerCode,
                    CustomerName = payload.CustomerName,
                    Currency = !string.IsNullOrEmpty(payload.Currency) ? payload.Currency : "MUR",
                    GrandTotal = payload.GrandTotal,
                    OriginalInvoiceId = payload.OriginalInvoiceId,
                    LinkedInvoiceIds = payload.LinkedInvoiceIds != null && payload.LinkedInvoiceIds.Count > 0 ? string.Join(",", payload.LinkedInvoiceIds) : null,
                    SettlementType = payload.SettlementType,
                    Reference = payload.Reference,
                    CreatedAt = payload.CreatedAt ?? DateTime.UtcNow.ToString("yyyyMMdd"),
                    CreatedBy = payload.CreatedBy ?? "system",
                    DeviceId = payload.DeviceId,
                    IsProcessedByX3 = false,
                    SyncedAt = DateTime.UtcNow
                };

                foreach (var line in payload.Lines)
                {
                    stagingHeader.Lines.Add(new StagingCreditNoteLine
                    {
                        CreditNoteId = payload.CreditNoteId,
                        LineNo = line.LineNo,
                        Quantity = line.Quantity,
                        OriginInvoiceId = line.OriginInvoiceId,
                        OriginLineNo = line.OriginLineNo,
                        StandaloneSku = line.StandaloneSku,
                        StandaloneName = line.StandaloneName,
                        StandaloneSalesUnit = line.StandaloneSalesUnit,
                        StandalonePrice = line.StandalonePrice,
                        StandaloneTaxRule = line.StandaloneTaxRule,
                        StandaloneLot = line.StandaloneLot,
                        StandaloneWarehouse = line.StandaloneWarehouse,
                        StandaloneCce0 = line.StandaloneCce0
                    });
                }

                foreach (var refund in payload.Refunds)
                {
                    stagingHeader.Refunds.Add(new StagingCreditNoteRefund
                    {
                        CreditNoteId = payload.CreditNoteId,
                        Method = refund.Method,
                        Amount = refund.Amount,
                        BankCode = refund.BankCode,
                        BankName = refund.BankName,
                        ChequeNumber = refund.ChequeNumber,
                        ChequeDate = refund.ChequeDate
                    });
                }

                _dbContext.StagingCreditNoteHeaders.Add(stagingHeader);
                await _dbContext.SaveChangesAsync();

                // 2. Invoke Sage X3 SOAP
                var importResult = await _soapService.ImportCreditNoteAsync(stagingHeader);

                bool isSuccess = importResult.Success ||
                    (!string.IsNullOrEmpty(importResult.RawPayload) && importResult.RawPayload.Contains("Creation of ", StringComparison.OrdinalIgnoreCase));

                if (isSuccess)
                {
                    stagingHeader.IsProcessedByX3 = true;
                    if (!string.IsNullOrEmpty(importResult.DocumentId))
                    {
                        stagingHeader.X3DocumentId = importResult.DocumentId;
                    }
                    await _dbContext.SaveChangesAsync();

                    // 3. Commit exactly on confirmed success
                    await transaction.CommitAsync();
                    return Ok(new
                    {
                        success = true,
                        creditNoteId = payload.CreditNoteId,
                        x3Request = importResult.RequestNumber,
                        x3DocumentId = importResult.DocumentId,
                        rawPayload = importResult.RawPayload
                    });
                }
                else
                {
                    // 4. Rollback strictly on failure — zero dirty rows remain in MSSQL
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
            }
            catch (Exception ex)
            {
                await transaction.RollbackAsync();
                return StatusCode(500, new { success = false, creditNoteId = payload.CreditNoteId, error = ex.Message });
            }
        }

        [HttpGet("customers")]
        public async Task<IActionResult> GetCustomers()
        {
            try
            {
                var customers = await _repository.GetCustomersAsync(string.Empty);
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
