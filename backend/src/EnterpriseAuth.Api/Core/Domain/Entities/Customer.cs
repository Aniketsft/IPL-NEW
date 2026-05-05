using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    [Table("Customers")]
    public class Customer
    {
        [Key]
        [Column("ROWID")]
        public string? ROWID { get; set; }
        [Required]
        [MaxLength(100)]
        [Column("ZFULLBUSNAM_0")]
        public string? ZFULLBUSNAM_0 { get; set; }
        [Required]
        [MaxLength(100)]
        [Column("BPCNUM_0")]
        public string? BPCNUM_0 { get; set; }
        [Required]
        [MaxLength(100)]
        [Column("BCGCOD_0")]
        public string? BCGCOD_0 { get; set; }
        [Required]
        [MaxLength(100)]
        [Column("OSTCTL_0")]
        public string? OSTCTL_0 { get; set; }
        [Required]
        [MaxLength(100)]
        [Column("OSTAUZ_0")]
        public string? OSTAUZ_0 { get; set; }
    }
}
