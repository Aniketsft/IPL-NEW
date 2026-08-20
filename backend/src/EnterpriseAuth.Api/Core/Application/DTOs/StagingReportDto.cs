using System;

namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class StagingReportDto
    {
        public string SONumber { get; set; } = string.Empty;
        public string? Salesman { get; set; }
        public string? LorryNumber { get; set; }
        public string? LorryShortCode { get; set; }
        public string? CustomerCode { get; set; }
        public string? CustomerName { get; set; }
        public string? ItemCode { get; set; }
        public string? Description { get; set; }
        public string? LotNumber { get; set; }
        public string? Location { get; set; }
        public decimal DeliveredQty { get; set; }
        public decimal OrderedQty { get; set; }
        public decimal ProducedQty { get; set; }
        public DateTime? DeliveryDate { get; set; }
        public DateTime? ExpiryDate { get; set; }
    }
}
