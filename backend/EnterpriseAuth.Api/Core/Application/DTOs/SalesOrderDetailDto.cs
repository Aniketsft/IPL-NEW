namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class SalesOrderDetailDto
    {
        public string SoNumber { get; set; } = string.Empty;
        public string ProductCode { get; set; } = string.Empty;
        public string ProductDescription { get; set; } = string.Empty;
        public string BarcodeType { get; set; } = "Variable Weight";
        public decimal OrderedQuantity { get; set; }
        public decimal RemainingQuantity { get; set; }
        public decimal Manufactured { get; set; }
    }
}
