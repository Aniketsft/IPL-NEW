namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class TaxMatrixDto
    {
        public string CustomerTaxRule { get; set; } = string.Empty;
        public string ItemTaxLevel { get; set; } = string.Empty;
        public string TaxCode { get; set; } = string.Empty;
    }
}
