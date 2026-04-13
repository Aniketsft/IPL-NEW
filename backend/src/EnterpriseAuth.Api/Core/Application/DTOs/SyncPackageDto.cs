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
        public List<ProductionScanDto> RecentScans { get; set; } = new();
        public DateTime SyncTimestamp { get; set; } = DateTime.UtcNow;
    }

    public class SyncPushRequestDto
    {
        public List<ProductionScanDto> Scans { get; set; } = new();
        public List<CutBulkEntryDto> CutBulkEntries { get; set; } = new();
        public List<PreparationStatusUpdateDto> PreparationStatusUpdates { get; set; } = new();
        public List<ShipmentPreparationUpdateDto> ShipmentPreparationUpdates { get; set; } = new();
        public List<OrderStatusUpdateDto> OrderStatusUpdates { get; set; } = new();
        public string DeviceId { get; set; } = string.Empty;
    }

    public class PreparationStatusUpdateDto
    {
        public string SoNumber { get; set; } = string.Empty;
        public string ItemCode { get; set; } = string.Empty;
        public bool IsPrepared { get; set; }
    }

    public class ShipmentPreparationUpdateDto
    {
        public string SoNumber { get; set; } = string.Empty;
        public bool IsPreparedForShipment { get; set; }
    }

    public class OrderStatusUpdateDto
    {
        public string SoNumber { get; set; } = string.Empty;
        public int Status { get; set; }
    }
}
