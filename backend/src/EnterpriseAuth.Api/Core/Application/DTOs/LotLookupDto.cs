using System;

namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class LotLookupDto
    {
        public string ItemCode { get; set; } = string.Empty;
        public string SiteCode { get; set; } = string.Empty;
        public string Lot { get; set; } = string.Empty;
    }
}
