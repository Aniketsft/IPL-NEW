using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using EnterpriseAuth.Api.Core.Application.DTOs;
using EnterpriseAuth.Api.Core.Domain.Entities;

namespace EnterpriseAuth.Api.Core.Application.Interfaces
{
    public interface IFiscalisationService
    {
        Task<(int HttpStatusCode, FiscaliseResultDto Result)> FiscaliseAsync(
            FiscaliseDocumentRequestDto request,
            string? headerDeviceId,
            string? userName,
            string? userSiteCode,
            CancellationToken cancellationToken = default);

        Task<HepFiscalInvoice?> GetFiscalInvoiceAsync(string documentNo, CancellationToken cancellationToken = default);

        Task<bool> IsDocumentFiscalisedAsync(string documentNo, CancellationToken cancellationToken = default);

        Task MarkX3SyncedAsync(string documentNo, string? x3DocumentId, CancellationToken cancellationToken = default);

        Task<List<HepFiscalInvoice>> GetPendingX3SyncAsync(int limit = 100, CancellationToken cancellationToken = default);

        Task<List<HepFiscalFailureLog>> GetFailureLogsAsync(string? documentNo = null, int limit = 100, CancellationToken cancellationToken = default);
    }
}
