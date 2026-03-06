namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class LotLookupDto
    {
        public string LotNumber { get; set; } = string.Empty;
        public string? LotDescription { get; set; }
        public decimal StockQuantity { get; set; }
    }
}
