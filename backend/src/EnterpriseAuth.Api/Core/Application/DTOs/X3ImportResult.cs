using System.Collections.Generic;

namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class X3ImportResult
    {
        public string Identifier { get; set; } = string.Empty; // SOHNUM
        public bool Success { get; set; }
        public string? RequestNumber { get; set; } // O_REQNUM
        public string? DocumentId { get; set; } // X3 Document ID (e.g. DPMSI260627195)
        public List<string> Messages { get; set; } = new List<string>();
        public string? TechnicalError { get; set; }
        public string? RawPayload { get; set; }
    }

    public class EndOfDayResult
    {
        public int TotalProcessed { get; set; }
        public int SuccessCount { get; set; }
        public int FailureCount { get; set; }
        public List<X3ImportResult> Results { get; set; } = new List<X3ImportResult>();
    }
}
