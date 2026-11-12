namespace EnterpriseAuth.Api.Core.Application.Common
{
    /// <summary>
    /// Centralized representation of operational and financial facility contexts for Sage X3.
    /// </summary>
    public class SiteContext
    {
        /// <summary>
        /// Operational lorry or warehouse shipping site (e.g. "SCG", "SCP", "SDA", "SFF").
        /// Target for: Physical stock (STOCK.STOFCY_0), item catalog, lorry inventory, delivery routes.
        /// </summary>
        public string ShippingSiteCode { get; set; } = string.Empty;

        /// <summary>
        /// Financial/accounting facility (e.g. "CGD", "POD", "DPD", "FFD", "IPL").
        /// Target for: Open invoices (GACCDUDATE.FCY_0), invoices/credit notes (SINVOICE.SALFCY_0), customer debt, tax, banks.
        /// </summary>
        public string FinancialSiteCode { get; set; } = string.Empty;

        /// <summary>
        /// Raw site assigned to the user in claims or explicitly passed in the request.
        /// </summary>
        public string RawSiteCode { get; set; } = string.Empty;

        /// <summary>
        /// Whether the user has global visibility across all facilities (e.g. "ALL" or Admin).
        /// </summary>
        public bool IsMultiSiteAdmin { get; set; }

        /// <summary>
        /// Legal company code (default: "INL").
        /// </summary>
        public string LegalCompany { get; set; } = "INL";
    }
}

