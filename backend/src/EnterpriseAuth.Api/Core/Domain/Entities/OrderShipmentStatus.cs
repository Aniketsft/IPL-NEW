using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    [Table("OrderShipmentStatus")]
    public class OrderShipmentStatus
    {
        [Key]
        [Column("Id")]
        public int Id { get; set; }

        [Required]
        [MaxLength(100)]
        [Column("SoNumber")]
        public string SoNumber { get; set; } = string.Empty;

        [Column("IsPreparedForShipment")]
        public bool IsPreparedForShipment { get; set; }

        [Column("IsValidated")]
        public bool IsValidated { get; set; }

        [MaxLength(100)]
        [Column("UpdatedBy")]
        public string? UpdatedBy { get; set; }

        [Column("UpdatedAt")]
        public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    }
}
