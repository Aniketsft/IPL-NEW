using System.Collections.Generic;

namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class SalesInvoiceSyncDto
    {
        public string InvoiceId { get; set; } = string.Empty;
        public string? SalesSite { get; set; }
        public string? CustomerCode { get; set; }
        public string? SalesRep { get; set; }
        public string? PricingRule { get; set; }
        public string? CreatedAt { get; set; }
        public string? DeviceId { get; set; }
        public string? CreatedBy { get; set; }
        public string? DueDate { get; set; }
        public string? UserName { get; set; }
        public string? Reference { get; set; }
        public string InvoiceType { get; set; } = "STD";
        public string? TransactionalId { get; set; }

        public List<SalesInvoiceLineDto> Lines { get; set; } = new List<SalesInvoiceLineDto>();
    }

    public class SalesInvoiceLineDto
    {
        public int LineNo { get; set; }
        public string? Sku { get; set; }
        public string? Name { get; set; }
        public double Quantity { get; set; }
        public double BasePrice { get; set; }
        public double DiscountAmount { get; set; }
        public double VatAmount { get; set; }
        public double Total { get; set; }
        public string? LotNumber { get; set; }
        public string? Warehouse { get; set; }
        public string? SalesUnit { get; set; }
        public string? Cce0 { get; set; }
        public string? TaxRule { get; set; }
    }
}
