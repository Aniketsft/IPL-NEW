using System.Collections.Generic;

namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class SalesInvoiceSyncDto
    {
        public string InvoiceId { get; set; } = string.Empty;
        public string SalesSite { get; set; } = string.Empty;
        public string CustomerCode { get; set; } = string.Empty;
        public string PricingRule { get; set; } = string.Empty;
        public string DueDate { get; set; } = string.Empty;
        public string CreatedAt { get; set; } = string.Empty;

        public List<SalesInvoiceSyncLineDto> Lines { get; set; } = new List<SalesInvoiceSyncLineDto>();
    }

    public class SalesInvoiceSyncLineDto
    {
        public string Sku { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public int LineNo { get; set; }
        public decimal Quantity { get; set; }
        public decimal BasePrice { get; set; }
        public decimal DiscountAmount { get; set; }
        public decimal VatAmount { get; set; }
    }
}
