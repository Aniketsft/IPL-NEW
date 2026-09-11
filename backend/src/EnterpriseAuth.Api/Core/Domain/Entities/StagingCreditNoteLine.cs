using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    [Table("StagingCreditNoteLines")]
    public class StagingCreditNoteLine
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int LineId { get; set; }

        [MaxLength(100)]
        public string CreditNoteId { get; set; } = string.Empty;

        [ForeignKey("CreditNoteId")]
        public StagingCreditNoteHeader? Header { get; set; }

        public int LineNo { get; set; }
        public double Quantity { get; set; }

        // Lean references for REVERSAL and CASH_ONLY
        [MaxLength(100)]
        public string? OriginInvoiceId { get; set; }
        public int? OriginLineNo { get; set; }

        // Standalone product details (for STANDALONE returns)
        [MaxLength(100)]
        public string? StandaloneSku { get; set; }

        [MaxLength(500)]
        public string? StandaloneName { get; set; }

        [MaxLength(20)]
        public string? StandaloneSalesUnit { get; set; }

        public double? StandalonePrice { get; set; }

        [MaxLength(20)]
        public string? StandaloneTaxRule { get; set; }

        [MaxLength(100)]
        public string? StandaloneLot { get; set; }

        [MaxLength(50)]
        public string? StandaloneWarehouse { get; set; }

        [MaxLength(50)]
        public string? StandaloneCce0 { get; set; }
    }
}
