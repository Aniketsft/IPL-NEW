using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    [Table("SalesInvoiceCustomers")]
    public class SalesInvoiceCustomer
    {
        [Key]
        [MaxLength(100)]
        [Column("Code")]
        public string Code { get; set; } = string.Empty;

        [Required]
        [MaxLength(255)]
        [Column("Name")]
        public string Name { get; set; } = string.Empty;

        [MaxLength(50)]
        [Column("PaymentTerm")]
        public string? PaymentTerm { get; set; }

        [Column("CreditLimit", TypeName = "decimal(18,2)")]
        public decimal? CreditLimit { get; set; }

        [Column("StatusFlag")]
        public int StatusFlag { get; set; }

        [Column("IsProcessed")]
        public bool IsProcessed { get; set; }

        [Column("CreatedAt")]
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        [Column("UpdatedAt")]
        public DateTime? UpdatedAt { get; set; }
    }
}
