using System.Collections.Generic;
using System.Threading.Tasks;
using EnterpriseAuth.Api.Core.Domain.Entities;

namespace EnterpriseAuth.Api.Core.Application.Interfaces
{
    public interface ISalesInvoiceRepository
    {
        Task<IEnumerable<EnterpriseAuth.Api.Core.Application.DTOs.SalesInvoiceCustomerDto>> GetCustomersAsync();
        Task<IEnumerable<EnterpriseAuth.Api.Core.Application.DTOs.SalesInvoiceProductDto>> GetProductsAsync(string sitecode);
        Task<IEnumerable<EnterpriseAuth.Api.Core.Application.DTOs.SalesInvoiceItemStockDto>> GetItemStockDetailsAsync();
        Task<IEnumerable<EnterpriseAuth.Api.Core.Application.DTOs.TaxMatrixDto>> GetTaxDeterminationsAsync();
        Task<IEnumerable<EnterpriseAuth.Api.Core.Application.DTOs.TaxRateDto>> GetTaxRatesAsync();
    }
}
