namespace EnterpriseAuth.Api.Core.Application.Common;

public class SyncSettings
{
    public int SyncWindowDays { get; set; } = 7;
    public string X3DatabaseName { get; set; } = "x3";
    public string AppDatabaseName { get; set; } = "Hipo";
    /// <summary>
    /// X3 company code used to filter SPRICCONF by PLICPY_0 (e.g. "INL").
    /// Matches the X3 UAT spec: WHERE PLICPY_0 = 'INL' AND PLIENAFLG_0 = 2
    /// </summary>
    public string X3CompanyCode { get; set; } = "INL";
}
