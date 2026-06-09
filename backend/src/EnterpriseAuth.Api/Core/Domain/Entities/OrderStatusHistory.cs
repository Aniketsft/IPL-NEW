using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    [Table("OrderStatusHistory")]
    public class OrderStatusHistory
    {
        [Key]
        [Column("Id")]
        public int Id { get; set; }

        [Required]
        [MaxLength(100)]
        [Column("SoNumber")]
        public string SoNumber { get; set; } = string.Empty;

        [Column("Status")]
        public int Status { get; set; } // 2 = Closed

        [MaxLength(100)]
        [Column("ChangedBy")]
        public string? ChangedBy { get; set; }

        [Column("ChangedAt")]
        public DateTime ChangedAt { get; set; } = DateTime.UtcNow;
    }
}
