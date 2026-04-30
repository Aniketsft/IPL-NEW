using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    [Table("ProductionScanTransactions")]
    public class ProductionScanTransaction
    {
        [Key]
        [Column("Id")]
        public Guid Id { get; set; } = Guid.NewGuid();

        [Required]
        [Column("SalesOrderLineId")]
        public Guid SalesOrderLineId { get; set; }

        [Column("ScanAmountKg")]
        public decimal ScanAmountKg { get; set; }
        
        [Column("EaQuantity")]
        public decimal? EaQuantity { get; set; }

        [MaxLength(100)]
        [Column("Barcode")]
        public string? Barcode { get; set; }

        [MaxLength(100)]
        [Column("LotNumber")]
        public string? LotNumber { get; set; }

        [MaxLength(100)]
        [Column("Location")]
        public string? Location { get; set; }

        [Required]
        [MaxLength(100)]
        [Column("SyncId")]
        public string SyncId { get; set; } = string.Empty;

        [MaxLength(100)]
        [Column("ItemStatus")]
        public string? ItemStatus { get; set; } // 'A', 'Q', etc.

        [MaxLength(100)]
        [Column("DeviceId")]
        public string? DeviceId { get; set; }

        [MaxLength(100)]
        [Column("CreatedBy")]
        public string? CreatedBy { get; set; }

        [Column("CreatedAt")]
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        [Column("IsDeleted")]
        public bool IsDeleted { get; set; }

        [Column("IsArchived")]
        public bool IsArchived { get; set; }

        // Navigation
        [ForeignKey("SalesOrderLineId")]
        public SalesOrderLine OrderLine { get; set; } = null!;
    }
}
