namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class ProductionTrackingDto
    {
        public string ItemCode { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;
        public decimal Quantity { get; set; }
    }
}
