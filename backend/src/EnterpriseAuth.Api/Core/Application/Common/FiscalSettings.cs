namespace EnterpriseAuth.Api.Core.Application.Common
{
    /// <summary>
    /// Configuration options for MRA EBS / HEP fiscalisation integration.
    /// </summary>
    public class FiscalSettings
    {
        public string BaseUrl { get; set; } = "http://192.168.120.10:5161";
        public int TimeoutSeconds { get; set; } = 30;
        public bool EnforceX3Gate { get; set; } = true;
        public FiscalSellerFallbackSettings Seller { get; set; } = new();
    }

    public class FiscalSellerFallbackSettings
    {
        public string Name { get; set; } = "INNODIS LTD";
        public string TradeName { get; set; } = "INNODIS LTD";
        public string Tan { get; set; } = string.Empty;
        public string Brn { get; set; } = string.Empty;
        public string BusinessAddr { get; set; } = "MFD, Zone 5, Mer Rouge, Port Louis, Mauritius";
        public string BusinessPhoneNo { get; set; } = string.Empty;
    }
}
