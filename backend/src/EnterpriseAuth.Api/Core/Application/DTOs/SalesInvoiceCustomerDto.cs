namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class SalesInvoiceCustomerDto
    {
        public string Code { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string? PaymentTerm { get; set; }
        public decimal? CreditLimit { get; set; }
        public string? StatusFlag { get; set; }
        public string TaxRule { get; set; } = string.Empty;
    }
}
