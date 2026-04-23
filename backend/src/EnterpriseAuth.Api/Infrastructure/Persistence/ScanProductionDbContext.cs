using Microsoft.EntityFrameworkCore;
using EnterpriseAuth.Api.Core.Domain.Entities;

namespace EnterpriseAuth.Api.Infrastructure.Persistence
{
    public class ScanProductionDbContext : DbContext
    {
        public ScanProductionDbContext(DbContextOptions<ScanProductionDbContext> options) : base(options) { }

        // --- ENTERPRISE TABLES ---
        public DbSet<SalesOrder> SalesOrders { get; set; }
        public DbSet<SalesOrderLine> SalesOrderLines { get; set; }
        public DbSet<ProductionScanTransaction> ProductionScanTransactions { get; set; }
        public DbSet<ProductionLineState> ProductionLineStates { get; set; }
        public DbSet<StagingEod> StagingEodRecords { get; set; }

        // --- TRANSACTION / STATUS TABLES (Kept Separately) ---
        public DbSet<OrderShipmentStatus> OrderShipmentStatuses { get; set; }
        public DbSet<OrderStatusHistory> OrderStatusHistories { get; set; }

        // --- EXCESS / BULK POOL ---
        public DbSet<Excess> Excesses { get; set; }

        // --- AUDIT ---
        public DbSet<AuditLog> AuditLogs { get; set; }
        public DbSet<LabelAudit> LabelAudits { get; set; }
        public DbSet<GlobalSetting> GlobalSettings { get; set; }
        public DbSet<Staging> StagingRecords { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            base.OnModelCreating(modelBuilder);
            
            // SalesOrders
            modelBuilder.Entity<SalesOrder>(entity =>
            {
                entity.HasKey(e => e.Id);
                entity.HasIndex(e => e.SourceOrderId).IsUnique();
                entity.HasIndex(e => new { e.SourceSystem, e.Status, e.IsArchived });
            });

            // SalesOrderLines
            modelBuilder.Entity<SalesOrderLine>(entity =>
            {
                entity.HasKey(e => e.Id);
                entity.Property(e => e.OrderedQuantity).HasPrecision(18, 5);
                entity.HasIndex(e => new { e.SalesOrderId, e.ItemCode });
                
                entity.HasOne(d => d.Order)
                    .WithMany(p => p.Lines)
                    .HasForeignKey(d => d.SalesOrderId)
                    .OnDelete(DeleteBehavior.Cascade);
            });

            // ProductionScanTransactions
            modelBuilder.Entity<ProductionScanTransaction>(entity =>
            {
                entity.HasKey(e => e.Id);
                entity.Property(e => e.ScanAmountKg).HasPrecision(18, 5);
                entity.HasIndex(e => e.SyncId).IsUnique();
                entity.HasIndex(e => new { e.SalesOrderLineId, e.IsDeleted, e.IsArchived });
            });

            // ProductionLineStates
            modelBuilder.Entity<ProductionLineState>(entity =>
            {
                entity.HasKey(e => e.SalesOrderLineId);
                entity.Property(e => e.TotalManufacturedQty).HasPrecision(18, 5);
                entity.Property(e => e.TotalPreparedQty).HasPrecision(18, 5);
                entity.Property(e => e.TotalValidatedQty).HasPrecision(18, 5);
                
                entity.HasOne(d => d.OrderLine)
                    .WithOne()
                    .HasForeignKey<ProductionLineState>(d => d.SalesOrderLineId)
                    .OnDelete(DeleteBehavior.Cascade);
            });

            // OrderShipmentStatus (Kept as separate table)
            modelBuilder.Entity<OrderShipmentStatus>(entity =>
            {
                entity.HasKey(e => e.Id);
                entity.HasIndex(e => e.SoNumber)
                    .IsUnique()
                    .HasDatabaseName("UQ_OrderShipmentStatus_SoNumber");
            });

            // OrderStatusHistory (Kept as separate table)
            modelBuilder.Entity<OrderStatusHistory>(entity =>
            {
                entity.HasKey(e => e.Id);
                entity.HasIndex(e => e.SoNumber)
                    .HasDatabaseName("IX_OrderStatusHistory_SoNumber");
            });

            // Excess (Bulk Pool Tracking)
            modelBuilder.Entity<Excess>(entity =>
            {
                entity.HasKey(e => e.Id);
                entity.Property(e => e.TotalManufacturedQuantity).HasPrecision(18, 5);
                entity.Property(e => e.AllocatedQuantity).HasPrecision(18, 5);
                entity.Property(e => e.RemainingExcess).HasPrecision(18, 5);
                entity.HasIndex(e => new { e.SourceBulkSoNumber, e.ItemCode })
                    .IsUnique()
                    .HasDatabaseName("UQ_Excess_BulkSO_Item");
                entity.HasIndex(e => new { e.DeliveryDate, e.ItemCode })
                    .HasDatabaseName("IX_Excess_Date_Item");
            });

            // AuditLogs
            modelBuilder.Entity<AuditLog>(entity =>
            {
                entity.HasIndex(e => new { e.EntityName, e.EntityIdString })
                    .HasDatabaseName("IX_AuditLogs_EntityLookup");
            });

            // LabelAudits
            modelBuilder.Entity<LabelAudit>(entity =>
            {
                entity.HasKey(e => e.Id);
                entity.HasIndex(e => e.LabelId).IsUnique();
                entity.Property(e => e.TotalWeight).HasPrecision(18, 5);
            });

            // GlobalSettings
            modelBuilder.Entity<GlobalSetting>(entity =>
            {
                entity.HasKey(e => e.Id);
                entity.Property(e => e.UpdatedAt).HasDefaultValueSql("GETUTCDATE()");
            });

            // Staging
            modelBuilder.Entity<Staging>(entity =>
            {
                entity.HasKey(e => e.Id);
                entity.Property(e => e.ZQTY_0).HasPrecision(18, 5);
                entity.HasIndex(e => e.ZSOHNUM_0);
            });

            // StagingEod
            modelBuilder.Entity<StagingEod>(entity =>
            {
                entity.HasKey(e => e.Id);
                entity.Property(e => e.TotalManufacturedQuantity).HasPrecision(18, 5);
                entity.HasIndex(e => e.WorkOrderNumber);
            });
        }
    }
}
