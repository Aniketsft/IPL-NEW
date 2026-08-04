using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    [Table("StagingEod")]
    public class StagingEod
    {
        [Key]
        public Guid Id { get; set; } = Guid.NewGuid();

        [Required]
        [MaxLength(100)]
        public string WorkOrderNumber { get; set; } = string.Empty;

        [Required]
        [MaxLength(100)]
        public string ProductCode { get; set; } = string.Empty;

        public decimal TotalManufacturedQuantity { get; set; }

        public DateTime DateOfManufacturing { get; set; }

        [MaxLength(20)]
        public string Unit { get; set; } = string.Empty;

        [MaxLength(100)]
        public string Location { get; set; } = string.Empty;

        [MaxLength(20)]
        public string ItemStatus { get; set; } = string.Empty;

        public DateTime? ExpiryDate { get; set; }

        [MaxLength(100)]
        public string? Location2 { get; set; } // CCE_0

        [MaxLength(100)]
        public string? Location3 { get; set; } // CCE_1

        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        public bool IsCompleted { get; set; } = false;

        public bool IsProcessed { get; set; } = false;
        public decimal EaQuantity { get; set; }
        
        public bool IsFpp { get; set; } = false;

        [MaxLength(100)]
        public string? LotNumber { get; set; }

        [MaxLength(255)]
        public string? DeviceId { get; set; }

        public Guid? EodTransactionId { get; set; }
    }
}
