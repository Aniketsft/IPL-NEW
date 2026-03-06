using System;

namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class ScanDto
    {
        public string SoNumber { get; set; } = string.Empty;
        public string ProductCode { get; set; } = string.Empty;
        public decimal Quantity { get; set; }
        public DateTime ScanTimestamp { get; set; }
    }
}
