using System.Threading.Tasks;
using EnterpriseAuth.Api.Core.Application.DTOs;

namespace EnterpriseAuth.Api.Core.Domain.Interfaces
{
    public interface ISyncRepository
    {
        Task<SyncPackageDto> GetRefreshPackageAsync(string site);
        Task<int> PushUpdatesAsync(SyncPushRequestDto request);
    }
}
