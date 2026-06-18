using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    [Table("StagingSalesInvoiceLines")]
    public class StagingSalesInvoiceLine
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int LineId { get; set; }

        [MaxLength(100)]
        public string InvoiceId { get; set; } = string.Empty;
        
        [ForeignKey("InvoiceId")]
        public StagingSalesInvoiceHeader? Header { get; set; }

        public int LineNo { get; set; }

        [MaxLength(100)]
        public string? Sku { get; set; }

        [MaxLength(500)]
        public string? Name { get; set; }

        public double Quantity { get; set; }
        public double BasePrice { get; set; }
        public double DiscountAmount { get; set; }
        public double VatAmount { get; set; }
        public double Total { get; set; }
    }
}
