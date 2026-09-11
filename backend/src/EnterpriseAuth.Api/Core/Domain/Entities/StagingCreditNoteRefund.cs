using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    [Table("StagingCreditNoteRefunds")]
    public class StagingCreditNoteRefund
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int RefundId { get; set; }

        [MaxLength(100)]
        public string CreditNoteId { get; set; } = string.Empty;

        [ForeignKey("CreditNoteId")]
        public StagingCreditNoteHeader? Header { get; set; }

        [MaxLength(50)]
        public string Method { get; set; } = string.Empty; // CASH, CREDIT, CHEQUE

        public double Amount { get; set; }

        [MaxLength(50)]
        public string? BankCode { get; set; }

        [MaxLength(200)]
        public string? BankName { get; set; }

        [MaxLength(100)]
        public string? ChequeNumber { get; set; }

        [MaxLength(50)]
        public string? ChequeDate { get; set; }
    }
}
