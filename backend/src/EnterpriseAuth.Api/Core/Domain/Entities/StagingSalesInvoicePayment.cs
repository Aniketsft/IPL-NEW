using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    [Table("StagingSalesInvoicePayments")]
    public class StagingSalesInvoicePayment
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int PaymentId { get; set; }

        public int? LocalPaymentId { get; set; }

        [Required]
        [MaxLength(50)]
        public string DocumentType { get; set; } = "INVOICE"; // INVOICE or CREDIT_NOTE

        [Required]
        [MaxLength(100)]
        public string DocumentId { get; set; } = string.Empty;

        [NotMapped]
        public string InvoiceId
        {
            get => DocumentId;
            set => DocumentId = value ?? string.Empty;
        }

        [MaxLength(10)]
        public string X3DocumentType { get; set; } = "SINV"; // SINV or SCRN

        [MaxLength(10)]
        public string X3EntryType { get; set; } = "REC"; // REC or REM

        public int X3Sign { get; set; } = 2; // 2 = Receipt (In), 1 = Disbursement (Out)

        [MaxLength(100)]
        public string? X3InvoiceDocumentId { get; set; }

        [MaxLength(100)]
        public string? X3PaymentId { get; set; }

        [Required]
        [MaxLength(50)]
        public string PaymentMethod { get; set; } = string.Empty;

        [MaxLength(10)]
        public string X3PaymentMode { get; set; } = "CSH";

        [Column(TypeName = "decimal(18, 4)")]
        public decimal Amount { get; set; }

        [MaxLength(10)]
        public string Currency { get; set; } = "MUR";

        [MaxLength(50)]
        public string SalesSite { get; set; } = "POD";

        [MaxLength(100)]
        public string CustomerCode { get; set; } = string.Empty;

        [MaxLength(255)]
        public string? CustomerName { get; set; }

        [MaxLength(50)]
        public string? BankCode { get; set; }

        [MaxLength(200)]
        public string? BankName { get; set; }

        [MaxLength(100)]
        public string? ChequeNumber { get; set; }

        [MaxLength(50)]
        public string? ChequeDate { get; set; }

        [MaxLength(255)]
        public string? QrTransactionRef { get; set; }

        public bool IsProcessedByX3 { get; set; } = false;
        public int IsSynced { get; set; } = 0;
        public DateTime SyncedAt { get; set; } = DateTime.UtcNow;

        [MaxLength(50)]
        public string? CreatedAt { get; set; }

        [MaxLength(200)]
        public string? CreatedBy { get; set; }

        [MaxLength(200)]
        public string? UserName { get; set; }

        [MaxLength(255)]
        public string? DeviceId { get; set; }

        [MaxLength(100)]
        public string? SoapRequestNumber { get; set; }

        public string? SoapError { get; set; }

        // Navigation Property (optional in memory)
        [NotMapped]
        public StagingSalesInvoiceHeader? Header { get; set; }
    }
}
