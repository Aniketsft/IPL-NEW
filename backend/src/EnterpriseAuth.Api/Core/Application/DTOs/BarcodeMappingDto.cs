namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class BarcodeMappingDto
    {
        public string Site { get; set; } = string.Empty;
        public string Category { get; set; } = string.Empty;
        public string Product { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;
        public string Unit { get; set; } = string.Empty;
        public decimal StandardWeight { get; set; }
        public string Barcode { get; set; } = string.Empty;
        public string Location { get; set; } = string.Empty;
        public string LocationType { get; set; } = string.Empty;
        public string Warehouse { get; set; } = string.Empty;
    }
}
