namespace EnterpriseAuth.Api.Core.Application.Common;

public class SyncSettings
{
    public int SyncWindowDays { get; set; } = 7;
    public string X3DatabaseName { get; set; } = "x3";
    public string AppDatabaseName { get; set; } = "Hipo";
}
