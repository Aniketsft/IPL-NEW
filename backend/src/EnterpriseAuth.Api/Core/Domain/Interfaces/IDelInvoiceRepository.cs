using EnterpriseAuth.Api.Core.Application.DTOs;

namespace EnterpriseAuth.Api.Core.Domain.Interfaces
{
    public interface IDelInvoiceRepository
    {
        Task<List<InvoiceRowDto>> GetAllInvoices();
    }
}