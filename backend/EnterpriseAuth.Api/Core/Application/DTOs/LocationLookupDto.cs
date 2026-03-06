namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class LocationLookupDto
    {
        public string Site { get; set; } = string.Empty;
        public string Location { get; set; } = string.Empty;
        public string Warehouse { get; set; } = string.Empty;
        public string WarehouseName { get; set; } = string.Empty;
        public string LocationType { get; set; } = string.Empty;
        public string LocationTypeName { get; set; } = string.Empty;
    }
}
