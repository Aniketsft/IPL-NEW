using System;

namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class OrderRolloverDto
    {
        public string SoNumber { get; set; } = string.Empty;
        public DateTime UserSelectedDate { get; set; }
    }
}
