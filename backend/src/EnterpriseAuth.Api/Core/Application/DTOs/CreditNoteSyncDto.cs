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
        public string? DeviceId { get; set; }

        public List<CreditNoteLineSyncDto> Lines { get; set; } = new List<CreditNoteLineSyncDto>();
        public List<CreditNoteRefundSyncDto> Refunds { get; set; } = new List<CreditNoteRefundSyncDto>();
    }

    public class CreditNoteLineSyncDto
    {
        public int LineNo { get; set; }
        public double Quantity { get; set; }
        public string? OriginInvoiceId { get; set; }
        public int? OriginLineNo { get; set; }
        public string? StandaloneSku { get; set; }
        public string? StandaloneName { get; set; }
        public string? StandaloneSalesUnit { get; set; }
        public double? StandalonePrice { get; set; }
        public string? StandaloneTaxRule { get; set; }
        public string? StandaloneLot { get; set; }
        public string? StandaloneWarehouse { get; set; }
        public string? StandaloneCce0 { get; set; }
    }

    public class CreditNoteRefundSyncDto
    {
        public string Method { get; set; } = string.Empty;
        public double Amount { get; set; }
        public string? BankCode { get; set; }
        public string? BankName { get; set; }
        public string? ChequeNumber { get; set; }
        public string? ChequeDate { get; set; }
    }
}
