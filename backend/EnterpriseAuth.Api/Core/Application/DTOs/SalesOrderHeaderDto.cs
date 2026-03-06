using System;

namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class SalesOrderHeaderDto
    {
        public string SohNum { get; set; } = string.Empty;
        public string PoNo { get; set; } = string.Empty;
        public DateTime? OrderDate { get; set; }
        public DateTime? DeliveryDate { get; set; }
        public string CustomerCode { get; set; } = string.Empty;
        public string CustomerName { get; set; } = string.Empty;
        public string Rep0 { get; set; } = string.Empty;
        public string Rep1 { get; set; } = string.Empty;
        public int Status { get; set; }
        public string StatusLabel => Status == 4 ? "Closed" : "Open";
    }
}
