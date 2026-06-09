using System;

namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class DeviceSyncLogDto
    {
        public string DeviceId { get; set; } = string.Empty;
        public string LastSyncedBy { get; set; } = string.Empty;
        public DateTime LastSyncTime { get; set; }
        public string ActionType { get; set; } = string.Empty;
    }
}
