using System;

namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class DeviceLocationDto
    {
        public string DeviceId { get; set; } = string.Empty;
        public string DeviceName { get; set; } = string.Empty;
        public string? HardwareModel { get; set; }
        public string SiteCode { get; set; } = string.Empty;
        public string? WarehouseCode { get; set; }
        public string LocationCode { get; set; } = string.Empty;
        public string? HepProfileId { get; set; }
        public string? HepApiKey { get; set; }
        public bool IsLocked { get; set; } = true;
        public bool IsLicensed { get; set; } = true;
        public string LicenseStatus { get; set; } = "VALID";
        public DateTime? LicenseUpdatedAt { get; set; }
        public string? LicenseUpdatedBy { get; set; }
        public Guid? AssignedUserId { get; set; }
        public string? AssignedUserName { get; set; }
        public bool IsActive { get; set; } = true;
        public DateTime? UpdatedAt { get; set; }
        public string? UpdatedBy { get; set; }
    }

    public class DeviceHeartbeatRequestDto
    {
        public string DeviceId { get; set; } = string.Empty;
        public string? DeviceName { get; set; }
        public string? HardwareModel { get; set; }
        public string? SiteCode { get; set; }
    }

    public class DeviceProvisionRequestDto
    {
        public string DeviceName { get; set; } = string.Empty;
        public string? HardwareModel { get; set; }
        public string SiteCode { get; set; } = string.Empty;
        public string LocationCode { get; set; } = string.Empty;
        public string? WarehouseCode { get; set; }
        public string? HepProfileId { get; set; }
        public string? HepApiKey { get; set; }
    }

    public class DeviceLocationUpdateRequestDto
    {
        public string LocationCode { get; set; } = string.Empty;
        public string? WarehouseCode { get; set; }
    }

    public class DeviceAdminConfigRequestDto
    {
        public string? DeviceName { get; set; }
        public string? SiteCode { get; set; }
        public string? HepProfileId { get; set; }
        public string? HepApiKey { get; set; }
        public bool? IsLocked { get; set; }
    }

    public class DeviceLicenseToggleDto
    {
        public bool IsLicensed { get; set; }
    }

    public class LorryLookupDto
    {
        public string Location { get; set; } = string.Empty;
        public string? PlateNumber { get; set; }
        public string? LocationType { get; set; }
        public string? Warehouse { get; set; }
        public string? WarehouseName { get; set; }
        public string? Description { get; set; }
    }
}
