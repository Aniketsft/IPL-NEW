using System.Collections.Generic;
using System.Threading.Tasks;
using EnterpriseAuth.Api.Core.Domain.Entities;

namespace EnterpriseAuth.Api.Core.Application.Interfaces
{
    public interface ISalesInvoiceRepository
    {
        Task<IEnumerable<EnterpriseAuth.Api.Core.Application.DTOs.SalesInvoiceCustomerDto>> GetCustomersAsync(string sitecode = "");
        Task<IEnumerable<EnterpriseAuth.Api.Core.Application.DTOs.SalesInvoiceProductDto>> GetProductsAsync(string sitecode);
        Task<IEnumerable<EnterpriseAuth.Api.Core.Application.DTOs.SalesInvoiceItemStockDto>> GetItemStockDetailsAsync(string sitecode);
        Task<IEnumerable<EnterpriseAuth.Api.Core.Application.DTOs.TaxMatrixDto>> GetTaxDeterminationsAsync();
        Task<IEnumerable<EnterpriseAuth.Api.Core.Application.DTOs.TaxRateDto>> GetTaxRatesAsync();
        Task<IEnumerable<EnterpriseAuth.Api.Core.Application.DTOs.PriceListDto>> GetPriceListsAsync();
        Task<IEnumerable<EnterpriseAuth.Api.Core.Application.DTOs.SalesRepLookupDto>> GetSalesRepsAsync(string? siteCode = null);
    }
}
