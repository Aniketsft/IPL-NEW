using System;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    public class Excess
    {
        public Guid Id { get; set; } = Guid.NewGuid();
        
        /// <summary>
        /// Source bulk sales order number (e.g. BLK-20261015, CUTS-20261015)
        /// </summary>
        public string SourceBulkSoNumber { get; set; }
        
        public string ItemCode { get; set; }
        
        public DateTime DeliveryDate { get; set; }
        
        public decimal TotalManufacturedQuantity { get; set; }
        
        public decimal AllocatedQuantity { get; set; }
        
        public decimal RemainingExcess { get; set; }
        
        public string? CustomerCode { get; set; }
        public string? Salesman { get; set; }
        
        public bool ExcludeFromEod { get; set; }
        
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
        public string CreatedBy { get; set; }
        
        public DateTime? UpdatedAt { get; set; }
        public string UpdatedBy { get; set; }
    }
}
