namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class FacilityDto
    {
        public string SalesSiteCode { get; set; } = string.Empty;
        public string SalesSiteName { get; set; } = string.Empty;
        public int SalesFlag { get; set; } = 1; // 1 = Yes (Active for Sales), 2 = No
        public string FinancialSiteCode { get; set; } = string.Empty;
        public string? FinancialSiteName { get; set; }
        public string LegalCompany { get; set; } = "INL";
    }
}
