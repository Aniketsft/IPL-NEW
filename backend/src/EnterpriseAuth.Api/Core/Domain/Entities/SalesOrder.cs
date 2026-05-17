using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    [Table("SalesOrders")]
    public class SalesOrder
    {
        [Key]
        [Column("Id")]
        public Guid Id { get; set; } = Guid.NewGuid();

        [Required]
        [MaxLength(100)]
        [Column("SourceOrderId")]
        public string SourceOrderId { get; set; } = string.Empty; // SOHNUM or Internal EntryNo

        [Required]
        [MaxLength(20)]
        [Column("SourceSystem")]
        public string SourceSystem { get; set; } = "X3"; // 'X3', 'Internal'

        [MaxLength(100)]
        [Column("PoNumber")]
        public string? PoNumber { get; set; }

        [Column("OrderDate")]
        public DateTime? OrderDate { get; set; }

        [Column("DeliveryDate")]
        public DateTime? DeliveryDate { get; set; }

        [MaxLength(200)]
        [Column("Salesman")]
        public string? Salesman { get; set; }

        [MaxLength(100)]
        [Column("CustomerCode")]
        public string? CustomerCode { get; set; }

        [MaxLength(255)]
        [Column("CustomerName")]
        public string? CustomerName { get; set; }

        [MaxLength(100)]
        [Column("Site")]
        public string? Site { get; set; }

        [Column("Status")]
        public int Status { get; set; } // 1: Open, 2: Closed

        [Column("IsArchived")]
        public bool IsArchived { get; set; }

        [Column("CreatedAt")]
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        [Column("UpdatedAt")]
        public DateTime? UpdatedAt { get; set; }

        [Column("IsProcessed")]
        public bool IsProcessed { get; set; }

        // Navigation
        public ICollection<SalesOrderLine> Lines { get; set; } = new List<SalesOrderLine>();
    }
}
