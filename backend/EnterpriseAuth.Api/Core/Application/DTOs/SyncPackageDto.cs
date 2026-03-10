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
        public List<ProductionScanDto> RecentScans { get; set; } = new();
        public DateTime SyncTimestamp { get; set; } = DateTime.UtcNow;
    }

    public class SyncPushRequestDto
    {
        public List<ProductionScanDto> Scans { get; set; } = new();
        public List<CutBulkEntryDto> CutBulkEntries { get; set; } = new();
        public string DeviceId { get; set; } = string.Empty;
    }
}
