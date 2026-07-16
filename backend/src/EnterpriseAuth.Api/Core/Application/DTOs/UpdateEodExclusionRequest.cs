using System;

namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class UpdateEodExclusionRequest
    {
        public string EntityType { get; set; } = string.Empty; // "SalesOrder" or "ScanLine"
        public string EntityId { get; set; } = string.Empty; // SourceOrderId or SyncId
        public bool ExcludeFromEod { get; set; }
    }
}
