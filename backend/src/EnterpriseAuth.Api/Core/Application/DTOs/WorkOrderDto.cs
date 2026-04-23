using System;

namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class WorkOrderDto
    {
        public string WorkOrder { get; set; } = string.Empty;
        public string Product { get; set; } = string.Empty;
        public decimal ReleasedQty { get; set; }
        public string Unit { get; set; } = string.Empty;
        public string TrackingNum { get; set; } = string.Empty;
        public DateTime? Date { get; set; }
        public string RecordType { get; set; } = "M";
        public string ProductionSite { get; set; } = "IPL";
        public string Conversion { get; set; } = "1";
        public string TransactionType { get; set; } = "STD";
        public string StockFlag { get; set; } = "S";
        public string StockUnit { get; set; } = string.Empty;
        public decimal StockQty { get; set; }
        public string StockConversion { get; set; } = "1";
        public string Location { get; set; } = "IPLCH";
        public string Status { get; set; } = "A";
        public string ExpirationDate { get; set; } = "20261231";
        public string LC { get; set; } = "LC";
        public string DPT { get; set; } = "DPT";
        public string PRO { get; set; } = "PRO";
        public string CUS { get; set; } = "CUS";
        public string CCE_0 { get; set; } = string.Empty;
        public string CCE_1 { get; set; } = string.Empty;
    }
}
