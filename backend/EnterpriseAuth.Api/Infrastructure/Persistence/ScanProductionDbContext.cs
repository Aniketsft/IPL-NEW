using Microsoft.EntityFrameworkCore;
using EnterpriseAuth.Api.Core.Domain.Entities;

namespace EnterpriseAuth.Api.Infrastructure.Persistence
{
    public class ScanProductionDbContext : DbContext
    {
        public ScanProductionDbContext(DbContextOptions<ScanProductionDbContext> options) : base(options) { }

        public DbSet<ProductionScan> ProductionScans { get; set; }
        public DbSet<CutBulkEntry> CutBulkEntries { get; set; }
        public DbSet<SalesOrderDetailCutsBulk> SalesOrderDetailCutsBulk { get; set; }
        public DbSet<AuditLog> AuditLogs { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            base.OnModelCreating(modelBuilder);
            
            // Ensures the precision matches our plan
            modelBuilder.Entity<ProductionScan>()
                .Property(e => e.ScanAmountKg)
                .HasPrecision(18, 2);

            // Configure CutBulkEntry in ScanProduction (v12 Optimized Meta-Mapping)
            modelBuilder.Entity<CutBulkEntry>(entity =>
            {
                entity.ToTable("cut_bulk_entries");
                entity.HasKey(e => e.Id);
                
                // PERFORMANCE: Optimized indexes for Atomic Overwrite and Sync tracking
                entity.HasIndex(e => e.EntryNumber).IsUnique();
                entity.HasIndex(e => new { e.DeviceId, e.SyncStatus }); 
                
                entity.Property(e => e.AmountKg).HasPrecision(18, 2);
            });

            // Configure SalesOrderDetailCutsBulk in ScanProduction (v13 Isolation)
            modelBuilder.Entity<SalesOrderDetailCutsBulk>(entity =>
            {
                entity.ToTable("salesorderdetailscutsbulk");
                entity.HasKey(e => e.Id);
                
                // PERFORMANCE: Optimized composite index for detail reconciliation
                entity.HasIndex(e => new { e.SoNumber, e.ItemCode });
                
                entity.Property(e => e.Quantity).HasPrecision(18, 2);
            });
        }
    }
}
