namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class SalesInvoiceCustomerDto
    {
        public string Code { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string? PaymentTerm { get; set; }
        public decimal? CreditLimit { get; set; }
        public decimal? OutstandingBalance { get; set; }
        public string? StatusFlag { get; set; }
        public string TaxRule { get; set; } = string.Empty;
        public string? Bcgcod { get; set; }
        public string? Tsccod { get; set; }
        public int? FacilityFlag { get; set; }
    }
}
