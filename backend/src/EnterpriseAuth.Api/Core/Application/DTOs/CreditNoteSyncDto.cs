using System.Collections.Generic;

namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class CreditNoteSyncDto
    {
        public string CreditNoteId { get; set; } = string.Empty;
        public string CreditNoteType { get; set; } = string.Empty; // REVERSAL, STANDALONE, AMOUNT_ONLY / CASH_ONLY
        public string X3CreditNoteType { get; set; } = "CRN";
        public string SalesSite { get; set; } = "SCG";
        public string CustomerCode { get; set; } = string.Empty;
        public string CustomerName { get; set; } = string.Empty;
        public string Currency { get; set; } = "MUR";
        public double GrandTotal { get; set; }
        public string? OriginalInvoiceId { get; set; }
        public List<string> LinkedInvoiceIds { get; set; } = new List<string>();
        public string SettlementType { get; set; } = "CASH";
        public string? Reference { get; set; }
        public string? CreatedAt { get; set; }
        public string? CreatedBy { get; set; }
        public string? UserName { get; set; }
        public string? DeviceId { get; set; }
        public string? TransactionalId { get; set; }
        public int Category { get; set; } = 2; // 1 = Invoice, 2 = Credit Note, 3 = Return
        public string? SalesRep { get; set; }
        public string? Reason { get; set; }
        public string? TransactionMode { get; set; } // "1" = Direct, "4" = Linked
        public string? DueDate { get; set; }

        public List<CreditNoteLineSyncDto> Lines { get; set; } = new List<CreditNoteLineSyncDto>();
        public List<CreditNoteRefundSyncDto> Refunds { get; set; } = new List<CreditNoteRefundSyncDto>();
    }

    public class CreditNoteLineSyncDto
    {
        public int LineNo { get; set; }
        public double Quantity { get; set; }
        public string? OriginInvoiceId { get; set; }
        public int? OriginLineNo { get; set; }
        public string? Sku { get; set; }
        public string? Name { get; set; }
        public string? SalesUnit { get; set; }
        public double? BasePrice { get; set; }
        public double? DiscountAmount { get; set; }
        public double? Discount2 { get; set; }
        public double? Discount3 { get; set; }
        public string? TaxRule { get; set; }
        public double? Total { get; set; }
        public string? LotNumber { get; set; }
        public string? Warehouse { get; set; }
        public string? Cce0 { get; set; }

        // Fallback backward-compatible standalone aliases
        public string? StandaloneSku { get => Sku; set => Sku = value; }
        public string? StandaloneName { get => Name; set => Name = value; }
        public string? StandaloneSalesUnit { get => SalesUnit; set => SalesUnit = value; }
        public double? StandalonePrice { get => BasePrice; set => BasePrice = value; }
        public string? StandaloneTaxRule { get => TaxRule; set => TaxRule = value; }
        public string? StandaloneLot { get => LotNumber; set => LotNumber = value; }
        public string? StandaloneWarehouse { get => Warehouse; set => Warehouse = value; }
        public string? StandaloneCce0 { get => Cce0; set => Cce0 = value; }
    }

    public class CreditNoteRefundSyncDto
    {
        public int? LocalRefundId { get; set; }
        public string Method { get; set; } = string.Empty;
        public double Amount { get; set; }
        public string? BankCode { get; set; }
        public string? BankName { get; set; }
        public string? ChequeNumber { get; set; }
        public string? ChequeDate { get; set; }
    }
}
