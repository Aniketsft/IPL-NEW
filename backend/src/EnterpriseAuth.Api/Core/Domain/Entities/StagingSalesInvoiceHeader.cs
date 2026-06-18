using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    [Table("StagingSalesInvoiceHeaders")]
    public class StagingSalesInvoiceHeader
    {
        [Key]
        [MaxLength(100)]
        public string InvoiceId { get; set; } = string.Empty;

        [MaxLength(50)]
        public string? SalesSite { get; set; }

        [MaxLength(100)]
        public string? CustomerCode { get; set; }

        [MaxLength(100)]
        public string? SalesRep { get; set; }

        [MaxLength(50)]
        public string? PricingRule { get; set; }

        [MaxLength(50)]
        public string? DueDate { get; set; }

        [MaxLength(200)]
        public string? UserName { get; set; }

        public int IsSynced { get; set; }

        [MaxLength(50)]
        public string? CreatedAt { get; set; }

        [MaxLength(200)]
        public string? CreatedBy { get; set; }

        [MaxLength(255)]
        public string? DeviceId { get; set; }

        // Backend specific fields
        public bool IsProcessedByX3 { get; set; } = false;
        public DateTime SyncedAt { get; set; } = DateTime.UtcNow;

        // Navigation property
        public ICollection<StagingSalesInvoiceLine> Lines { get; set; } = new List<StagingSalesInvoiceLine>();
    }
}
