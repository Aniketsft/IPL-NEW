using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    [Table("X3SoapAudits")]
    public class X3SoapAudit
    {
        [Key]
        public Guid Id { get; set; } = Guid.NewGuid();

        /// <summary>
        /// The name of the action/method being called (e.g., "ProcessEndOfDay").
        /// </summary>
        [MaxLength(100)]
        public string ActionName { get; set; } = string.Empty;

        /// <summary>
        /// The business identifier being processed (e.g., a Work Order or SO number).
        /// </summary>
        [MaxLength(100)]
        public string? Identifier { get; set; }

        /// <summary>
        /// A brief summary or full XML of the request sent to X3.
        /// </summary>
        public string? RequestPayload { get; set; }

        /// <summary>
        /// A brief summary or full XML of the response received from X3.
        /// </summary>
        public string? ResponsePayload { get; set; }

        public bool IsSuccess { get; set; }

        [MaxLength(2000)]
        public string? ErrorMessage { get; set; }

        /// <summary>
        /// Username of the user who triggered the operation.
        /// </summary>
        [MaxLength(200)]
        public string? TriggeredBy { get; set; }

        /// <summary>
        /// The hardware device ID of the terminal that initiated the request.
        /// </summary>
        [MaxLength(255)]
        public string? DeviceId { get; set; }

        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }
}
