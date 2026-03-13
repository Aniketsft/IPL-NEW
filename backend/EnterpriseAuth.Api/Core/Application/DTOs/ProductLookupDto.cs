namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class ProductLookupDto
    {
        public string ProductCode { get; set; } = string.Empty;
        public string ProductDescription { get; set; } = string.Empty;
        public string StockUnit { get; set; } = string.Empty;
        public string SalesUnit { get; set; } = string.Empty;
    }
}
