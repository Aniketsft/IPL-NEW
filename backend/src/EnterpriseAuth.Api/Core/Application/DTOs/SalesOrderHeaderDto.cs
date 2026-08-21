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
        public string Site { get; set; } = string.Empty;
        public string Salesman { get; set; } = string.Empty;
        public int Status { get; set; }
        public string Source { get; set; } = string.Empty;
        public string? TargetLorry { get; set; }
        public bool IsPreparedForShipment { get; set; }
        public bool IsProcessed { get; set; }
        public bool ExcludeFromEod { get; set; }
        public string StatusLabel => Status == 2 ? "Closed" : "Open";
        public bool HasFppProducts { get; set; }
    }
}
