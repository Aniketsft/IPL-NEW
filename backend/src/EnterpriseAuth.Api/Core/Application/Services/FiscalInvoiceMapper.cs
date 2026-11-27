using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.Json;
using EnterpriseAuth.Api.Core.Application.DTOs;

namespace EnterpriseAuth.Api.Core.Application.Services
{
    public sealed record MappedFiscalPayload(
        HepPayloadDocument Document,
        decimal TotalAmtWoVatCur,
        decimal TotalAmtWoVatMur,
        decimal TotalVatAmount,
        decimal InvoiceTotal,
        decimal DiscountTotal,
        decimal TotalAmountPaid,
        string InvoiceDateFormatted);

    public sealed record ParsedHepOutcome(
        bool IsSuccess,
        string? HepId,
        string? HepStatus,
        string? HepStatusMessage,
        string? MraStatus,
        string? MraRequestId,
        string? MraResponseId,
        string? MraEnvironment,
        string? MraResponseDateTime,
        string? Irn,
        string? QrBase64,
        List<FiscalErrorItemDto> Errors);

    public static class FiscalInvoiceMapper
    {
        private static readonly JsonSerializerOptions JsonOptions = new()
        {
            PropertyNameCaseInsensitive = true
        };

        /// <summary>
        /// Maps X3 SIVTYP / mobile category to MRA invoiceTypeDesc (Z_INV_TYPE rule).
        /// </summary>
        public static string ResolveInvoiceTypeDesc(string? rawInvoiceType, string? documentCategory)
        {
            var raw = (rawInvoiceType ?? string.Empty).Trim().ToUpperInvariant();
            if (raw is "DICAS" or "DICRE" or "MICAS" or "MICRE" or "MSINV" or "STD" or "INVOICE")
            {
                return "STD";
            }
            if (raw is "DRCAS" or "DRCRE" or "MRCAS" or "MRCRE" or "MSCRN" or "CRN" or "RTN" or "CREDIT_NOTE" or "RETURN")
            {
                return "CRN";
            }

            var cat = (documentCategory ?? string.Empty).Trim().ToUpperInvariant();
            if (cat is "CREDIT_NOTE" or "RETURN" or "REVERSAL")
            {
                return "CRN";
            }
            if (cat is "INVOICE" or "")
            {
                return string.IsNullOrEmpty(raw) ? "STD" : raw;
            }

            return raw;
        }

        /// <summary>
        /// Maps mobile payment / refund methods to MRA salesTransactions.
        /// Rules: any CREDIT -> CREDIT; single method -> mapped method; multiple non-credit -> CASH.
        /// </summary>
        public static string ResolveSalesTransactions(
            IEnumerable<FiscalisePaymentDto>? payments,
            string? settlementType = null,
            string? rawInvoiceType = null)
        {
            var mapped = new List<string>();
            if (payments != null)
            {
                foreach (var p in payments)
                {
                    if (p.Amount <= 0 && payments.Count() > 1) continue;
                    var code = MapSinglePaymentMethod(p.Method);
                    if (!string.IsNullOrEmpty(code))
                    {
                        mapped.Add(code);
                    }
                }
            }

            if (mapped.Count == 0 && !string.IsNullOrWhiteSpace(settlementType))
            {
                var fromSettlement = MapSinglePaymentMethod(settlementType);
                if (!string.IsNullOrEmpty(fromSettlement))
                {
                    mapped.Add(fromSettlement);
                }
            }

            if (mapped.Count == 0 && !string.IsNullOrWhiteSpace(rawInvoiceType))
            {
                var raw = rawInvoiceType.Trim().ToUpperInvariant();
                if (raw is "MICRE" or "MRCRE" or "DICRE" or "DRCRE") return "CREDIT";
                if (raw is "MICAS" or "MRCAS" or "DICAS" or "DRCAS") return "CASH";
            }

            if (mapped.Count == 0) return string.Empty;
            if (mapped.Contains("CREDIT", StringComparer.OrdinalIgnoreCase)) return "CREDIT";

            var distinct = mapped.Distinct(StringComparer.OrdinalIgnoreCase).ToList();
            return distinct.Count == 1 ? distinct[0] : "CASH";
        }

