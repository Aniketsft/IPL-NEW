using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    [Table("Staging")]
    public class Staging
    {
        [Key]
        [Column("Id")]
        public int Id { get; set; }

        [Required]
        [MaxLength(1)]
        [Column("ZREC_0")]
        public string ZREC_0 { get; set; } = "L";

        [Required]
        [MaxLength(5)]
        [Column("ZSDHTYP_0")]
        public string ZSDHTYP_0 { get; set; } = "SDH";

        [MaxLength(5)]
        [Column("ZSALFCY_0")]
        public string? ZSALFCY_0 { get; set; }

        [Required]
        [MaxLength(5)]
        [Column("ZSTOFCY_0")]
        public string ZSTOFCY_0 { get; set; } = "IPL";

        [MaxLength(20)]
        [Column("ZSDHNUM_0")]
        public string? ZSDHNUM_0 { get; set; }

        [MaxLength(20)]
        [Column("ZBPCORD_0")]
        public string? ZBPCORD_0 { get; set; }

        [Required]
        [MaxLength(5)]
        [Column("ZSUR_0")]
        public string ZSUR_0 { get; set; } = "MUR";

        [Column("ZSHIDAT_0")]
        public DateTime? ZSHIDAT_0 { get; set; }

        [Column("ZDLVDAT_0")]
        public DateTime? ZDLVDAT_0 { get; set; }

        [Column("ZCFMFLG_0")]
        public int ZCFMFLG_0 { get; set; } = 2;

        [MaxLength(100)]
        [Column("ZLOCFCY_0")]
        public string? ZLOCFCY_0 { get; set; }

        [MaxLength(10)]
        [Column("ZLORSHORT_0")]
        public string? ZLORSHORT_0 { get; set; }

        [MaxLength(100)]
        [Column("ZLOC_0")]
        public string? ZLOC_0 { get; set; }

        [Required]
        [MaxLength(20)]
        [Column("ZSOHNUM_0")]
        public string ZSOHNUM_0 { get; set; } = string.Empty;

        [Column("ZSOPLIN_0")]
        public int ZSOPLIN_0 { get; set; }

        [MaxLength(50)]
        [Column("ZITMREF_0")]
        public string? ZITMREF_0 { get; set; }

        [MaxLength(255)]
        [Column("ZITMDES_0")]
        public string? ZITMDES_0 { get; set; }

        [MaxLength(10)]
        [Column("ZSAU_0")]
        public string? ZSAU_0 { get; set; }

        [Column("ZQTY_0")]
        public decimal ZQTY_0 { get; set; }

        [Column("CreatedAt")]
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        [Column("IsProcessed")]
        public bool IsProcessed { get; set; }

        [MaxLength(50)]
        [Column("ZVACITM_0")]
        public string? ZVACITM_0 { get; set; }

        [MaxLength(100)]
        [Column("LotNumber")]
        public string? LotNumber { get; set; }
    }
}
