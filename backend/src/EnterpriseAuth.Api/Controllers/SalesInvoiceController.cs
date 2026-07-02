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

            // Process one invoice at a time, transactionally
            using var transaction = await _dbContext.Database.BeginTransactionAsync();
            try
            {
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
        public async Task<IActionResult> GetProducts([FromQuery] string sitecode)
        {
            if (string.IsNullOrEmpty(sitecode))
            {
                return BadRequest("sitecode is required.");
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
        public async Task<IActionResult> GetItemStockDetails()
        {
            try
            {
                var details = await _repository.GetItemStockDetailsAsync();
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
