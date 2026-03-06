namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class ProductionTrackingDto
    {
        public string SoNumber { get; set; } = string.Empty;
        public string Site { get; set; } = string.Empty;
        public string ProductCode { get; set; } = string.Empty;
        public string ProductDescription { get; set; } = string.Empty;
        public string BarcodeType { get; set; } = string.Empty;
        public decimal OrderedQuantity { get; set; }
        public decimal RemainingQuantity { get; set; }
        public decimal Manufactured { get; set; }
        public string Location { get; set; } = string.Empty;
        public string LotNumber { get; set; } = string.Empty;
    }
}
