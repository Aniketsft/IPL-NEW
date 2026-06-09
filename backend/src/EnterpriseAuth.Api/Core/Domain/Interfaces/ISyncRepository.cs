using System.Threading.Tasks;
using EnterpriseAuth.Api.Core.Application.DTOs;

namespace EnterpriseAuth.Api.Core.Domain.Interfaces
{
    public interface ISyncRepository
    {
        Task<SyncPackageDto> GetRefreshPackageAsync(string site, string? deviceId = null, string? performedBy = null);
        Task<int> PushUpdatesAsync(SyncPushRequestDto request, string performedBy);
        Task<IEnumerable<DeviceSyncLogDto>> GetLatestDeviceSyncsAsync();
    }
}
