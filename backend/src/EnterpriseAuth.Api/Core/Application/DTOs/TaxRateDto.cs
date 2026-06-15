namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class TaxRateDto
    {
        public string TaxCode { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;
        public decimal TaxRatePercent { get; set; }
    }
}
