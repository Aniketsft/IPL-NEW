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
        public string Lot { get; set; } = string.Empty;
        public decimal? EaQuantity { get; set; }
        public string Site { get; set; } = string.Empty;
        public string Unit { get; set; } = "KG";
        public int Soplin { get; set; }
        public bool IsPrepared { get; set; }
        public string? CustomerCode { get; set; }
        public string? CustomerName { get; set; }
        public string? Salesman { get; set; }
    }
}
