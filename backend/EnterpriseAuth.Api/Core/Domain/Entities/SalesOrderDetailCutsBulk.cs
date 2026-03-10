using System;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    public class SalesOrderDetailCutsBulk
    {
        public int Id { get; set; }
        public string SoNumber { get; set; } = string.Empty;
        public string ItemCode { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;
        public string BarcodeType { get; set; } = "Variable Weight";
        public decimal Quantity { get; set; }
        
        // Enterprise Metadata
        public string? SyncStatus { get; set; } // 'Synced', 'Local'
        public DateTime? CreatedAt { get; set; } = DateTime.UtcNow;
    }
}
