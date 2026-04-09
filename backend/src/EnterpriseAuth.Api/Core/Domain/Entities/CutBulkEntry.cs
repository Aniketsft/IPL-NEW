using System;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    public class CutBulkEntry
    {
        public int Id { get; set; }
        public string EntryNumber { get; set; } = string.Empty;
        public string Type { get; set; } = string.Empty; // 'Cuts' or 'Bulks'
        public string CustomerCode { get; set; } = string.Empty;
        public string CustomerName { get; set; } = string.Empty;
        public DateTime Date { get; set; }
        public string? PoNumber { get; set; }
        public string? Salesman1Code { get; set; }
        public string? Salesman2Code { get; set; }
        public decimal AmountKg { get; set; }

        // Enterprise Sync Metadata
        public string? DeviceId { get; set; }
        public string? SyncStatus { get; set; } // 'Synced', 'Pending'
        public DateTime? SyncTimestamp { get; set; }
    }
}
