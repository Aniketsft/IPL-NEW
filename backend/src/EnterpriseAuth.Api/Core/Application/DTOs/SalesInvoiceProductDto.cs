using System;

namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class SalesInvoiceProductDto
    {
        public string Sku { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public double StockQty { get; set; }
        public string Warehouse { get; set; }
        public string StockUnit { get; set; } = string.Empty;
    }
}
