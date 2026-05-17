using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    [Table("AuditLogs")]
    public class AuditLog
    {
        [Key]
        [Column("AuditId")]
        public int AuditId { get; set; }

        [Required]
        [MaxLength(100)]
        [Column("EntityName")]
        public string EntityName { get; set; } = string.Empty;

        [Required]
        [MaxLength(200)]
        [Column("EntityIdString")]
        public string EntityIdString { get; set; } = string.Empty;

        [Required]
        [MaxLength(20)]
        [Column("ActionType")]
        public string ActionType { get; set; } = string.Empty; // INSERT, UPDATE, DELETE

        [Column("Payload")]
        public string? Payload { get; set; }

        [MaxLength(100)]
        [Column("PerformedBy")]
        public string? PerformedBy { get; set; }

        [Column("PerformedAt")]
        public DateTime PerformedAt { get; set; } = DateTime.UtcNow;
    }
}