        public static string MapSinglePaymentMethod(string? method)
        {
            var m = (method ?? string.Empty).Trim().ToUpperInvariant();
            return m switch
            {
                "CASH" or "CSH" or "CASH REFUND" => "CASH",
                "CHEQUE" or "CHQ" => "CHEQUE",
                "CREDIT" or "CREDIT ON ACCOUNT" or "ON ACCOUNT" => "CREDIT",
                "CARD" => "CARD",
                "BNKTRANSFER" or "BANK_TRANSFER" or "BANK TRANSFER" => "BNKTRANSFER",
                "MYT MONEY" or "MYTMONEY" or "BLINK" or "JUICE" or "QR" or "QR CODE" or "CN_OFFSET" or "OTHER" => "OTHER",
                "" => string.Empty,
                _ => "OTHER"
            };
        }

        /// <summary>
        /// Normalizes X3 ZTRANTYPE (either string B2B/B2C/B2G/EXP/B2E or local menu 1..5).
        /// </summary>
        public static string NormalizeTransactionType(string? rawTranType, string? buyerBrn, string? buyerTan)
        {
            var clean = (rawTranType ?? string.Empty).Trim().ToUpperInvariant();
            switch (clean)
            {
                case "B2B":
                case "1":
                    return "B2B";
                case "B2G":
                case "2":
                    return "B2G";
                case "B2C":
                case "3":
                    return "B2C";
                case "EXP":
                case "4":
                    return "EXP";
                case "B2E":
                case "5":
                    return "B2E";
                default:
                    return (!string.IsNullOrWhiteSpace(buyerBrn) || !string.IsNullOrWhiteSpace(buyerTan))
                        ? "B2B"
                        : "B2C";
            }
        }

        public static string FormatInvoiceDateTime(string? rawDate)
        {
            if (!string.IsNullOrWhiteSpace(rawDate))
            {
                var trimmed = rawDate.Trim();
                if (DateTime.TryParse(trimmed, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var parsed))
                {
                    return parsed.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture) + " 00:00:00";
                }
                if (trimmed.Length >= 8 && DateTime.TryParseExact(trimmed.Substring(0, 8), "yyyyMMdd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var compact))
                {
                    return compact.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture) + " 00:00:00";
                }
            }
            return DateTime.UtcNow.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture) + " 00:00:00";
        }

        public static decimal Round2(decimal value) => Math.Round(value, 2, MidpointRounding.AwayFromZero);
        public static decimal Round4(decimal value) => Math.Round(value, 4, MidpointRounding.AwayFromZero);

        public static string Fmt2(decimal value) => Round2(value).ToString("0.##", CultureInfo.InvariantCulture);
        public static string Fmt4(decimal value) => Round4(value).ToString("0.####", CultureInfo.InvariantCulture);

