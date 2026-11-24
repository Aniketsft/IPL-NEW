using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Security.Claims;
using System.Text.Json;
using System.Threading.Tasks;
using EnterpriseAuth.Api.Controllers;
using EnterpriseAuth.Api.Core.Application.Common;
using EnterpriseAuth.Api.Core.Application.DTOs;
using EnterpriseAuth.Api.Core.Application.Interfaces;
using EnterpriseAuth.Api.Core.Domain.Entities;
using EnterpriseAuth.Api.Core.Domain.Interfaces;
using EnterpriseAuth.Api.Infrastructure.Features.SnapshotManagement;
using EnterpriseAuth.Api.Infrastructure.Persistence;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;

namespace EnterpriseAuth.UnitTests
{
    public class SalesInvoiceStockSyncTests
    {
        private static ScanProductionDbContext CreateInMemoryDb()
        {
            var options = new DbContextOptionsBuilder<ScanProductionDbContext>()
                .UseInMemoryDatabase("SalesInvoiceStockSync_" + Guid.NewGuid())
                .ConfigureWarnings(w => w.Ignore(InMemoryEventId.TransactionIgnoredWarning))
                .Options;
            return new ScanProductionDbContext(options);
        }

        private static ClaimsPrincipal CreateUser(string username, string siteCode = "POD")
        {
            return new ClaimsPrincipal(new ClaimsIdentity(new[]
            {
                new Claim("username", username),
                new Claim("SiteCode", siteCode),
            }, "TestAuth"));
        }

        private static async Task<string> WriteGzipStockSnapshotAsync(
            string directory,
            string fileName,
            IEnumerable<SalesInvoiceItemStockDto> items)
        {
            Directory.CreateDirectory(directory);
            var path = Path.Combine(directory, fileName);
            await using var fs = new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.None);
            await using var gzip = new GZipStream(fs, CompressionLevel.Fastest);
            await JsonSerializer.SerializeAsync(gzip, items);
            return path;
        }

