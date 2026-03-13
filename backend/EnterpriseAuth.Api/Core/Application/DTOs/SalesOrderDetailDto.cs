namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class SalesOrderDetailDto
    {
        public string SoNumber { get; set; } = string.Empty;
        public string ItemCode { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;
        public string BarcodeType { get; set; } = "Variable Weight";
        public decimal? Quantity { get; set; }
        public decimal Remaining { get; set; }
        public decimal Manufactured { get; set; }
    }
}