        public static MappedFiscalPayload Map(
            FiscaliseDocumentRequestDto request,
            FiscalSellerContext seller,
            FiscalBuyerContext buyer,
            string ebsCounterNo,
            IReadOnlyDictionary<string, string> itemNatures,
            IReadOnlyDictionary<string, string> resolvedTaxCodes,
            string? resolvedReasonText)
        {
            var rateMultiplier = request.RateMultiplier <= 0 ? 1m : request.RateMultiplier;
            var currency = string.IsNullOrWhiteSpace(request.Currency) ? "MUR" : request.Currency.Trim().ToUpperInvariant();
            var invoiceTypeDesc = ResolveInvoiceTypeDesc(request.InvoiceType, request.DocumentCategory);
            var salesTransactions = ResolveSalesTransactions(request.Payments, request.SettlementType, request.InvoiceType);
            var tranType = NormalizeTransactionType(buyer.TransactionType, buyer.Brn, buyer.Tan);
            var issuedDate = FormatInvoiceDateTime(request.InvoiceDate);

            var hepItems = new List<HepItemDto>();
            decimal totalWoVatCur = 0m;
            decimal totalVat = 0m;
            decimal totalLineDiscount = 0m;

            int seq = 1;
            foreach (var line in request.Lines)
            {
                var qty = line.Quantity;
                var grossUnit = Round4(line.UnitPrice);
                var lineDiscountTotal = line.DiscountAmount < 0 ? 0m : line.DiscountAmount;
                var unitDiscount = qty > 0 ? Round4(lineDiscountTotal / qty) : 0m;
                if (unitDiscount > grossUnit) unitDiscount = grossUnit;
                var netUnit = Round4(grossUnit - unitDiscount);

                decimal amtWoVatCur;
                if (line.AmtWoVat.HasValue)
                {
                    amtWoVatCur = Round2(line.AmtWoVat.Value);
                }
                else if (line.Total.HasValue && line.Total.Value > 0)
                {
                    amtWoVatCur = Round2(line.Total.Value - line.VatAmount);
                }
                else
                {
                    amtWoVatCur = Round2((qty * grossUnit) - lineDiscountTotal);
                }

                var vatAmt = Round2(line.VatAmount);
                var totalPrice = line.Total.HasValue && line.Total.Value > 0
                    ? Round2(line.Total.Value)
                    : Round2(amtWoVatCur + vatAmt);
                var amtWoVatMur = Round2(amtWoVatCur * rateMultiplier);

                totalWoVatCur += amtWoVatCur;
                totalVat += vatAmt;
                totalLineDiscount += lineDiscountTotal;

                var sku = (line.Sku ?? string.Empty).Trim();
                var taxCode = !string.IsNullOrWhiteSpace(line.TaxCode)
                    ? line.TaxCode.Trim()
                    : (!string.IsNullOrWhiteSpace(line.TaxRule)
                        ? line.TaxRule.Trim()
                        : (resolvedTaxCodes.TryGetValue(sku, out var t) ? t : string.Empty));

                var nature = !string.IsNullOrWhiteSpace(line.Nature)
                    ? line.Nature.Trim().ToUpperInvariant()
                    : (itemNatures.TryGetValue(sku, out var n) ? n : "GOODS");

                var itemNo = line.LineNo > 0
                    ? (line.LineNo >= 1000 && line.LineNo % 1000 == 0 ? line.LineNo / 1000 : line.LineNo)
                    : seq;

                hepItems.Add(new HepItemDto
                {
                    ItemNo = itemNo.ToString(CultureInfo.InvariantCulture),
                    TaxCode = taxCode,
                    Nature = nature,
                    ProductCodeMra = string.Empty,
                    ProductCodeOwn = sku,
                    ItemDesc = (line.Name ?? sku).Trim(),
                    Quantity = qty.ToString("0.####", CultureInfo.InvariantCulture),
                    UnitPrice = Fmt4(grossUnit),
                    Discount = Fmt4(unitDiscount),
                    DiscountedValue = Fmt4(netUnit),
                    AmtWoVatCur = Fmt2(amtWoVatCur),
                    AmtWoVatMur = Fmt2(amtWoVatMur),
                    VatAmt = Fmt2(vatAmt),
                    TotalPrice = Fmt2(totalPrice)
                });

                seq++;
            }

            totalWoVatCur = Round2(totalWoVatCur);
            var totalWoVatMur = Round2(totalWoVatCur * rateMultiplier);
            totalVat = Round2(totalVat);
            var invoiceTotal = Round2(totalWoVatCur + totalVat);
            // Line-level discounts are already reflected in AMTNOT/AMTATI; header discountTotalAmount = 0
            // matching X3 ZDISCOUNTTOT and the HEP response summary sample.
            decimal headerDiscountTotal = 0m;
            var totalAmtPaid = request.TotalPaid.HasValue && request.TotalPaid.Value > 0
                ? Round2(request.TotalPaid.Value)
                : Round2(invoiceTotal - headerDiscountTotal);

            var reasonStated = invoiceTypeDesc == "CRN"
                ? (!string.IsNullOrWhiteSpace(resolvedReasonText) ? resolvedReasonText.Trim() : (request.Reason ?? string.Empty).Trim())
                : string.Empty;

            var doc = new HepPayloadDocument
            {
                InvoiceCounter = "1",
                TransactionType = tranType,
                PersonType = buyer.PersonType,
                InvoiceTypeDesc = invoiceTypeDesc,
                Currency = currency,
                InvoiceIdentifier = request.DocumentNo.Trim(),
                InvoiceRefIdentifier = invoiceTypeDesc == "CRN" ? (request.OriginalInvoiceId ?? string.Empty).Trim() : string.Empty,
                PreviousNoteHash = "0",
                ReasonStated = reasonStated,
                TotalVatAmount = Fmt2(totalVat),
                TotalAmtWoVatCur = Fmt2(totalWoVatCur),
                TotalAmtWoVatMur = Fmt2(totalWoVatMur),
                InvoiceTotal = Fmt2(invoiceTotal),
                DiscountTotalAmount = Fmt2(headerDiscountTotal),
                TotalAmtPaid = Fmt2(totalAmtPaid),
                DateTimeInvoiceIssued = issuedDate,
                Seller = new HepSellerDto
                {
                    Name = seller.Name,
                    TradeName = string.IsNullOrWhiteSpace(seller.TradeName) ? seller.Name : seller.TradeName,
                    Tan = seller.Tan,
                    Brn = seller.Brn,
                    BusinessAddr = seller.BusinessAddr,
                    BusinessPhoneNo = seller.BusinessPhoneNo,
                    EbsCounterNo = string.IsNullOrWhiteSpace(ebsCounterNo) ? "1" : ebsCounterNo.Trim()
                },
                Buyer = new HepBuyerDto
                {
                    Name = buyer.Name,
                    Tan = buyer.Tan,
                    Brn = buyer.Brn,
                    BusinessAddr = buyer.BusinessAddr,
                    BuyerType = string.IsNullOrWhiteSpace(buyer.BuyerType) ? buyer.PersonType : buyer.BuyerType,
                    Nic = buyer.Nic
                },
                ItemList = hepItems,
                SalesTransactions = salesTransactions
            };

            return new MappedFiscalPayload(
                doc,
                totalWoVatCur,
                totalWoVatMur,
                totalVat,
                invoiceTotal,
                Round2(totalLineDiscount),
                totalAmtPaid,
                issuedDate);
        }

