using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    [Table("SalesOrderLines")]
    public class SalesOrderLine
    {
        [Key]
        [Column("Id")]
        public Guid Id { get; set; } = Guid.NewGuid();

        [Required]
        [Column("SalesOrderId")]
        public Guid SalesOrderId { get; set; }

        [Required]
        [MaxLength(100)]
        [Column("ItemCode")]
        public string ItemCode { get; set; } = string.Empty;

        [MaxLength(255)]
        [Column("Description")]
        public string? Description { get; set; }

        [Column("OrderedQuantity")]
        public decimal OrderedQuantity { get; set; }

        [MaxLength(50)]
        [Column("Unit")]
        public string? Unit { get; set; }

        [MaxLength(100)]
        [Column("Location")]
        public string? TargetLocation { get; set; }

        [MaxLength(100)]
        [Column("Lot")]
        public string? TargetLot { get; set; }

        [Column("LineNumber")]
        public int LineNumber { get; set; }

        [Column("LineStatus")]
        public int LineStatus { get; set; } // 1: Pending, 2: InProgress, 3: Completed

        [Column("CreatedAt")]
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        // Navigation
        [ForeignKey("SalesOrderId")]
        public SalesOrder Order { get; set; } = null!;
    }
}
