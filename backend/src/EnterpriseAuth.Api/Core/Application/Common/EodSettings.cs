namespace EnterpriseAuth.Api.Core.Application.Common
{
    public class EodSettings
    {
        /// <summary>
        /// Parent BOM item codes whose components should always appear in StagingEod at EOD,
        /// even if TotalManufacturedQuantity = 0 (not scanned).
        /// Configurable via appsettings.json under "EodSettings:BomParentItemCodes".
        /// </summary>
        public List<string> BomParentItemCodes { get; set; } = new();
    }
}