        public static List<FiscalErrorItemDto> ValidateBeforeSend(HepPayloadDocument doc)
        {
            var errors = new List<FiscalErrorItemDto>();

            if (string.IsNullOrWhiteSpace(doc.InvoiceIdentifier))
            {
                errors.Add(new FiscalErrorItemDto { Code = "PRE_DOC_ID", Description = "Invoice/document identifier is required." });
            }
            if (string.IsNullOrWhiteSpace(doc.SalesTransactions))
            {
                errors.Add(new FiscalErrorItemDto { Code = "PRE_SALES_TX", Description = "Sales transactions type (CASH/CREDIT/CHEQUE/CARD/OTHER) is required." });
            }
            if (string.IsNullOrWhiteSpace(doc.TransactionType))
            {
                errors.Add(new FiscalErrorItemDto { Code = "PRE_TRAN_TYPE", Description = "Customer transactionType (B2B/B2C/B2G/EXP/B2E) is missing." });
            }
            if (string.IsNullOrWhiteSpace(doc.Buyer.Name))
            {
                errors.Add(new FiscalErrorItemDto { Code = "PRE_BUYER_NAME", Description = "Buyer name is required." });
            }
            if (doc.InvoiceTypeDesc == "CRN" && string.IsNullOrWhiteSpace(doc.ReasonStated))
            {
                errors.Add(new FiscalErrorItemDto { Code = "PRE_CRN_REASON", Description = "Reason stated is mandatory for credit notes and returns." });
            }
            if (doc.ItemList.Count == 0)
            {
                errors.Add(new FiscalErrorItemDto { Code = "PRE_ITEMS_EMPTY", Description = "At least one line item is required for fiscalisation." });
            }
            foreach (var item in doc.ItemList)
            {
                if (string.IsNullOrWhiteSpace(item.TaxCode))
                {
                    errors.Add(new FiscalErrorItemDto
                    {
                        Code = "PRE_TAX_CODE",
                        Description = $"Item {item.ItemNo} ({item.ProductCodeOwn}): Tax code is blank."
                    });
                }
            }

            return errors;
        }