        private static SalesInvoiceController CreateSalesController(
            ScanProductionDbContext db,
            Mock<ISalesInvoiceRepository> repoMock,
            ISnapshotService? snapshotService,
            IX3SchemaProvider? schemaProvider,
            string shippingSite = "POD",
            string username = "driver1",
            string userSiteClaim = "POD")
        {
            var siteResolverMock = new Mock<ISiteContextResolver>();
            siteResolverMock
                .Setup(r => r.ResolveSiteContextAsync(It.IsAny<ClaimsPrincipal>(), It.IsAny<string?>(), It.IsAny<bool>()))
                .ReturnsAsync((new SiteContext
                {
                    ShippingSiteCode = shippingSite,
                    FinancialSiteCode = shippingSite,
                    RawSiteCode = shippingSite,
                }, null));

            var soapMock = new Mock<ISageX3SoapService>();

            var controller = new SalesInvoiceController(
                repoMock.Object,
                db,
                soapMock.Object,
                NullLogger<SalesInvoiceController>.Instance,
                siteResolverMock.Object,
                snapshotService,
                schemaProvider);

            controller.ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = CreateUser(username, userSiteClaim)
                }
            };

            return controller;
        }

        [Fact]
        public async Task Heartbeat_ResolvesExistingDeviceByHardwareIdHeader_AndPreservesConcreteSiteWhenCallerSendsAll()
        {
            using var db = CreateInMemoryDb();
            var deviceId = Guid.NewGuid().ToString().ToLowerInvariant();
            db.DeviceLocations.Add(new DeviceLocation
            {
                DeviceId = deviceId,
                DeviceName = "HM5",
                HardwareModel = "Infinix X6850",
                HardwareIdentifier = "android-hw-57",
                SiteCode = "SCP",
                WarehouseCode = "WRH57",
                LocationCode = "57",
                IsActive = true,
                IsLicensed = true,
                LicenseStatus = "VALID",
                UpdatedAt = DateTime.UtcNow,
            });
            await db.SaveChangesAsync();

            var syncRepoMock = new Mock<ISyncRepository>();
            var controller = new DevicesController(db, syncRepoMock.Object)
            {
                ControllerContext = new ControllerContext
                {
                    HttpContext = new DefaultHttpContext
                    {
                        User = CreateUser("admin_all", "ALL")
                    }
                }
            };

            var action = await controller.Heartbeat(
                new DeviceHeartbeatRequestDto
                {
                    DeviceId = string.Empty,
                    DeviceName = string.Empty,
                    HardwareModel = "Infinix X6850",
                    SiteCode = "ALL",
                },
                headerDeviceId: null,
                headerHardwareId: "android-hw-57");

            var ok = Assert.IsType<OkObjectResult>(action.Result);
            var dto = Assert.IsType<DeviceLocationDto>(ok.Value);
            Assert.Equal(deviceId, dto.DeviceId);
            Assert.Equal("SCP", dto.SiteCode);
            Assert.Equal("57", dto.LocationCode);
            Assert.Equal("WRH57", dto.WarehouseCode);
        }

        [Fact]
        public async Task Heartbeat_BrandNewDeviceWithAllSite_DefaultsSiteToPod()
        {
            using var db = CreateInMemoryDb();
            var syncRepoMock = new Mock<ISyncRepository>();
            var controller = new DevicesController(db, syncRepoMock.Object)
            {
                ControllerContext = new ControllerContext
                {
                    HttpContext = new DefaultHttpContext
                    {
                        User = CreateUser("operator_all", "ALL")
                    }
                }
            };

            var action = await controller.Heartbeat(
                new DeviceHeartbeatRequestDto
                {
                    DeviceId = string.Empty,
                    HardwareModel = "Infinix X6850",
                    HardwareIdentifier = "new-android-hw",
                    SiteCode = "ALL",
                },
                headerDeviceId: null,
                headerHardwareId: "new-android-hw");

            var ok = Assert.IsType<OkObjectResult>(action.Result);
            var dto = Assert.IsType<DeviceLocationDto>(ok.Value);
            Assert.True(Guid.TryParse(dto.DeviceId, out _));
            Assert.Equal("POD", dto.SiteCode);
            Assert.Equal("POD", dto.LocationCode);
            Assert.Equal("new-android-hw", dto.HardwareIdentifier);
        }

        [Fact]
        public async Task GetItemStockDetails_UnassignedTablet_ReturnsEmptyWithLorryRequiredHeaderEvenWithIfNoneMatch()
        {
            using var db = CreateInMemoryDb();
            var deviceId = Guid.NewGuid().ToString().ToLowerInvariant();
            db.DeviceLocations.Add(new DeviceLocation
            {
                DeviceId = deviceId,
                DeviceName = "HM1",
                HardwareIdentifier = "hw-unassigned",
                SiteCode = "POD",
                LocationCode = "POD",
                WarehouseCode = "POD",
                IsActive = true,
                UpdatedAt = DateTime.UtcNow,
            });
            await db.SaveChangesAsync();

            var repoMock = new Mock<ISalesInvoiceRepository>();
            var snapshotMock = new Mock<ISnapshotService>();
            var schemaMock = new Mock<IX3SchemaProvider>();
            schemaMock.Setup(s => s.GetSchemaName()).Returns("INLDRYRUN");

            var controller = CreateSalesController(db, repoMock.Object == null ? repoMock : repoMock, snapshotMock.Object, schemaMock.Object);
            controller.Request.Headers["X-Device-Id"] = deviceId;
            controller.Request.Headers.IfNoneMatch = "\"stale_etag_57\"";

            var result = await controller.GetItemStockDetails("POD");

            var ok = Assert.IsType<OkObjectResult>(result);
            var items = Assert.IsAssignableFrom<IEnumerable<SalesInvoiceItemStockDto>>(ok.Value);
            Assert.Empty(items);
            Assert.Equal("true", controller.Response.Headers["X-Lorry-Required"].ToString());
            snapshotMock.Verify(
                s => s.GetOrUpdateSnapshotAsync(
                    It.IsAny<string>(),
                    It.IsAny<string>(),
                    It.IsAny<Func<Task<string>>>(),
                    It.IsAny<Func<Task<IEnumerable<SalesInvoiceItemStockDto>>>>()),
                Times.Never);
        }

        [Fact]
        public async Task GetItemStockDetails_StaleUuid_FallsBackToHardwareIdHeader_AndFiltersAndSetsLorryHeaders()
        {
            using var db = CreateInMemoryDb();
            db.DeviceLocations.Add(new DeviceLocation
            {
                DeviceId = Guid.NewGuid().ToString().ToLowerInvariant(),
                DeviceName = "HM7",
                HardwareModel = "Infinix X6850",
                HardwareIdentifier = "hw-device-57",
                SiteCode = "POD",
                LocationCode = "57",
                WarehouseCode = "WRH57",
                AssignedUserName = "driver7",
                IsActive = true,
                UpdatedAt = DateTime.UtcNow,
            });
            await db.SaveChangesAsync();

            var tempDir = Path.Combine(AppContext.BaseDirectory, "tmp_snap_" + Guid.NewGuid().ToString("N"));
            try
            {
                var gzPath = await WriteGzipStockSnapshotAsync(tempDir, "stock.gz", new[]
                {
                    new SalesInvoiceItemStockDto { ItemCode = "SKU57", ItemName = "Chicken 57", Location = "57", Warehouse = "WRH57", SiteCode = "POD", TotalQty = 12 },
                    new SalesInvoiceItemStockDto { ItemCode = "SKU99", ItemName = "Chicken 99", Location = "99", Warehouse = "WRH99", SiteCode = "POD", TotalQty = 8 },
                });

                var repoMock = new Mock<ISalesInvoiceRepository>();
                var snapshotMock = new Mock<ISnapshotService>();
                snapshotMock
                    .Setup(s => s.GetOrUpdateSnapshotAsync(
                        "POD",
                        "StockDetails_INLDRYRUN",
                        It.IsAny<Func<Task<string>>>(),
                        It.IsAny<Func<Task<IEnumerable<SalesInvoiceItemStockDto>>>>()))
                    .ReturnsAsync(new SnapshotFileResult(gzPath, "\"wm-100\"", true, DateTime.UtcNow));

                var schemaMock = new Mock<IX3SchemaProvider>();
                schemaMock.Setup(s => s.GetSchemaName()).Returns("INLDRYRUN");

                var controller = CreateSalesController(db, repoMock, snapshotMock.Object, schemaMock.Object);
                controller.Request.Headers["X-Device-Id"] = Guid.NewGuid().ToString(); // stale/mismatched UUID
                controller.Request.Headers["X-Device-Hardware-Id"] = "hw-device-57";

                var result = await controller.GetItemStockDetails("POD");

                var ok = Assert.IsType<OkObjectResult>(result);
                var items = Assert.IsAssignableFrom<IEnumerable<SalesInvoiceItemStockDto>>(ok.Value).ToList();
                var single = Assert.Single(items);
                Assert.Equal("SKU57", single.ItemCode);
                Assert.Equal("57", controller.Response.Headers["X-Assigned-Lorry"].ToString());
                Assert.Equal("WRH57", controller.Response.Headers["X-Assigned-Warehouse"].ToString());
                Assert.Contains("_INLDRYRUN_57\"", controller.Response.Headers.ETag.ToString());
            }
            finally
            {
                if (Directory.Exists(tempDir))
                {
                    Directory.Delete(tempDir, recursive: true);
                }
            }
        }

        [Fact]
        public async Task GetItemStockDetails_IsolatesSnapshotAndETagBySchema_AndPreservesLorryHeadersOn304()
        {
            using var db = CreateInMemoryDb();
            var deviceId = Guid.NewGuid().ToString().ToLowerInvariant();
            db.DeviceLocations.Add(new DeviceLocation
            {
                DeviceId = deviceId,
                DeviceName = "HM8",
                HardwareIdentifier = "hw-88",
                SiteCode = "POD",
                LocationCode = "57",
                WarehouseCode = "WRH57",
                IsActive = true,
                UpdatedAt = DateTime.UtcNow,
            });
            await db.SaveChangesAsync();

            var tempDir = Path.Combine(AppContext.BaseDirectory, "tmp_snap_" + Guid.NewGuid().ToString("N"));
            try
            {
                var dryGz = await WriteGzipStockSnapshotAsync(tempDir, "dry.gz", new[]
                {
                    new SalesInvoiceItemStockDto { ItemCode = "DRY1", Location = "57", Warehouse = "WRH57", SiteCode = "POD", TotalQty = 5 },
                });
                var prodGz = await WriteGzipStockSnapshotAsync(tempDir, "prod.gz", new[]
                {
                    new SalesInvoiceItemStockDto { ItemCode = "PROD1", Location = "57", Warehouse = "WRH57", SiteCode = "POD", TotalQty = 9 },
                });

                var activeSchema = "INLDRYRUN";
                var schemaMock = new Mock<IX3SchemaProvider>();
                schemaMock.Setup(s => s.GetSchemaName()).Returns(() => activeSchema);

                var snapshotMock = new Mock<ISnapshotService>();
                snapshotMock
                    .Setup(s => s.GetOrUpdateSnapshotAsync(
                        "POD",
                        "StockDetails_INLDRYRUN",
                        It.IsAny<Func<Task<string>>>(),
                        It.IsAny<Func<Task<IEnumerable<SalesInvoiceItemStockDto>>>>()))
                    .ReturnsAsync(new SnapshotFileResult(dryGz, "\"same-wm\"", true, DateTime.UtcNow));
                snapshotMock
                    .Setup(s => s.GetOrUpdateSnapshotAsync(
                        "POD",
                        "StockDetails_INLPROD",
                        It.IsAny<Func<Task<string>>>(),
                        It.IsAny<Func<Task<IEnumerable<SalesInvoiceItemStockDto>>>>()))
                    .ReturnsAsync(new SnapshotFileResult(prodGz, "\"same-wm\"", true, DateTime.UtcNow));

                var repoMock = new Mock<ISalesInvoiceRepository>();

                // 1. Fetch INLDRYRUN
                var dryController = CreateSalesController(db, repoMock, snapshotMock.Object, schemaMock.Object);
                dryController.Request.Headers["X-Device-Id"] = deviceId;
                var dryResult = Assert.IsType<OkObjectResult>(await dryController.GetItemStockDetails("POD"));
                var dryItems = Assert.IsAssignableFrom<IEnumerable<SalesInvoiceItemStockDto>>(dryResult.Value).ToList();
                var dryEtag = dryController.Response.Headers.ETag.ToString();
                Assert.Equal("DRY1", Assert.Single(dryItems).ItemCode);
                Assert.Contains("_INLDRYRUN_57\"", dryEtag);

                // 2. Switch schema to INLPROD with INLDRYRUN's ETag -> must NOT 304 and must serve PROD1
                activeSchema = "INLPROD";
                var prodController = CreateSalesController(db, repoMock, snapshotMock.Object, schemaMock.Object);
                prodController.Request.Headers["X-Device-Id"] = deviceId;
                prodController.Request.Headers.IfNoneMatch = dryEtag;
                var prodResult = Assert.IsType<OkObjectResult>(await prodController.GetItemStockDetails("POD"));
                var prodItems = Assert.IsAssignableFrom<IEnumerable<SalesInvoiceItemStockDto>>(prodResult.Value).ToList();
                var prodEtag = prodController.Response.Headers.ETag.ToString();
                Assert.Equal("PROD1", Assert.Single(prodItems).ItemCode);
                Assert.Contains("_INLPROD_57\"", prodEtag);
                Assert.NotEqual(dryEtag, prodEtag);

                // 3. Matching INLPROD ETag -> 304 Not Modified still carries X-Assigned-Lorry & X-Assigned-Warehouse headers
                var cachedController = CreateSalesController(db, repoMock, snapshotMock.Object, schemaMock.Object);
                cachedController.Request.Headers["X-Device-Id"] = deviceId;
                cachedController.Request.Headers.IfNoneMatch = prodEtag;
                var cachedResult = await cachedController.GetItemStockDetails("POD");
                var status = Assert.IsType<StatusCodeResult>(cachedResult);
                Assert.Equal(304, status.StatusCode);
                Assert.Equal("57", cachedController.Response.Headers["X-Assigned-Lorry"].ToString());
                Assert.Equal("WRH57", cachedController.Response.Headers["X-Assigned-Warehouse"].ToString());
            }
            finally
            {
                if (Directory.Exists(tempDir))
                {
                    Directory.Delete(tempDir, recursive: true);
                }
            }
        }

        [Fact]
        public async Task GetItemStockDetails_SiteScopedHardwareModelFallback_PrefersMatchingSiteDevice()
        {
            using var db = CreateInMemoryDb();
            db.DeviceLocations.AddRange(
                new DeviceLocation
                {
                    DeviceId = Guid.NewGuid().ToString().ToLowerInvariant(),
                    DeviceName = "HM10",
                    HardwareModel = "Infinix X6528",
                    SiteCode = "SCP",
                    LocationCode = "SCP",
                    WarehouseCode = "SCP",
                    IsActive = true,
                    UpdatedAt = DateTime.UtcNow.AddMinutes(5),
                },
                new DeviceLocation
                {
                    DeviceId = Guid.NewGuid().ToString().ToLowerInvariant(),
                    DeviceName = "HM11",
                    HardwareModel = "Infinix X6528",
                    SiteCode = "POD",
                    LocationCode = "57",
                    WarehouseCode = "WRH57",
                    IsActive = true,
                    UpdatedAt = DateTime.UtcNow,
                });
            await db.SaveChangesAsync();

            var repoMock = new Mock<ISalesInvoiceRepository>();
            repoMock.Setup(r => r.GetItemStockDetailsAsync("POD"))
                .ReturnsAsync(new[]
                {
                    new SalesInvoiceItemStockDto { ItemCode = "POD57", Location = "57", Warehouse = "WRH57", SiteCode = "POD", TotalQty = 3 },
                    new SalesInvoiceItemStockDto { ItemCode = "POD99", Location = "99", Warehouse = "WRH99", SiteCode = "POD", TotalQty = 4 },
                });

            var controller = CreateSalesController(db, repoMock, snapshotService: null, schemaProvider: null, shippingSite: "POD");
            controller.Request.Headers["X-Device-Id"] = "Infinix X6528";

            var result = Assert.IsType<OkObjectResult>(await controller.GetItemStockDetails("POD"));
            var items = Assert.IsAssignableFrom<IEnumerable<SalesInvoiceItemStockDto>>(result.Value).ToList();
            Assert.Equal("POD57", Assert.Single(items).ItemCode);
            Assert.Equal("57", controller.Response.Headers["X-Assigned-Lorry"].ToString());
        }
    }
}
