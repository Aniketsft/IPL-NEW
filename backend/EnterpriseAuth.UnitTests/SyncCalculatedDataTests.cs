using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using EnterpriseAuth.Api.Core.Application.DTOs;
using EnterpriseAuth.Api.Core.Application.Common;
using EnterpriseAuth.Api.Core.Domain.Entities;
using EnterpriseAuth.Api.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Options;
using Moq;
using Xunit;

namespace EnterpriseAuth.UnitTests
{
    public class SyncCalculatedDataTests
    {
        private (EfSyncRepository repository, ScanProductionDbContext scanContext) CreateRepository()
        {
            var options1 = new DbContextOptionsBuilder<ApplicationDbContext>()
                .UseInMemoryDatabase(databaseName: Guid.NewGuid().ToString())
                .Options;
            var context = new ApplicationDbContext(options1);

            var options2 = new DbContextOptionsBuilder<ScanProductionDbContext>()
                .UseInMemoryDatabase(databaseName: Guid.NewGuid().ToString())
                .Options;
            var scanContext = new ScanProductionDbContext(options2);

            var mockConfig = new Mock<IConfiguration>();
            mockConfig.Setup(c => c.GetSection("ConnectionStrings")["Innodis"]).Returns("Server=test;Database=test;");

            var syncSettings = new SyncSettings { SyncWindowDays = 7 };
            var mockOptions = new Mock<IOptions<SyncSettings>>();
            mockOptions.Setup(o => o.Value).Returns(syncSettings);

            var repository = new EfSyncRepository(mockConfig.Object, context, scanContext, mockOptions.Object);
            return (repository, scanContext);
        }

        [Fact]
        public async Task PushUpdates_OverwriteSync_ResetsManufacturedQuantity_CurrentBehavior()
        {
            // This test captures the CURRENT behavior (the bug)
            var (repo, scanContext) = CreateRepository();

            // 1. Initial Sync of a Cut Entry
            var entryNo = "CUT-001";
            var pushRequest = new SyncPushRequestDto
            {
                DeviceId = "DEV-01",
                CutBulkEntries = new List<CutBulkEntryDto>
                {
                    new CutBulkEntryDto { EntryNumber = entryNo, Type = "Cuts", AmountKg = 100, CustomerCode = "C001" }
                }
            };

            await repo.PushUpdatesAsync(pushRequest);

            // Verify initial state
            var detail = await scanContext.SalesOrderDetailCutsBulk.FirstOrDefaultAsync(d => d.SoNumber == entryNo);
            Assert.NotNull(detail);
            Assert.Equal(0, detail.ManufacturedQuantity);

            // 2. Scan some quantity
            var scanPush = new SyncPushRequestDto
            {
                DeviceId = "DEV-01",
                Scans = new List<ProductionScanDto>
                {
                    new ProductionScanDto { SoNumber = entryNo, ItemCode = "PROD-CUT", ScanAmountKg = 10 }
                }
            };

            await repo.PushUpdatesAsync(scanPush);

            // Verify increment
            detail = await scanContext.SalesOrderDetailCutsBulk.FirstOrDefaultAsync(d => d.SoNumber == entryNo);
            Assert.Equal(10, detail.ManufacturedQuantity);

            // 3. Perform an "Overwrite Sync" (e.g. metadata update or re-sync)
            var overwritePush = new SyncPushRequestDto
            {
                DeviceId = "DEV-01",
                CutBulkEntries = new List<CutBulkEntryDto>
                {
                    new CutBulkEntryDto { EntryNumber = entryNo, Type = "Cuts", AmountKg = 100, CustomerCode = "C001" }
                }
            };

            await repo.PushUpdatesAsync(overwritePush);

            // VERIFY THE BUG: The quantity is reset to 0 because of Atomic Overwrite
            detail = await scanContext.SalesOrderDetailCutsBulk.FirstOrDefaultAsync(d => d.SoNumber == entryNo);
            
            // This assertion currently PASSES, proving the bug exists.
            Assert.Equal(0, detail.ManufacturedQuantity); 
            
            // But the scans are still there
            var scans = await scanContext.ProductionScans.Where(s => s.SoNumber == entryNo).ToListAsync();
            Assert.Single(scans);
        }

        [Fact]
        public async Task GetRefreshPackage_ShouldCalculateFromScans_DesiredBehavior()
        {
            // This test will fail until we implement the fix
            var (repo, scanContext) = CreateRepository();
            var entryNo = "CUT-002";

            // 1. Sync entry & scan
            await repo.PushUpdatesAsync(new SyncPushRequestDto
            {
                DeviceId = "DEV-01",
                CutBulkEntries = new List<CutBulkEntryDto> { new CutBulkEntryDto { EntryNumber = entryNo, Type = "Cuts", AmountKg = 100 } },
                Scans = new List<ProductionScanDto> { new ProductionScanDto { SoNumber = entryNo, ItemCode = "PROD-CUT", ScanAmountKg = 25 } }
            });

            // 2. Fetch via Refresh
            var refresh = await repo.GetRefreshPackageAsync("TEST_SITE");

            // Verify
            var detailDto = refresh.Details.FirstOrDefault(d => d.SoNumber == entryNo);
            Assert.NotNull(detailDto);
            
            // Currently this would likely be 25 because we JUST synced it, 
            // but if we overwrite it, it becomes 0.
            
            // 3. Overwrite
            await repo.PushUpdatesAsync(new SyncPushRequestDto
            {
                DeviceId = "DEV-01",
                CutBulkEntries = new List<CutBulkEntryDto> { new CutBulkEntryDto { EntryNumber = entryNo, Type = "Cuts", AmountKg = 100 } }
            });

            var refreshAfterOverwrite = await repo.GetRefreshPackageAsync("TEST_SITE");
            var detailDtoAfter = refreshAfterOverwrite.Details.FirstOrDefault(d => d.SoNumber == entryNo);
            
            // This SHOULD be 25 (calculated from scans), but currently it will be 0.
            Assert.Equal(25, detailDtoAfter?.Manufactured);
        }
    }
}
