using System;

namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class DeviceLocationDto
    {
        public string DeviceId { get; set; } = string.Empty;
        public string? MacAddress { get; set; }
        public string DeviceName { get; set; } = string.Empty;
        public string SiteCode { get; set; } = string.Empty;
        public string? WarehouseCode { get; set; }
        public string LocationCode { get; set; } = string.Empty;
        public Guid? AssignedUserId { get; set; }
        public string? AssignedUserName { get; set; }
        public bool IsActive { get; set; } = true;
        public DateTime? UpdatedAt { get; set; }
        public string? UpdatedBy { get; set; }
    }

    public class DeviceHeartbeatRequestDto
    {
        public string DeviceId { get; set; } = string.Empty;
        public string? MacAddress { get; set; }
        public string DeviceName { get; set; } = string.Empty;
        public string SiteCode { get; set; } = string.Empty;
    }
}
