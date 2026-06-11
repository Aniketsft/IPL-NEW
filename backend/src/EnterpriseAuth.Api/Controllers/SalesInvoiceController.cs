using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.Threading.Tasks;
using EnterpriseAuth.Api.Core.Application.Interfaces;

namespace EnterpriseAuth.Api.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    [Authorize]
    public class SalesInvoiceController : ControllerBase
    {
        private readonly ISalesInvoiceRepository _repository;

        public SalesInvoiceController(ISalesInvoiceRepository repository)
        {
            _repository = repository;
        }

        [HttpGet("customers")]
        public async Task<IActionResult> GetCustomers()
        {
            try
            {
                // First, trigger the upsert from X3 to local DB
                await _repository.SyncCustomersFromX3Async();
                
                // Then fetch from local DB
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
    }
}
