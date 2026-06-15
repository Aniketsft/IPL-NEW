namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class SalesInvoiceItemStockDto
    {
        public string ItemCode { get; set; }
        public string LotNumber { get; set; }
        public string Warehouse { get; set; }
        public string Location { get; set; }
        public string LocationType { get; set; }
        public string WarehouseName { get; set; }
        public string ItemName { get; set; }
        public double TotalQty { get; set; }
    }
}
