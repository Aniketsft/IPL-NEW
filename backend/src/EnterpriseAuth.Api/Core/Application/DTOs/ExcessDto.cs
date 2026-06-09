using System;

namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class ExcessDto
    {
        public Guid Id { get; set; }
        public string SourceBulkSoNumber { get; set; }
        public string ItemCode { get; set; }
        public DateTime DeliveryDate { get; set; }
        public decimal TotalManufacturedQuantity { get; set; }
        public decimal AllocatedQuantity { get; set; }
        public decimal RemainingExcess { get; set; }
    }

    public class AllocateExcessDto
    {
        /// <summary>
        /// The bulk order to draw from (e.g. BLK-20261015)
        /// </summary>
        public string SourceBulkSoNumber { get; set; }

        /// <summary>
        /// The real target Sales Order to allocate into
        /// </summary>
        public string TargetSoNumber { get; set; }
        
        public string ItemCode { get; set; }
        
        /// <summary>
        /// The amount in KG to allocate from the bulk pool
        /// </summary>
        public decimal AllocateAmountKg { get; set; }
        
        public string AllocatedBy { get; set; }
    }
}
