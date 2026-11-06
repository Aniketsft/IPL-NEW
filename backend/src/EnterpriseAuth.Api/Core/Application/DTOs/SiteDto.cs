namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class SiteDto
    {
        public string SiteCode { get; set; } = string.Empty;
        public string SiteName { get; set; } = string.Empty;
        public int IsSalesSite { get; set; }
        public int IsStockSite { get; set; }
        public string FinancialSiteCode { get; set; } = string.Empty;
        public string? FinancialSiteName { get; set; }
    }
}
