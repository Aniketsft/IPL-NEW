using System;
using System.ComponentModel.DataAnnotations;

namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class ProductionScanDto
    {
        public int? ScanId { get; set; }
        
        [Required]
        public string ItemCode { get; set; } = string.Empty;
        
        [Required]
        public int LineNo { get; set; }
        
        [Required]
        public decimal ScanAmountKg { get; set; }
        
        [Required]
        public string SoNumber { get; set; } = string.Empty;
        
        public string? OrderStatus { get; set; }
        
        public string? ItemStatus { get; set; }
        
        public string? Location { get; set; }
        
        public string? Lot { get; set; }

        public string? CreatedBy { get; set; }
        
        public DateTime? CreatedAt { get; set; }
    }
}
