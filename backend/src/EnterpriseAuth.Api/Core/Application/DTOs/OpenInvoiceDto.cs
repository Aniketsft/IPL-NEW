using System;
using System.Collections.Generic;

namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class OpenInvoiceDto
    {
        public string CustomerNo { get; set; } = string.Empty;
        public string CustomerName { get; set; } = string.Empty;
        public string DocumentNo { get; set; } = string.Empty;
        public DateTime? DueDate { get; set; }
        public string Site { get; set; } = string.Empty;
        public string Company { get; set; } = string.Empty;
        public string DocType { get; set; } = "INV"; // "INV" or "CN"
        public decimal RemainingAmtLCY { get; set; }
    }

    public class OpenInvoicePaymentSyncDto
    {
        public string PaymentId { get; set; } = string.Empty;
        public string DocumentNo { get; set; } = string.Empty;
        public string CustomerNo { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public string PaymentMethod { get; set; } = "CASH";
        public string? BankCode { get; set; }
        public string? BankName { get; set; }
        public string? ChequeNumber { get; set; }
        public string? ChequeDate { get; set; }
        public string? QrTransactionRef { get; set; }
        public string SiteCode { get; set; } = string.Empty;
        public string? Company { get; set; }
        public string? CreatedAt { get; set; }
        public string? UserName { get; set; }
        public string? DeviceId { get; set; }
    }
}
