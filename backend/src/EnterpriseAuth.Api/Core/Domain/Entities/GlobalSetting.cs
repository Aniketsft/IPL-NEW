using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    [Table("GlobalSettings")]
    public class GlobalSetting
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int Id { get; set; }

        [MaxLength(100)]
        [Column("SettingKey")]
        public string SettingKey { get; set; } = string.Empty;

        [Column("SettingValue")]
        public string SettingValue { get; set; } = string.Empty;

        [MaxLength(100)]
        [Column("LastUpdatedBy")]
        public string? LastUpdatedBy { get; set; }

        [Column("UpdatedAt")]
        public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

        [MaxLength(20)]
        [Column("Action")]
        public string Action { get; set; } = "INSERT";
    }
}
