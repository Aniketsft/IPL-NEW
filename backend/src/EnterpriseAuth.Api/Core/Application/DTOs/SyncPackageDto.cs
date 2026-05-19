using System;
using System.Collections.Generic;

namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class SyncPackageDto
    {
        public List<SalesOrderHeaderDto> Orders { get; set; } = new();
        public List<SalesOrderDetailDto> Details { get; set; } = new();
        public List<CustomerLookupDto> Customers { get; set; } = new();
        public List<SalesRepLookupDto> Reps { get; set; } = new();
        public List<LocationLookupDto> Locations { get; set; } = new();
        public List<ProductLookupDto> Products { get; set; } = new();
        public List<SiteLookupDto> Sites { get; set; } = new();
        public List<LotLookupDto> Lots { get; set; } = new();
        public List<CutBulkEntryDto> CutBulkEntries { get; set; } = new();
        public Dictionary<string, string> GlobalSettingsMap { get; set; } = new();
        public DateTime SyncTimestamp { get; set; } = DateTime.UtcNow;
    }

    public class SyncPushRequestDto
    {
        public List<ProductionScanDto> Scans { get; set; } = new();
        public List<CutBulkEntryDto> CutBulkEntries { get; set; } = new();
        public List<PreparationStatusUpdateDto> PreparationStatusUpdates { get; set; } = new();
        public List<ShipmentPreparationUpdateDto> ShipmentPreparationUpdates { get; set; } = new();
        public List<OrderStatusUpdateDto> OrderStatusUpdates { get; set; } = new();
        public List<LabelAuditDto> LabelAudits { get; set; } = new();
        public List<GlobalSettingUpdateDto>? GlobalSettingsUpdates { get; set; }
        public List<StagingEodDto> StagingEodEntries { get; set; } = new();
        public string DeviceId { get; set; } = string.Empty;
        public List<OfflineAuditDto> OfflineAudits { get; set; } = new();
        public List<EodProcessAuditDto> EodProcessAudits { get; set; } = new();
    }

    public class OfflineAuditDto
    {
        public string Entity { get; set; } = string.Empty;
        public string Action { get; set; } = string.Empty;
        public string Payload { get; set; } = string.Empty;
        public string? DeviceId { get; set; }
        public DateTime Timestamp { get; set; }
    }

    public class StagingEodDto
    {
        public Guid Id { get; set; }
        public string WorkOrderNumber { get; set; } = string.Empty;
        public string ProductCode { get; set; } = string.Empty;
        public decimal TotalManufacturedQuantity { get; set; }
        public DateTime DateOfManufacturing { get; set; }
        public string Unit { get; set; } = string.Empty;
        public string Location { get; set; } = string.Empty;
        public string ItemStatus { get; set; } = string.Empty;
        public DateTime? ExpiryDate { get; set; }
        public string? Location2 { get; set; } = string.Empty;
        public string? Location3 { get; set; } = string.Empty;
        public decimal EaQuantity { get; set; }
        public DateTime CreatedAt { get; set; }
        public string? LotNumber { get; set; }
        public string? DeviceId { get; set; }
    }

    public class GlobalSettingUpdateDto
    {
        public string SettingKey { get; set; } = string.Empty;
        public string SettingValue { get; set; } = string.Empty;
        public string UpdatedBy { get; set; } = string.Empty;
    }

    public class LabelAuditDto
    {
        public string LabelId { get; set; } = string.Empty;
        public string? ReferenceNumber { get; set; }
        public string? LabelType { get; set; }
        public string? ProductCode { get; set; }
        public string? CustomerName { get; set; }
        public decimal TotalWeight { get; set; }
        public string? ManifestJson { get; set; }
        public string? PrintedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public bool IsOfflineCreated { get; set; }
        public string? DeviceId { get; set; }
    }

    public class PreparationStatusUpdateDto
    {
        public string SoNumber { get; set; } = string.Empty;
        public string ItemCode { get; set; } = string.Empty;
        public bool IsPrepared { get; set; }
        public bool IsValidated { get; set; }
        public string? DeviceId { get; set; }
    }

    public class ShipmentPreparationUpdateDto
    {
        public string SoNumber { get; set; } = string.Empty;
        public bool IsPreparedForShipment { get; set; }
        public bool? IsValidated { get; set; }
    }

    public class OrderStatusUpdateDto
    {
        public string SoNumber { get; set; } = string.Empty;
        public int Status { get; set; }
    }

    public class EodProcessAuditDto
    {
        public Guid Id { get; set; }
        public string EodDate { get; set; } = string.Empty;
        public string WorkOrderNumber { get; set; } = string.Empty;
        public string TriggeredBy { get; set; } = string.Empty;
        public string DeviceId { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; }
    }
}
