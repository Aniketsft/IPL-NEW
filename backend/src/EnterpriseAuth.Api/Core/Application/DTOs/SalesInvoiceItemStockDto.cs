namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class SalesInvoiceItemStockDto
    {
        public string ItemCode { get; set; } = string.Empty;
        public string LotNumber { get; set; } = string.Empty;
        public string Warehouse { get; set; } = string.Empty;
        public string Location { get; set; } = string.Empty;
        public string LocationType { get; set; } = string.Empty;
        public string WarehouseName { get; set; } = string.Empty;
        public string ItemName { get; set; } = string.Empty;
        public double TotalQty { get; set; }
        public string TaxLevel { get; set; } = string.Empty;
        public string Cce0 { get; set; } = string.Empty;
        public string SalesUnit { get; set; } = string.Empty;
        public string Barcode { get; set; } = string.Empty;
        public string SiteCode { get; set; } = string.Empty;
    }
}
