using System;

namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class CutBulkEntryDto
    {
        public string? EntryNumber { get; set; }
        public string Type { get; set; } = string.Empty;
        public string CustomerCode { get; set; } = string.Empty;
        public string CustomerName { get; set; } = string.Empty;
        public DateTime Date { get; set; }
        public string? PoNumber { get; set; }
        public string? Salesman1Code { get; set; }
        public string? Salesman2Code { get; set; }
        public decimal AmountKg { get; set; }
    }
}
