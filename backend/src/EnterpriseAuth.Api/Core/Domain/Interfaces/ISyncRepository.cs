using System.Collections.Generic;
using System.Threading.Tasks;
using EnterpriseAuth.Api.Core.Application.DTOs;

namespace EnterpriseAuth.Api.Core.Domain.Interfaces
{
    public interface ISyncRepository
    {
        Task<SyncPackageDto> GetRefreshPackageAsync(string site, string? deviceId = null, string? performedBy = null);
        Task<IEnumerable<LocationLookupDto>> GetSiteLocationsAsync(string site);
        Task<SalesSyncExtrasDto> GetSalesSyncExtrasAsync(string site, string? deviceId = null, string? performedBy = null);
        Task<int> PushUpdatesAsync(SyncPushRequestDto request, string performedBy);
        Task<IEnumerable<DeviceSyncLogDto>> GetLatestDeviceSyncsAsync(string? siteCode = null);
        Task LogDeviceSyncAsync(string deviceId, string actionType, string site, string performedBy, string? payload = null);
        Task<Dictionary<string, string>> GetGlobalSettingsAsync();
        Task UpsertGlobalSettingAsync(string settingKey, string settingValue, string performedBy, string? deviceId = null);
    }
}
