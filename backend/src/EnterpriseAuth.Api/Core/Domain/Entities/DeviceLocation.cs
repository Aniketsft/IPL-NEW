using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    [Table("DeviceLocations")]
    public class DeviceLocation
    {
        [Key]
        [MaxLength(64)]
        [Column("DeviceId")]
        public string DeviceId { get; set; } = string.Empty;

        [Required]
        [MaxLength(100)]
        [Column("DeviceName")]
        public string DeviceName { get; set; } = string.Empty;

        [MaxLength(150)]
        [Column("HardwareModel")]
        public string? HardwareModel { get; set; }

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

        [MaxLength(100)]
        [Column("HepProfileId")]
        public string? HepProfileId { get; set; }

        [MaxLength(255)]
        [Column("HepApiKey")]
        public string? HepApiKey { get; set; }

        [Column("IsLocked")]
        public bool IsLocked { get; set; } = true;

        [Column("IsLicensed")]
        public bool IsLicensed { get; set; } = true;

        [Required]
        [MaxLength(30)]
        [Column("LicenseStatus")]
        public string LicenseStatus { get; set; } = "VALID";

        [Column("LicenseUpdatedAt")]
        public DateTime? LicenseUpdatedAt { get; set; }

        [MaxLength(100)]
        [Column("LicenseUpdatedBy")]
        public string? LicenseUpdatedBy { get; set; }

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
