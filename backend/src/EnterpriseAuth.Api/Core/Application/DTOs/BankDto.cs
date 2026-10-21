namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class BankDto
    {
        public string BankCode { get; set; } = string.Empty;
        public string BankName { get; set; } = string.Empty;
        public string Company { get; set; } = string.Empty;
        public string Currency { get; set; } = string.Empty;
        public string? SiteCode { get; set; }
    }
}
