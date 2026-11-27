using System;
using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    // --- Mobile <-> Backend API DTOs ---

    public class FiscaliseDocumentRequestDto
    {
        public string DocumentNo { get; set; } = string.Empty;
        public string DocumentCategory { get; set; } = "INVOICE"; // INVOICE, CREDIT_NOTE, RETURN
        public string? InvoiceType { get; set; } // Optional raw type: STD, CRN, MICAS, MICRE, MRCAS, MRCRE, etc.
        public string? SalesSite { get; set; }
        public string CustomerCode { get; set; } = string.Empty;
        public string? CustomerName { get; set; }
        public string Currency { get; set; } = "MUR";
        public decimal RateMultiplier { get; set; } = 1m;
        public string? OriginalInvoiceId { get; set; }
        public string? Reason { get; set; }
        public string? InvoiceDate { get; set; }
        public string? DeviceId { get; set; }
        public string? SettlementType { get; set; }
        public decimal? TotalPaid { get; set; }
        public List<FiscaliseLineDto> Lines { get; set; } = new();
        public List<FiscalisePaymentDto> Payments { get; set; } = new();
    }

    public class FiscaliseLineDto
    {
        public int LineNo { get; set; }
        public string Sku { get; set; } = string.Empty;
        public string? Name { get; set; }
        public decimal Quantity { get; set; }
        public decimal UnitPrice { get; set; } // Gross unit price (excl. VAT)
        public decimal DiscountAmount { get; set; } // Total line discount
        public decimal VatAmount { get; set; }
        public decimal? AmtWoVat { get; set; }
        public decimal? Total { get; set; }
        public string? TaxCode { get; set; }
        public string? TaxRule { get; set; }
        public string? Nature { get; set; } // GOODS / SERVICES
    }

    public class FiscalisePaymentDto
    {
        public string Method { get; set; } = string.Empty;
        public decimal Amount { get; set; }
    }

    public class FiscalErrorItemDto
    {
        public string? Code { get; set; }
        public string Description { get; set; } = string.Empty;
    }

    public class FiscaliseResultDto
    {
        public bool Success { get; set; }
        public string DocumentNo { get; set; } = string.Empty;
        public bool IsFiscalised { get; set; }
        public string? HepId { get; set; }
        public string? HepStatus { get; set; }
        public string? StatusMessage { get; set; }
        public string? Irn { get; set; }
        public string? QrBase64 { get; set; }
        public string? MraStatus { get; set; }
        public string? MraEnvironment { get; set; }
        public string? MraRequestId { get; set; }
        public string? MraResponseId { get; set; }
        public DateTime? FiscalisedAt { get; set; }
        public List<FiscalErrorItemDto> Errors { get; set; } = new();
    }

    // --- Resolved Master Context for Mapping ---

    public class FiscalSellerContext
    {
        public string Name { get; set; } = string.Empty;
        public string TradeName { get; set; } = string.Empty;
        public string Tan { get; set; } = string.Empty;
        public string Brn { get; set; } = string.Empty;
        public string BusinessAddr { get; set; } = string.Empty;
        public string BusinessPhoneNo { get; set; } = string.Empty;
    }

    public class FiscalBuyerContext
    {
        public string Code { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string Tan { get; set; } = string.Empty;
        public string Brn { get; set; } = string.Empty;
        public string BusinessAddr { get; set; } = string.Empty;
        public string BuyerType { get; set; } = string.Empty;
        public string PersonType { get; set; } = string.Empty;
        public string Nic { get; set; } = string.Empty;
        public string TransactionType { get; set; } = string.Empty;
    }

    // --- HEP Connector Wire DTOs (Matches X3 CDATA JSON Schema) ---

    public class HepPayloadDocument
    {
        [JsonPropertyName("invoiceCounter")]
        public string InvoiceCounter { get; set; } = "1";

        [JsonPropertyName("transactionType")]
        public string TransactionType { get; set; } = string.Empty;

        [JsonPropertyName("personType")]
        public string PersonType { get; set; } = string.Empty;

        [JsonPropertyName("invoiceTypeDesc")]
        public string InvoiceTypeDesc { get; set; } = "STD";

        [JsonPropertyName("currency")]
        public string Currency { get; set; } = "MUR";

        [JsonPropertyName("invoiceIdentifier")]
        public string InvoiceIdentifier { get; set; } = string.Empty;

        [JsonPropertyName("invoiceRefIdentifier")]
        public string InvoiceRefIdentifier { get; set; } = string.Empty;

        [JsonPropertyName("previousNoteHash")]
        public string PreviousNoteHash { get; set; } = "0";

        [JsonPropertyName("reasonStated")]
        public string ReasonStated { get; set; } = string.Empty;

        [JsonPropertyName("totalVatAmount")]
        public string TotalVatAmount { get; set; } = "0.00";

        [JsonPropertyName("totalAmtWoVatCur")]
        public string TotalAmtWoVatCur { get; set; } = "0.00";

        [JsonPropertyName("totalAmtWoVatMur")]
        public string TotalAmtWoVatMur { get; set; } = "0.00";

        [JsonPropertyName("invoiceTotal")]
        public string InvoiceTotal { get; set; } = "0.00";

        [JsonPropertyName("discountTotalAmount")]
        public string DiscountTotalAmount { get; set; } = "0.00";

        [JsonPropertyName("totalAmtPaid")]
        public string TotalAmtPaid { get; set; } = "0.00";

        [JsonPropertyName("dateTimeInvoiceIssued")]
        public string DateTimeInvoiceIssued { get; set; } = string.Empty;

        [JsonPropertyName("seller")]
        public HepSellerDto Seller { get; set; } = new();

        [JsonPropertyName("buyer")]
        public HepBuyerDto Buyer { get; set; } = new();

        [JsonPropertyName("itemList")]
        public List<HepItemDto> ItemList { get; set; } = new();

        [JsonPropertyName("salesTransactions")]
        public string SalesTransactions { get; set; } = string.Empty;
    }

    public class HepSellerDto
    {
        [JsonPropertyName("name")]
        public string Name { get; set; } = string.Empty;

        [JsonPropertyName("tradeName")]
        public string TradeName { get; set; } = string.Empty;

        [JsonPropertyName("tan")]
        public string Tan { get; set; } = string.Empty;

        [JsonPropertyName("brn")]
        public string Brn { get; set; } = string.Empty;

        [JsonPropertyName("businessAddr")]
        public string BusinessAddr { get; set; } = string.Empty;

        [JsonPropertyName("businessPhoneNo")]
        public string BusinessPhoneNo { get; set; } = string.Empty;

        [JsonPropertyName("ebsCounterNo")]
        public string EbsCounterNo { get; set; } = "1";
    }

    public class HepBuyerDto
    {
        [JsonPropertyName("name")]
        public string Name { get; set; } = string.Empty;

        [JsonPropertyName("tan")]
        public string Tan { get; set; } = string.Empty;

        [JsonPropertyName("brn")]
        public string Brn { get; set; } = string.Empty;

        [JsonPropertyName("businessAddr")]
        public string BusinessAddr { get; set; } = string.Empty;

        [JsonPropertyName("buyerType")]
        public string BuyerType { get; set; } = string.Empty;

        [JsonPropertyName("nic")]
        public string Nic { get; set; } = string.Empty;
    }

    public class HepItemDto
    {
        [JsonPropertyName("itemNo")]
        public string ItemNo { get; set; } = "1";

        [JsonPropertyName("taxCode")]
        public string TaxCode { get; set; } = string.Empty;

        [JsonPropertyName("nature")]
        public string Nature { get; set; } = "GOODS";

        [JsonPropertyName("productCodeMra")]
        public string ProductCodeMra { get; set; } = string.Empty;

        [JsonPropertyName("productCodeOwn")]
        public string ProductCodeOwn { get; set; } = string.Empty;

        [JsonPropertyName("itemDesc")]
        public string ItemDesc { get; set; } = string.Empty;

        [JsonPropertyName("quantity")]
        public string Quantity { get; set; } = "0";

        [JsonPropertyName("unitPrice")]
        public string UnitPrice { get; set; } = "0.0000";

        [JsonPropertyName("discount")]
        public string Discount { get; set; } = "0.0000";

        [JsonPropertyName("discountedValue")]
        public string DiscountedValue { get; set; } = "0.0000";

        [JsonPropertyName("amtWoVatCur")]
        public string AmtWoVatCur { get; set; } = "0.00";

        [JsonPropertyName("amtWoVatMur")]
        public string AmtWoVatMur { get; set; } = "0.00";

        [JsonPropertyName("vatAmt")]
        public string VatAmt { get; set; } = "0.00";

        [JsonPropertyName("totalPrice")]
        public string TotalPrice { get; set; } = "0.00";
    }

    // --- HEP Connector Response DTOs ---

    public class HepIngestResponseDto
    {
        [JsonPropertyName("hepId")]
        public string? HepId { get; set; }

        [JsonPropertyName("status")]
        public string? Status { get; set; }

        [JsonPropertyName("statusMessage")]
        public string? StatusMessage { get; set; }

        [JsonPropertyName("summary")]
        public HepSummaryDto? Summary { get; set; }

        [JsonPropertyName("mraResponse")]
        public HepMraResponseDto? MraResponse { get; set; }
    }

    public class HepSummaryDto
    {
        [JsonPropertyName("createdAt")]
        public string? CreatedAt { get; set; }

        [JsonPropertyName("updatedAt")]
        public string? UpdatedAt { get; set; }

        [JsonPropertyName("invoiceTotal")]
        public decimal? InvoiceTotal { get; set; }

        [JsonPropertyName("lineItemCount")]
        public int? LineItemCount { get; set; }

        [JsonPropertyName("totalVatAmount")]
        public decimal? TotalVatAmount { get; set; }

        [JsonPropertyName("totalAmountPaid")]
        public decimal? TotalAmountPaid { get; set; }

        [JsonPropertyName("discountTotalAmount")]
        public decimal? DiscountTotalAmount { get; set; }

        [JsonPropertyName("totalAmountWithoutVatCur")]
        public decimal? TotalAmountWithoutVatCur { get; set; }

        [JsonPropertyName("totalAmountWithoutVatMur")]
        public decimal? TotalAmountWithoutVatMur { get; set; }
    }

    public class HepMraResponseDto
    {
        [JsonPropertyName("status")]
        public string? Status { get; set; }

        [JsonPropertyName("requestId")]
        public string? RequestId { get; set; }

        [JsonPropertyName("responseId")]
        public string? ResponseId { get; set; }

        [JsonPropertyName("environment")]
        public string? Environment { get; set; }

        [JsonPropertyName("responseDateTime")]
        public string? ResponseDateTime { get; set; }

        [JsonPropertyName("errorMessages")]
        public List<HepErrorMessageDto>? ErrorMessages { get; set; }

        [JsonPropertyName("fiscalisedInvoices")]
        public List<HepFiscalisedInvoiceDto>? FiscalisedInvoices { get; set; }
    }

    public class HepFiscalisedInvoiceDto
    {
        [JsonPropertyName("irn")]
        public string? Irn { get; set; }

        [JsonPropertyName("qrCode")]
        public string? QrCode { get; set; }

        [JsonPropertyName("status")]
        public string? Status { get; set; }

        [JsonPropertyName("invoiceIdentifier")]
        public string? InvoiceIdentifier { get; set; }

        [JsonPropertyName("errorMessages")]
        public List<HepErrorMessageDto>? ErrorMessages { get; set; }
    }

    public class HepErrorMessageDto
    {
        [JsonPropertyName("code")]
        public string? Code { get; set; }

        [JsonPropertyName("description")]
        public string? Description { get; set; }
    }
}
