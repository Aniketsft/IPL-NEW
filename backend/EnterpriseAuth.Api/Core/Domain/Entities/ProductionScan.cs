using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    [Table("ProductionScans")]
    public class ProductionScan
    {
        [Key]
        public int ScanId { get; set; }

        [Required]
        [MaxLength(100)]
        public string ProductId { get; set; } = string.Empty;

        [MaxLength(255)]
        public string ProductDescription { get; set; } = string.Empty;

        [Required]
        [Column(TypeName = "decimal(18,2)")]
        public decimal ScanAmountKg { get; set; }

        [Required]
        [MaxLength(100)]
        public string SoNumber { get; set; } = string.Empty;

        [MaxLength(100)]
        public string CustomerId { get; set; } = string.Empty;

        [MaxLength(255)]
        public string CustomerDescription { get; set; } = string.Empty;

        [Required]
        [MaxLength(1)]
        public string Status { get; set; } = "Q"; // Q, A, or R

        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }
}
