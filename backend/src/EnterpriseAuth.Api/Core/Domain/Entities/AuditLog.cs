using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    [Table("audit_log")]
    public class AuditLog
    {
        [Key]
        [Column("audit_id")]
        public int AuditId { get; set; }

        [Required]
        [MaxLength(100)]
        [Column("entity_name")]
        public string EntityName { get; set; } = string.Empty;

        [Required]
        [Column("entity_id")]
        public int EntityId { get; set; }

        [Required]
        [MaxLength(20)]
        [Column("action_type")]
        public string ActionType { get; set; } = string.Empty; // INSERT, UPDATE, DELETE

        [Column("payload")]
        public string? Payload { get; set; }

        [MaxLength(100)]
        [Column("performed_by")]
        public string? PerformedBy { get; set; }

        [Column("performed_at")]
        public DateTime PerformedAt { get; set; } = DateTime.UtcNow;
    }
}
