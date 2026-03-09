namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class ProductionTrackingDto
    {
        public string SoNumber { get; set; } = string.Empty;
        public string Site { get; set; } = string.Empty;
        public string ItemCode { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;
        public string BarcodeType { get; set; } = string.Empty;
        public decimal Quantity { get; set; }
        public decimal Remaining { get; set; }
        public decimal Manufactured { get; set; }
        public string Location { get; set; } = string.Empty;
        public string LocationName { get; set; } = string.Empty;
        public string Warehouse { get; set; } = string.Empty;
        public string WarehouseName { get; set; } = string.Empty;
        public string LocationType { get; set; } = string.Empty;
        public string LocationTypeName { get; set; } = string.Empty;
        public string Lot { get; set; } = string.Empty;
    }
}
