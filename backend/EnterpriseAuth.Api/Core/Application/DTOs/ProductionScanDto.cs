using System;
using System.ComponentModel.DataAnnotations;

namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class ProductionScanDto
    {
        public int? ScanId { get; set; }
        
        [Required]
        public string ProductId { get; set; } = string.Empty;
        
        [Required]
        public string ProductDescription { get; set; } = string.Empty;
        
        [Required]
        public decimal ScanAmountKg { get; set; }
        
        [Required]
        public string SoNumber { get; set; } = string.Empty;
        
        [Required]
        public string CustomerId { get; set; } = string.Empty;
        
        [Required]
        public string CustomerDescription { get; set; } = string.Empty;
        
        [Required]
        [MaxLength(1)]
        public string Status { get; set; } = "Q"; // Q, A, or R
        
        public DateTime? CreatedAt { get; set; }
    }
}
