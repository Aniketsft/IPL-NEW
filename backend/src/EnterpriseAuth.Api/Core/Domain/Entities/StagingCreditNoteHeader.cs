using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    [Table("StagingCreditNoteHeaders")]
    public class StagingCreditNoteHeader
    {
        [Key]
        [MaxLength(100)]
        public string CreditNoteId { get; set; } = string.Empty;

        [MaxLength(50)]
        public string CreditNoteType { get; set; } = string.Empty; // REVERSAL, STANDALONE, AMOUNT_ONLY / CASH_ONLY

        [MaxLength(50)]
        public string X3CreditNoteType { get; set; } = "CRN";

        [MaxLength(50)]
        public string SalesSite { get; set; } = string.Empty;

        [MaxLength(100)]
        public string CustomerCode { get; set; } = string.Empty;

        [MaxLength(255)]
        public string CustomerName { get; set; } = string.Empty;

        [MaxLength(10)]
        public string Currency { get; set; } = "MUR";

        public double GrandTotal { get; set; }

        [MaxLength(100)]
        public string? OriginalInvoiceId { get; set; }

        public string? LinkedInvoiceIds { get; set; } // Comma-separated or JSON list of invoice IDs

        [MaxLength(50)]
        public string SettlementType { get; set; } = string.Empty; // CASH, CREDIT, CHEQUE

        [MaxLength(100)]
        public string? Reference { get; set; }

        public int IsSynced { get; set; } = 0;

        [MaxLength(100)]
        public string? X3DocumentId { get; set; }

        [MaxLength(50)]
        public string CreatedAt { get; set; } = string.Empty;

        [MaxLength(200)]
        public string CreatedBy { get; set; } = string.Empty;

        [MaxLength(255)]
        public string? DeviceId { get; set; }

        // Backend specific audit fields
        public bool IsProcessedByX3 { get; set; } = false;
        public DateTime SyncedAt { get; set; } = DateTime.UtcNow;

        // Navigation properties
        public ICollection<StagingCreditNoteLine> Lines { get; set; } = new List<StagingCreditNoteLine>();
        public ICollection<StagingCreditNoteRefund> Refunds { get; set; } = new List<StagingCreditNoteRefund>();
    }
}
