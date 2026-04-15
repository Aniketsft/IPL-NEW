using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    [Table("ProductionLineStates")]
    public class ProductionLineState
    {
        [Key]
        [Column("SalesOrderLineId")]
        public Guid SalesOrderLineId { get; set; }

        [Column("TotalManufacturedQty")]
        public decimal TotalManufacturedQty { get; set; }

        [Column("TotalPreparedQty")]
        public decimal TotalPreparedQty { get; set; }

        [Column("TotalValidatedQty")]
        public decimal TotalValidatedQty { get; set; }

        [Column("IsLineCompleted")]
        public bool IsLineCompleted { get; set; }

        [Column("IsPrepared")]
        public bool IsPrepared { get; set; }

        [Column("LastScanId")]
        public Guid? LastScanId { get; set; }

        [Column("UpdatedAt")]
        public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

        // Navigation
        [ForeignKey("SalesOrderLineId")]
        public SalesOrderLine OrderLine { get; set; } = null!;
    }
}
