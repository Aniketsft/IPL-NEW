using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    [Table("production_scan")]
    public class ProductionScan
    {
        [Key]
        [Column("scan_id")]
        public int ScanId { get; set; }

        [Required]
        [MaxLength(100)]
        [Column("product_id")]
        public string ItemCode { get; set; } = string.Empty;

        [Required]
        [Column("line_no")]
        public int LineNo { get; set; }

        [Required]
        [Column("scan_amount_kg", TypeName = "decimal(18,2)")]
        public decimal ScanAmountKg { get; set; }

        [Required]
        [MaxLength(100)]
        [Column("so_number")]
        public string SoNumber { get; set; } = string.Empty;

        [MaxLength(10)]
        [Column("order_status")]
        public string? OrderStatus { get; set; }

        [MaxLength(10)]
        [Column("item_status")]
        public string? ItemStatus { get; set; }

        [MaxLength(100)]
        [Column("location")]
        public string? Location { get; set; }

        [MaxLength(100)]
        [Column("lot")]
        public string? Lot { get; set; }

        [MaxLength(100)]
        [Column("created_by")]
        public string? CreatedBy { get; set; }

        [Column("created_at")]
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        [MaxLength(100)]
        [Column("updated_by")]
        public string? UpdatedBy { get; set; }

        [Column("updated_at")]
        public DateTime? UpdatedAt { get; set; }

        [Column("is_deleted")]
        public bool IsDeleted { get; set; }

        [MaxLength(100)]
        [Column("deleted_by")]
        public string? DeletedBy { get; set; }

        [Column("deleted_at")]
        public DateTime? DeletedAt { get; set; }
    }
}
