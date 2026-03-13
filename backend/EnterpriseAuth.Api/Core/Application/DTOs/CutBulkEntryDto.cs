using System;

namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class CutBulkEntryDto
    {
        public string? EntryNumber { get; set; }
        public string Type { get; set; } = string.Empty;
        public string? CustomerCode { get; set; }
        public string? CustomerName { get; set; }
        public DateTime? Date { get; set; }
        public string? PoNumber { get; set; }
        public string? ItemCode { get; set; }
        public string? ProductName { get; set; }
        public string? Salesman1Code { get; set; }
        public string? Salesman2Code { get; set; }
        public decimal AmountKg { get; set; }
        public decimal ManufacturedQuantity { get; set; }
        public decimal RemainingQuantity { get; set; }
        public string? ExistingSoNumber { get; set; }
    }
}
