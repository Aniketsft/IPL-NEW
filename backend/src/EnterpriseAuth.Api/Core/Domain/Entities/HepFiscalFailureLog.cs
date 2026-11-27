using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    /// <summary>
    /// Append-only troubleshooting log for failed/rejected HEP fiscalisation attempts.
    /// Kept separate from HepFiscalInvoices so HepFiscalInvoices contains only successful fiscalisations.
    /// </summary>
    [Table("HepFiscalFailureLogs")]
    public class HepFiscalFailureLog
    {
        [Key]
        public Guid Id { get; set; } = Guid.NewGuid();

        [Required]
        [MaxLength(100)]
        public string DocumentNo { get; set; } = string.Empty;

        [MaxLength(10)]
        public string DocumentType { get; set; } = "STD";

        [MaxLength(30)]
        public string DocumentCategory { get; set; } = "INVOICE";

        [MaxLength(64)]
        public string? DeviceId { get; set; }

        [MaxLength(100)]
        public string? ProfileId { get; set; }

        [MaxLength(20)]
        public string? SiteCode { get; set; }

        [MaxLength(100)]
        public string? UserName { get; set; }

        [MaxLength(100)]
        public string? CustomerCode { get; set; }

        [MaxLength(500)]
        public string? RequestUrl { get; set; }

        public string? RequestPayload { get; set; }
        public int? HttpStatus { get; set; }
        public string? ResponsePayload { get; set; }

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

        [MaxLength(500)]
        public string? ErrorCodes { get; set; }

        [MaxLength(2000)]
        public string? ErrorMessages { get; set; }

        [MaxLength(2000)]
        public string? ExceptionText { get; set; }

        public int DurationMs { get; set; }

        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }
}
