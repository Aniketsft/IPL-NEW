using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    [Table("Invoices")]
    public class Invoice
    {
        [Key]
        [Column("ROWID")]
        public long ROWID { get; set; }
        [Required]
        [MaxLength(100)]
        [Column("SALFCY_0")]
        public string? SALFCY_0 { get; set; }
        [Required]
        [MaxLength(100)]
        [Column("SALPRITYP_0")]
        public string? SALPRITYP_0 { get; set; }
        [Required]
        [Column("NUM_0")]
        public long? NUM_0 { get; set; }
        [Required]
        [MaxLength(100)]
        [Column("INVTYP_0")]
        public string? INVTYP_0 { get; set; }
        [Required]
        [MaxLength(100)]
        [Column("SALFCY_0")]
        public string? INVREF_0 { get; set; }
        [Required]
        [Column("ACCDAT_0")]
        public DateTime? ACCDAT_0 { get; set; }
        [Required]
        [MaxLength(100)]
        [Column("BPCINV_0")]
        public string? BPCINV_0 { get; set; }
        [Required]
        [MaxLength(100)]
        [Column("CUR_0")]
        public string? CUR_0 { get; set; }
        [Required]
        [MaxLength(100)]
        [Column("REP_0")]
        public string? REP_0 { get; set; }
        [Required]
        [Column("SIHORINUM_0")]
        public long? SIHORINUM_0 { get; set; }
        [Required]
        [MaxLength(100)]
        [Column("SIHORI_0")]
        public string? SIHORI_0 { get; set; }
        [Required]
        [MaxLength(100)]
        [Column("STOMVTFLG_0")]
        public string? STOMVTFLG_0 { get; set; }
        [Required]
        [MaxLength(100)]
        [Column("STOFCY_0")]
        public string? STOFCY_0 { get; set; }
        [Required]
        [Column("INVDTAAMT_0")]
        public decimal? INVDTAAMT_0 { get; set; }
        [Required]
        [Column("INVDTAAMT_1")]
        public decimal? INVDTAAMT_1 { get; set; }
    }
}
