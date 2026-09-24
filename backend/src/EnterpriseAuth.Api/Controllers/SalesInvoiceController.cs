using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.Threading.Tasks;
using EnterpriseAuth.Api.Core.Application.Interfaces;
using EnterpriseAuth.Api.Infrastructure.Persistence;
using EnterpriseAuth.Api.Core.Domain.Entities;
using EnterpriseAuth.Api.Core.Application.DTOs;
using System;

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

        public SalesInvoiceController(
            ISalesInvoiceRepository repository,
            ScanProductionDbContext dbContext,
            ISageX3SoapService soapService)
        {
            _repository = repository;
            _dbContext = dbContext;
            _soapService = soapService;
        }

        [HttpPost("sync")]
        public async Task<IActionResult> SyncInvoice([FromBody] SalesInvoiceSyncDto payload)
        {
            if (payload == null || string.IsNullOrWhiteSpace(payload.InvoiceId))
                return BadRequest(new { success = false, error = "Invalid payload." });

            var totalAmount = payload.Lines.Sum(l => l.Total);
            if (payload.Lines.Count == 0 || totalAmount <= 0)
                return BadRequest(new { success = false, error = "Invoice with zero or negative total amount cannot be created." });

            // Process one invoice at a time, transactionally
            using var transaction = await _dbContext.Database.BeginTransactionAsync();
            try
            {
                var userSiteCode = User.FindFirst("SiteCode")?.Value;
                if (!string.IsNullOrEmpty(userSiteCode))
                {
                    payload.SalesSite = userSiteCode;
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
                if (!string.IsNullOrEmpty(userSiteCode))
                {
                    payload.SalesSite = userSiteCode;
                }

                var stagingHeader = new StagingCreditNoteHeader
                {
                    CreditNoteId = payload.CreditNoteId,
                    CreditNoteType = payload.CreditNoteType,
                    X3CreditNoteType = !string.IsNullOrEmpty(payload.X3CreditNoteType) ? payload.X3CreditNoteType : "CRN",
                    SalesSite = !string.IsNullOrEmpty(payload.SalesSite) ? payload.SalesSite : "SCG",
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
                // Fetch directly from X3
                var customers = await _repository.GetCustomersAsync();
                
                return Ok(customers);
            }
            catch (System.Exception ex)
            {
                // Dump the exact error to the HTTP response for bug hunting
                return StatusCode(500, ex.ToString());
            }
        }

        [HttpGet("Products")]
        public async Task<IActionResult> GetProducts([FromQuery] string? sitecode = null)
        {
            var userSiteCode = User.FindFirst("SiteCode")?.Value;

            if (string.IsNullOrWhiteSpace(sitecode) && !string.IsNullOrWhiteSpace(userSiteCode))
            {
                sitecode = userSiteCode;
            }
            else if (!string.IsNullOrWhiteSpace(userSiteCode) && !string.Equals(userSiteCode, "ALL", StringComparison.OrdinalIgnoreCase))
            {
                sitecode = userSiteCode;
            }

            if (string.IsNullOrWhiteSpace(sitecode))
            {
                return BadRequest("A specific sitecode is required to fetch products.");
            }

            try
            {
                var products = await _repository.GetProductsAsync(sitecode);
                return Ok(products);
            }
            catch (System.Exception ex)
            {
                return StatusCode(500, ex.ToString());
            }
        }

        [HttpGet("itemstockdetails")]
        public async Task<IActionResult> GetItemStockDetails([FromQuery] string? sitecode = null)
        {
            var userSiteCode = User.FindFirst("SiteCode")?.Value;

            if (string.IsNullOrWhiteSpace(sitecode) && !string.IsNullOrWhiteSpace(userSiteCode))
            {
                sitecode = userSiteCode;
            }
            else if (!string.IsNullOrWhiteSpace(userSiteCode) && !string.Equals(userSiteCode, "ALL", StringComparison.OrdinalIgnoreCase))
            {
                sitecode = userSiteCode;
            }

            if (string.IsNullOrWhiteSpace(sitecode))
            {
                return BadRequest("A specific sitecode is required to fetch item stock details.");
            }

            try
            {
                var details = await _repository.GetItemStockDetailsAsync(sitecode);
                return Ok(details);
            }
            catch (System.Exception ex)
            {
                return StatusCode(500, ex.ToString());
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
            catch (System.Exception ex)
            {
                return StatusCode(500, ex.ToString());
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
            catch (System.Exception ex)
            {
                return StatusCode(500, ex.ToString());
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
            catch (System.Exception ex)
            {
                return StatusCode(500, ex.ToString());
            }
        }
    }
}
