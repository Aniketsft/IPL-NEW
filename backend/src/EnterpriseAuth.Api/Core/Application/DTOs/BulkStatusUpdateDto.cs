using System.Collections.Generic;

namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class BulkStatusUpdateDto
    {
        public string SoNumber { get; set; } = string.Empty;
        public List<string> ItemCodes { get; set; } = new();
        public bool Status { get; set; }
        public bool IsValidation { get; set; }
        public string PerformedBy { get; set; } = "system";
    }
}
