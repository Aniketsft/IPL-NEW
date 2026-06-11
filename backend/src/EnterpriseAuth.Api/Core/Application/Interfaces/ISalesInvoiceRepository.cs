using System.Collections.Generic;
using System.Threading.Tasks;
using EnterpriseAuth.Api.Core.Domain.Entities;

namespace EnterpriseAuth.Api.Core.Application.Interfaces
{
    public interface ISalesInvoiceRepository
    {
        Task<IEnumerable<SalesInvoiceCustomer>> GetCustomersAsync();
        Task SyncCustomersFromX3Async();
        Task<IEnumerable<EnterpriseAuth.Api.Core.Application.DTOs.SalesInvoiceProductDto>> GetProductsAsync(string sitecode);
    }
}
