using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    [Table("EodProcessAudits")]
    public class EodProcessAudit
    {
        [Key]
        public Guid Id { get; set; } = Guid.NewGuid();

        [Required]
        [MaxLength(50)]
        public string EodDate { get; set; } = string.Empty;

        [Required]
        [MaxLength(100)]
        public string WorkOrderNumber { get; set; } = string.Empty;

        [Required]
        [MaxLength(200)]
        public string TriggeredBy { get; set; } = string.Empty;

        [Required]
        [MaxLength(255)]
        public string DeviceId { get; set; } = string.Empty;

        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        public bool IsDeactivated { get; set; } = false;
    }
}
