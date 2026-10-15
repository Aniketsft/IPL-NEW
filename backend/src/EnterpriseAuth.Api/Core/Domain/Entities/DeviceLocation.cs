using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    [Table("DeviceLocations")]
    public class DeviceLocation
    {
        [Key]
        [MaxLength(100)]
        [Column("DeviceId")]
        public string DeviceId { get; set; } = string.Empty;

        [MaxLength(50)]
        [Column("MacAddress")]
        public string? MacAddress { get; set; }

        [Required]
        [MaxLength(150)]
        [Column("DeviceName")]
        public string DeviceName { get; set; } = string.Empty;

        [Required]
        [MaxLength(20)]
        [Column("SiteCode")]
        public string SiteCode { get; set; } = string.Empty;

        [MaxLength(20)]
        [Column("WarehouseCode")]
        public string? WarehouseCode { get; set; }

        [Required]
        [MaxLength(30)]
        [Column("LocationCode")]
        public string LocationCode { get; set; } = string.Empty;

        [Column("AssignedUserId")]
        public Guid? AssignedUserId { get; set; }

        [MaxLength(100)]
        [Column("AssignedUserName")]
        public string? AssignedUserName { get; set; }

        [Column("IsActive")]
        public bool IsActive { get; set; } = true;

        [Column("CreatedAt")]
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        [Column("UpdatedAt")]
        public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

        [Required]
        [MaxLength(100)]
        [Column("UpdatedBy")]
        public string UpdatedBy { get; set; } = "SYSTEM";
    }
}
