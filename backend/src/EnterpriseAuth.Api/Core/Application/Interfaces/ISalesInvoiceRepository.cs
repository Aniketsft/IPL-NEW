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
        Task<IEnumerable<EnterpriseAuth.Api.Core.Application.DTOs.OpenInvoiceDto>> GetOpenInvoicesAsync(string? siteCode = null, string? customerNo = null, int daysCutoff = 90);
        Task<IEnumerable<EnterpriseAuth.Api.Core.Application.DTOs.X3HistoryDocumentDto>> GetX3HistoryAsync(string siteCode, string? customerCode = null, int months = 6);
        Task<IEnumerable<EnterpriseAuth.Api.Core.Application.DTOs.CreditNoteReasonDto>> GetCreditNoteReasonsAsync();
        Task<IEnumerable<EnterpriseAuth.Api.Core.Application.DTOs.BankDto>> GetBanksAsync();
        Task<string> GetX3HistoryWatermarkAsync(string siteCode, int months = 6);
        Task<string> GetOpenInvoicesWatermarkAsync(string siteCode, int daysCutoff = 90);
        Task<string> GetStockWatermarkAsync(string siteCode);
        Task<string> GetPriceListsWatermarkAsync();
        Task<EnterpriseAuth.Api.Core.Application.DTOs.CustomerLiveCreditDto?> GetCustomerLiveCreditAsync(string customerNo);
        Task<EnterpriseAuth.Api.Core.Application.DTOs.SalesInvoiceCustomerDto?> GetCustomerByCodeAsync(string customerCode);
        Task<EnterpriseAuth.Api.Core.Application.DTOs.ProductLiveStockDto?> GetProductLiveStockAsync(string productCode, string siteCode);
    }
}
