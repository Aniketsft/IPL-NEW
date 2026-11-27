using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    /// <summary>
    /// Stores successfully fiscalised HEP documents (invoices, credit notes, returns)
    /// including full posted details, HEP/MRA response metadata, IRN, and Base64 QR.
    /// Rows are inserted ONLY when HEP fiscalisation succeeds.
    /// </summary>
    [Table("HepFiscalInvoices")]
    public class HepFiscalInvoice
    {
        [Key]
        public Guid Id { get; set; } = Guid.NewGuid();

        [Required]
        [MaxLength(100)]
        public string DocumentNo { get; set; } = string.Empty;

        [Required]
        [MaxLength(10)]
        public string DocumentType { get; set; } = "STD";

        [Required]
        [MaxLength(30)]
        public string DocumentCategory { get; set; } = "INVOICE";

        [MaxLength(100)]
        public string? RefDocumentNo { get; set; }

        [MaxLength(255)]
        public string? Reason { get; set; }

        public bool IsFiscalised { get; set; } = true;

        public DateTime FiscalisedAt { get; set; } = DateTime.UtcNow;

        [MaxLength(64)]
        public string? DeviceId { get; set; }

        [MaxLength(100)]
        public string? ProfileId { get; set; }

        [MaxLength(20)]
        public string? EbsCounterNo { get; set; }

        [MaxLength(20)]
        public string? SiteCode { get; set; }

        [MaxLength(100)]
        public string? UserName { get; set; }

        [MaxLength(100)]
        public string? CustomerCode { get; set; }

        [MaxLength(255)]
        public string? CustomerName { get; set; }

        [MaxLength(50)]
        public string? BuyerTan { get; set; }

        [MaxLength(50)]
        public string? BuyerBrn { get; set; }

        [MaxLength(50)]
        public string? BuyerNic { get; set; }

        [MaxLength(50)]
        public string? BuyerType { get; set; }

        [MaxLength(50)]
        public string? PersonType { get; set; }

        [MaxLength(500)]
        public string? BuyerAddress { get; set; }

        [MaxLength(10)]
        public string? TransactionType { get; set; }

        [MaxLength(20)]
        public string? SalesTransactions { get; set; }

        [MaxLength(10)]
        public string? Currency { get; set; }

        [MaxLength(30)]
        public string? InvoiceDate { get; set; }

        public decimal TotalAmtWoVatCur { get; set; }
        public decimal TotalAmtWoVatMur { get; set; }
        public decimal TotalVatAmount { get; set; }
        public decimal InvoiceTotal { get; set; }
        public decimal DiscountTotal { get; set; }
        public decimal TotalAmountPaid { get; set; }
        public int LineCount { get; set; }

        [MaxLength(500)]
        public string? RequestUrl { get; set; }

        public string? RequestPayload { get; set; }
        public string? ResponsePayload { get; set; }
        public int? HttpStatus { get; set; }

        [MaxLength(100)]
        public string? HepId { get; set; }

        [MaxLength(50)]
        public string? HepStatus { get; set; }

        [MaxLength(500)]
        public string? HepStatusMessage { get; set; }

        [MaxLength(50)]
        public string? MraStatus { get; set; }

        [MaxLength(100)]
        public string? MraRequestId { get; set; }

        [MaxLength(100)]
        public string? MraResponseId { get; set; }

        [MaxLength(30)]
        public string? MraEnvironment { get; set; }

        [MaxLength(50)]
        public string? MraResponseDateTime { get; set; }

        [MaxLength(200)]
        public string? Irn { get; set; }

        public string? QrBase64 { get; set; }

        public bool X3Synced { get; set; } = false;

        [MaxLength(100)]
        public string? X3DocumentId { get; set; }

        public DateTime? X3SyncedAt { get; set; }
    }
}
