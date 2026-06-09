namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    /// <summary>
    /// Represents a BOM component row returned by the X3 BOM/BOMD join query.
    /// Used during End-of-Day to ensure all BOM components are inserted into StagingEod.
    /// </summary>
    public class BomComponentDto
    {
        public string ParentItemCode { get; set; } = string.Empty;
        public string ComponentItemCode { get; set; } = string.Empty;
    }
}
