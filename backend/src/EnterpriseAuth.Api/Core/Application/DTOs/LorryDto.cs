namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    /// <summary>
    /// Represents a lorry option from APLSTD where LANCHP_0=409 AND LAN_0='BRI'.
    /// LanNum (LANNUM_0) is the value stored in Staging.ZLOCFCY_0 and sent in the SOAP record.
    /// LanMes (LANMES_0) is the human-readable display label shown to the user.
    /// </summary>
    public class LorryDto
    {
        public int LanNum { get; set; }    // LANNUM_0 — stored in ZLOCFCY_0 & SOAP
        public string LanMes { get; set; } = string.Empty; // LANMES_0 — shown in UI dropdown
    }
}