        public static ParsedHepOutcome ParseHepResponse(string? responseBody, int? httpStatus)
        {
            if (string.IsNullOrWhiteSpace(responseBody))
            {
                return new ParsedHepOutcome(
                    false, null, "httpError", $"Empty response from HEP (HTTP {httpStatus?.ToString() ?? "N/A"}).",
                    null, null, null, null, null, null, null,
                    new List<FiscalErrorItemDto>
                    {
                        new() { Code = "HEP_EMPTY", Description = $"Empty response from HEP (HTTP {httpStatus?.ToString() ?? "N/A"})." }
                    });
            }

            HepIngestResponseDto? parsed;
            try
            {
                parsed = JsonSerializer.Deserialize<HepIngestResponseDto>(responseBody, JsonOptions);
            }
            catch (Exception ex)
            {
                return new ParsedHepOutcome(
                    false, null, "invalidJson", "HEP returned non-JSON response.",
                    null, null, null, null, null, null, null,
                    new List<FiscalErrorItemDto>
                    {
                        new() { Code = "HEP_INVALID_JSON", Description = $"Failed to parse HEP response: {ex.Message}" }
                    });
            }

            if (parsed == null)
            {
                return new ParsedHepOutcome(
                    false, null, "invalidJson", "Null response payload from HEP.",
                    null, null, null, null, null, null, null,
                    new List<FiscalErrorItemDto>
                    {
                        new() { Code = "HEP_NULL", Description = "HEP returned null JSON payload." }
                    });
            }

            var errors = new List<FiscalErrorItemDto>();
            var inv = parsed.MraResponse?.FiscalisedInvoices?.FirstOrDefault();

            if (parsed.MraResponse?.ErrorMessages != null)
            {
                foreach (var e in parsed.MraResponse.ErrorMessages)
                {
                    if (!string.IsNullOrWhiteSpace(e.Description) || !string.IsNullOrWhiteSpace(e.Code))
                    {
                        errors.Add(new FiscalErrorItemDto { Code = e.Code, Description = e.Description ?? e.Code ?? "MRA error" });
                    }
                }
            }
            if (inv?.ErrorMessages != null)
            {
                foreach (var e in inv.ErrorMessages)
                {
                    if (!string.IsNullOrWhiteSpace(e.Description) || !string.IsNullOrWhiteSpace(e.Code))
                    {
                        errors.Add(new FiscalErrorItemDto { Code = e.Code, Description = e.Description ?? e.Code ?? "MRA invoice error" });
                    }
                }
            }

            bool hepStatusOk = string.Equals(parsed.Status, "fiscalised", StringComparison.OrdinalIgnoreCase)
                || string.Equals(parsed.Status, "duplicate", StringComparison.OrdinalIgnoreCase);
            bool mraStatusOk = string.Equals(parsed.MraResponse?.Status, "SUCCESS", StringComparison.OrdinalIgnoreCase);
            bool invStatusOk = string.Equals(inv?.Status, "SUCCESS", StringComparison.OrdinalIgnoreCase);
            bool hasQr = !string.IsNullOrWhiteSpace(inv?.QrCode);

            bool isSuccess = hepStatusOk && mraStatusOk && invStatusOk && hasQr;

            if (!isSuccess && errors.Count == 0)
            {
                errors.Add(new FiscalErrorItemDto
                {
                    Code = parsed.Status ?? "HEP_ERROR",
                    Description = !string.IsNullOrWhiteSpace(parsed.StatusMessage)
                        ? parsed.StatusMessage!
                        : "Fiscalisation failed without detailed error message."
                });
            }

            return new ParsedHepOutcome(
                isSuccess,
                parsed.HepId,
                parsed.Status,
                parsed.StatusMessage,
                parsed.MraResponse?.Status,
                parsed.MraResponse?.RequestId,
                parsed.MraResponse?.ResponseId,
                parsed.MraResponse?.Environment,
                parsed.MraResponse?.ResponseDateTime,
                inv?.Irn,
                inv?.QrCode,
                errors);
        }
    }
}
