namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class ProductLiveStockDto
    {
        public string ProductCode { get; set; } = string.Empty;
        public string SiteCode { get; set; } = string.Empty;
        public decimal PhysicalStock { get; set; }
        public decimal AllocatedStock { get; set; }
        public decimal LiveAvailableStock { get; set; }
    }
}
