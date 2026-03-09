using Microsoft.EntityFrameworkCore;
using EnterpriseAuth.Api.Core.Domain.Entities;

namespace EnterpriseAuth.Api.Infrastructure.Persistence
{
    public class ScanProductionDbContext : DbContext
    {
        public ScanProductionDbContext(DbContextOptions<ScanProductionDbContext> options) : base(options) { }

        public DbSet<ProductionScan> ProductionScans { get; set; }
        public DbSet<AuditLog> AuditLogs { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            base.OnModelCreating(modelBuilder);
            
            // Ensures the precision matches our plan
            modelBuilder.Entity<ProductionScan>()
                .Property(e => e.ScanAmountKg)
                .HasPrecision(18, 2);
        }
    }
}
