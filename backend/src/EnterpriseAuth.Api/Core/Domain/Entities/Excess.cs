using System;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    public class Excess
    {
        public Guid Id { get; set; } = Guid.NewGuid();
        
        /// <summary>
        /// Source bulk sales order number (e.g. BLK-20261015, CUTS-20261015)
        /// </summary>
        public string SourceBulkSoNumber { get; set; } = string.Empty;
        
        public string ItemCode { get; set; } = string.Empty;
        
        public DateTime DeliveryDate { get; set; }
        
        public decimal TotalManufacturedQuantity { get; set; }
        
        public decimal AllocatedQuantity { get; set; }
        
        public decimal RemainingExcess { get; set; }
        
        public string? CustomerCode { get; set; }
        public string? Salesman { get; set; }
        
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
        public string CreatedBy { get; set; } = string.Empty;
        
        public DateTime? UpdatedAt { get; set; }
        public string UpdatedBy { get; set; } = string.Empty;
    }
}
