using System.Collections.Generic;

namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class SalesInvoiceSyncDto
    {
        public string InvoiceId { get; set; } = string.Empty;
        public string? SalesSite { get; set; }
        public string? CustomerCode { get; set; }
        public string? SalesRep { get; set; }
        public string? PricingRule { get; set; }
        public string? CreatedAt { get; set; }
        public string? DeviceId { get; set; }
        public string? CreatedBy { get; set; }
        public string? DueDate { get; set; }
        public string? UserName { get; set; }
        public string? Reference { get; set; }
        public string InvoiceType { get; set; } = "STD";
        public string? TransactionalId { get; set; }
        public string? PaymentTerm { get; set; }

        public List<SalesInvoiceLineDto> Lines { get; set; } = new List<SalesInvoiceLineDto>();
        public List<SalesInvoicePaymentSyncDto> Payments { get; set; } = new List<SalesInvoicePaymentSyncDto>();
    }

    public class SalesInvoicePaymentSyncDto
    {
        public int? LocalPaymentId { get; set; }
        public string Method { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public string? BankCode { get; set; }
        public string? BankName { get; set; }
        public string? ChequeNumber { get; set; }
        public string? ChequeDate { get; set; }
        public string? QrTransactionRef { get; set; }
        public string? DocumentType { get; set; }
        public string? DocumentId { get; set; }
        public string? X3InvoiceDocumentId { get; set; }
        public string? SalesSite { get; set; }
        public string? CustomerCode { get; set; }
        public string? CustomerName { get; set; }
    }

    public class SalesInvoiceLineDto
    {
        public int LineNo { get; set; }
        public string? Sku { get; set; }
        public string? Name { get; set; }
        public double Quantity { get; set; }
        public double BasePrice { get; set; }
        public double DiscountAmount { get; set; }
        public double DiscountAmountFlat { get; set; }
        public double Discount2 { get; set; }
        public double Discount3 { get; set; }
        public double VatAmount { get; set; }
        public double Total { get; set; }
        public string? LotNumber { get; set; }
        public string? Warehouse { get; set; }
        public string? Location { get; set; }
        public string? SalesUnit { get; set; }
        public string? Cce0 { get; set; }
        public string? TaxRule { get; set; }
    }
}
