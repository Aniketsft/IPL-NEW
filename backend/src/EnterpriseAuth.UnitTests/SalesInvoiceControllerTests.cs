using System;
using System.Collections.Generic;
using System.Security.Claims;
using System.Threading.Tasks;
using EnterpriseAuth.Api.Controllers;
using EnterpriseAuth.Api.Core.Application.DTOs;
using EnterpriseAuth.Api.Core.Application.Interfaces;
using EnterpriseAuth.Api.Core.Application.Services;
using EnterpriseAuth.Api.Infrastructure.Persistence;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Moq;
using Xunit;

using Microsoft.Extensions.Logging;

namespace EnterpriseAuth.UnitTests
{
    public class SalesInvoiceControllerTests
    {
        private readonly Mock<ISalesInvoiceRepository> _repoMock;
        private readonly Mock<ISageX3SoapService> _soapMock;
        private readonly Mock<ILogger<SalesInvoiceController>> _loggerMock;
        private readonly ScanProductionDbContext _dbContext;

        public SalesInvoiceControllerTests()
        {
            _repoMock = new Mock<ISalesInvoiceRepository>();
            _soapMock = new Mock<ISageX3SoapService>();
            _loggerMock = new Mock<ILogger<SalesInvoiceController>>();

            var options = new DbContextOptionsBuilder<ScanProductionDbContext>()
                .UseInMemoryDatabase(databaseName: "TestSalesInvoiceDb_" + Guid.NewGuid())
                .ConfigureWarnings(w => w.Ignore(Microsoft.EntityFrameworkCore.Diagnostics.InMemoryEventId.TransactionIgnoredWarning))
                .Options;
            _dbContext = new ScanProductionDbContext(options);
        }

        private SalesInvoiceController CreateControllerWithUser(string? siteClaim = null)
        {
            var siteResolver = new SiteContextResolver(_repoMock.Object, Mock.Of<ILogger<SiteContextResolver>>());
            var controller = new SalesInvoiceController(_repoMock.Object, _dbContext, _soapMock.Object, _loggerMock.Object, siteResolver);

            var claims = new List<Claim>();
            if (siteClaim != null)
            {
                claims.Add(new Claim("SiteCode", siteClaim));
            }

            var identity = new ClaimsIdentity(claims, "TestAuth");
            var user = new ClaimsPrincipal(identity);

            controller.ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext { User = user }
            };

            return controller;
        }

        [Fact]
        public async Task GetItemStockDetails_WithNoQueryParam_UsesUserSiteClaim()
        {
            // Arrange
            var controller = CreateControllerWithUser("IPL");
            _repoMock.Setup(r => r.GetItemStockDetailsAsync("IPL"))
                .ReturnsAsync(new List<SalesInvoiceItemStockDto>());

            // Act
            var result = await controller.GetItemStockDetails(null);

            // Assert
            var okResult = Assert.IsType<OkObjectResult>(result);
            _repoMock.Verify(r => r.GetItemStockDetailsAsync("IPL"), Times.Once);
        }

        [Fact]
        public async Task GetItemStockDetails_WithQueryParam_UsesQueryParamWhenUserHasAll()
        {
            // Arrange
            var controller = CreateControllerWithUser("ALL");
            _repoMock.Setup(r => r.GetItemStockDetailsAsync("SCG"))
                .ReturnsAsync(new List<SalesInvoiceItemStockDto>());

            // Act
            var result = await controller.GetItemStockDetails("SCG");

            // Assert
            var okResult = Assert.IsType<OkObjectResult>(result);
            _repoMock.Verify(r => r.GetItemStockDetailsAsync("SCG"), Times.Once);
        }

        [Fact]
        public async Task GetItemStockDetails_WithNoParamAndNoClaim_ReturnsForbidden()
        {
            // Arrange
            var controller = CreateControllerWithUser(null);

            // Act
            var result = await controller.GetItemStockDetails(null);

            // Assert
            var objectResult = Assert.IsType<ObjectResult>(result);
            Assert.Equal(StatusCodes.Status403Forbidden, objectResult.StatusCode);
        }

        [Fact]
        public async Task GetItemStockDetails_WithNoParamAndAllClaim_ReturnsBadRequest()
        {
            // Arrange
            var controller = CreateControllerWithUser("ALL");

            // Act
            var result = await controller.GetItemStockDetails(null);

            // Assert
            Assert.IsType<BadRequestObjectResult>(result);
        }

        [Fact]
        public async Task GetItemStockDetails_WithAssignedDevice_FiltersStrictlyToSingleSiteAndLorry_IncludingAQRStatuses()
        {
            var devId = Guid.NewGuid().ToString();
            _dbContext.DeviceLocations.Add(new EnterpriseAuth.Api.Core.Domain.Entities.DeviceLocation
            {
                DeviceId = devId,
                DeviceName = "HM4",
                SiteCode = "SCG",
                WarehouseCode = "N3",
                LocationCode = "N3",
                IsActive = true,
                IsLicensed = true,
                LicenseStatus = "VALID"
            });
            await _dbContext.SaveChangesAsync();

            var controller = CreateControllerWithUser("SCG");
            controller.ControllerContext.HttpContext.Request.Headers["X-Device-Id"] = devId;

            _repoMock.Setup(r => r.GetItemStockDetailsAsync("SCG"))
                .ReturnsAsync(new List<SalesInvoiceItemStockDto>
                {
                    new() { SiteCode = "SCG", Warehouse = "N3", Location = "N3", ItemCode = "SKU1", LotNumber = "L1", StockStatus = "A", TotalQty = 10 },
                    new() { SiteCode = "SCG", Warehouse = "N3", Location = "N3", ItemCode = "SKU1", LotNumber = "L2", StockStatus = "Q", TotalQty = 2 },
                    new() { SiteCode = "SCG", Warehouse = "N3", Location = "N3", ItemCode = "SKU1", LotNumber = "L3", StockStatus = "R", TotalQty = 1 },
                    new() { SiteCode = "SCG", Warehouse = "N6", Location = "N6", ItemCode = "SKU2", LotNumber = "L4", StockStatus = "A", TotalQty = 50 },
                    new() { SiteCode = "POD", Warehouse = "N3", Location = "N3", ItemCode = "SKU3", LotNumber = "L5", StockStatus = "A", TotalQty = 5 },
                });

            var result = await controller.GetItemStockDetails(null);

            var ok = Assert.IsType<OkObjectResult>(result);
            var items = new List<SalesInvoiceItemStockDto>(Assert.IsAssignableFrom<IEnumerable<SalesInvoiceItemStockDto>>(ok.Value));
            Assert.Equal(3, items.Count);
            Assert.All(items, i => Assert.Equal("SCG", i.SiteCode));
            Assert.All(items, i => Assert.Equal("N3", i.Location));
            Assert.Contains(items, i => i.StockStatus == "A");
            Assert.Contains(items, i => i.StockStatus == "Q");
            Assert.Contains(items, i => i.StockStatus == "R");
            Assert.Equal("N3", controller.Response.Headers["X-Assigned-Lorry"].ToString());
        }

        [Fact]
        public async Task GetItemStockDetails_WithUnassignedDevice_ReturnsEmptyAndSetsLorryRequiredHeader()
        {
            var devId = Guid.NewGuid().ToString();
            _dbContext.DeviceLocations.Add(new EnterpriseAuth.Api.Core.Domain.Entities.DeviceLocation
            {
                DeviceId = devId,
                DeviceName = "HM4",
                SiteCode = "SCG",
                WarehouseCode = "SCG",
                LocationCode = "SCG",
                IsActive = true,
                IsLicensed = true,
                LicenseStatus = "VALID"
            });
            await _dbContext.SaveChangesAsync();

            var controller = CreateControllerWithUser("SCG");
            controller.ControllerContext.HttpContext.Request.Headers["X-Device-Id"] = devId;

            var result = await controller.GetItemStockDetails(null);

            var ok = Assert.IsType<OkObjectResult>(result);
            var items = new List<SalesInvoiceItemStockDto>(Assert.IsAssignableFrom<IEnumerable<SalesInvoiceItemStockDto>>(ok.Value));
            Assert.Empty(items);
            Assert.Equal("true", controller.Response.Headers["X-Lorry-Required"].ToString());
            _repoMock.Verify(r => r.GetItemStockDetailsAsync(It.IsAny<string>()), Times.Never);
        }

        [Fact]
        public async Task SyncInvoice_RejectsWrongLorryAndNonApprovedStockStatus()
        {
            var devId = Guid.NewGuid().ToString();
            _dbContext.DeviceLocations.Add(new EnterpriseAuth.Api.Core.Domain.Entities.DeviceLocation
            {
                DeviceId = devId,
                DeviceName = "HM4",
                SiteCode = "SCG",
                WarehouseCode = "N3",
                LocationCode = "N3",
                IsActive = true,
                IsLicensed = true,
                LicenseStatus = "VALID"
            });
            await _dbContext.SaveChangesAsync();

            var controller = CreateControllerWithUser("SCG");
            controller.ControllerContext.HttpContext.Request.Headers["X-Device-Id"] = devId;

            var nonApprovedPayload = new SalesInvoiceSyncDto
            {
                InvoiceId = "INV-TEST-1",
                SalesSite = "SCG",
                ShippingSite = "SCG",
                DeviceId = devId,
                Lines = new List<SalesInvoiceLineDto>
                {
                    new() { LineNo = 1, Sku = "SKU1", Quantity = 1, BasePrice = 100, Total = 100, Warehouse = "N3", Location = "N3", StockStatus = "Q" }
                }
            };
            var badStatusResult = await controller.SyncInvoice(nonApprovedPayload);
            Assert.IsType<BadRequestObjectResult>(badStatusResult);

            var wrongLorryPayload = new SalesInvoiceSyncDto
            {
                InvoiceId = "INV-TEST-2",
                SalesSite = "SCG",
                ShippingSite = "SCG",
                DeviceId = devId,
                Lines = new List<SalesInvoiceLineDto>
                {
                    new() { LineNo = 1, Sku = "SKU1", Quantity = 1, BasePrice = 100, Total = 100, Warehouse = "N6", Location = "N6", StockStatus = "A" }
                }
            };
            var wrongLorryResult = await controller.SyncInvoice(wrongLorryPayload);
            var forbidObj = Assert.IsType<ObjectResult>(wrongLorryResult);
            Assert.Equal(StatusCodes.Status403Forbidden, forbidObj.StatusCode);
        }

        [Fact]
        public async Task SyncInvoice_MultiLotSameSku_PreservesDistinctLotsAndLineNosInStaging()
        {
            var devId = Guid.NewGuid().ToString();
            _dbContext.DeviceLocations.Add(new EnterpriseAuth.Api.Core.Domain.Entities.DeviceLocation
            {
                DeviceId = devId,
                DeviceName = "HM4",
                SiteCode = "SCG",
                WarehouseCode = "N3",
                LocationCode = "N3",
                IsActive = true,
                IsLicensed = true,
                LicenseStatus = "VALID"
            });
            await _dbContext.SaveChangesAsync();

            var controller = CreateControllerWithUser("SCG");
            controller.ControllerContext.HttpContext.Request.Headers["X-Device-Id"] = devId;

            _soapMock
                .Setup(s => s.ImportSalesInvoiceAsync(It.IsAny<EnterpriseAuth.Api.Core.Domain.Entities.StagingSalesInvoiceHeader>()))
                .ReturnsAsync(new X3ImportResult { Success = true, DocumentId = "X3-INV-MULTILOT-1" });

            var payload = new SalesInvoiceSyncDto
            {
                InvoiceId = "HISC01-MULTILOT-1",
                SalesSite = "SCG",
                ShippingSite = "SCG",
                CustomerCode = "CUST001",
                DeviceId = devId,
                Lines = new List<SalesInvoiceLineDto>
                {
                    new() { LineNo = 1, Sku = "SKU1", Name = "Chicken", Quantity = 10, BasePrice = 100, Total = 1000, Warehouse = "N3", Location = "N3", LotNumber = "LOT-A", StockStatus = "A" },
                    new() { LineNo = 1, Sku = "SKU1", Name = "Chicken", Quantity = 8, BasePrice = 100, Total = 800, Warehouse = "N3", Location = "N3", LotNumber = "LOT-B", StockStatus = "A" }
                }
            };

            var res = await controller.SyncInvoice(payload);
            Assert.IsType<OkObjectResult>(res);

            var stagedLines = await Microsoft.EntityFrameworkCore.EntityFrameworkQueryableExtensions.ToListAsync(
                _dbContext.StagingSalesInvoiceLines);
            Assert.Equal(2, stagedLines.Count);
            Assert.Contains(stagedLines, l => l.LotNumber == "LOT-A" && l.Quantity == 10);
            Assert.Contains(stagedLines, l => l.LotNumber == "LOT-B" && l.Quantity == 8);
            Assert.Equal(2, System.Linq.Enumerable.Distinct(System.Linq.Enumerable.Select(stagedLines, l => l.LineNo)).Count());
        }

        [Theory]
        [InlineData("A", "RET", null, "A")]
        [InlineData("R", "DEF", null, "R")]
        [InlineData("Q", "EXP", null, "Q")]
        [InlineData("R1", "DAMAGED", null, "R")]
        [InlineData("Q1", "EXPIRED", null, "Q")]
        [InlineData("A", "DEF", null, "R")]
        [InlineData("A", "EXP", null, "Q")]
        [InlineData("", "", "DEF", "R")]
        [InlineData("", "", "EXP", "Q")]
        [InlineData(null, null, null, "A")]
        public void ResolveMiscReceiptStockStatus_EnforcesNormalDamagedExpiredRules(
            string? stockStatus,
            string? returnCondition,
            string? headerReason,
            string expected)
        {
            var actual = SageX3SoapService.ResolveMiscReceiptStockStatus(stockStatus, returnCondition, headerReason);
            Assert.Equal(expected, actual);
        }

        [Theory]
        [InlineData("R", null, "Damaged Return")]
        [InlineData("Q", null, "Expired / Quarantine Return")]
        [InlineData("A", null, "Restockable Return")]
        [InlineData("Q", "Expired", "Expired")]
        public void ResolveMiscReceiptDescription_FormatsConditionOrDefault(
            string sta,
            string? returnCondition,
            string expected)
        {
            var actual = SageX3SoapService.ResolveMiscReceiptDescription(sta, returnCondition);
            Assert.Equal(expected, actual);
        }

        [Fact]
        public async Task SyncCreditNote_CustomerReturn_ForwardsARQStatusesToMiscReceipt()
        {
            var devId = Guid.NewGuid().ToString();
            _dbContext.DeviceLocations.Add(new EnterpriseAuth.Api.Core.Domain.Entities.DeviceLocation
            {
                DeviceId = devId,
                DeviceName = "HM4",
                SiteCode = "SCG",
                WarehouseCode = "N3",
                LocationCode = "N3",
                IsActive = true,
                IsLicensed = true,
                LicenseStatus = "VALID"
            });
            await _dbContext.SaveChangesAsync();

            _repoMock.Setup(r => r.GetFinancialSiteForSalesSiteAsync("SCG"))
                .ReturnsAsync("CGD");

            EnterpriseAuth.Api.Core.Domain.Entities.StagingSalesInvoiceHeader? capturedHeader = null;
            List<EnterpriseAuth.Api.Core.Domain.Entities.StagingSalesInvoiceLine>? capturedLines = null;

            _soapMock
                .Setup(s => s.ImportCreditNoteAsync(It.IsAny<EnterpriseAuth.Api.Core.Domain.Entities.StagingSalesInvoiceHeader>()))
                .ReturnsAsync(new X3ImportResult { Success = true, DocumentId = "X3-CRN-99" });

            _soapMock
                .Setup(s => s.ImportMiscReceiptAsync(
                    It.IsAny<EnterpriseAuth.Api.Core.Domain.Entities.StagingSalesInvoiceHeader>(),
                    It.IsAny<List<EnterpriseAuth.Api.Core.Domain.Entities.StagingSalesInvoiceLine>>()))
                .Callback<EnterpriseAuth.Api.Core.Domain.Entities.StagingSalesInvoiceHeader, List<EnterpriseAuth.Api.Core.Domain.Entities.StagingSalesInvoiceLine>>(
                    (h, l) =>
                    {
                        capturedHeader = h;
                        capturedLines = l;
                    })
                .ReturnsAsync(new X3ImportResult { Success = true, DocumentId = "X3-SMR-99" });

            var controller = CreateControllerWithUser("SCG");
            controller.ControllerContext.HttpContext.Request.Headers["X-Device-Id"] = devId;

            var payload = new CreditNoteSyncDto
            {
                CreditNoteId = "RTN-ARQ-001",
                CreditNoteType = "RETURN",
                Category = 3,
                StockTransaction = 1,
                SalesSite = "SCG",
                ShippingSite = "SCG",
                CustomerCode = "CUST001",
                CustomerName = "Test Customer",
                GrandTotal = 300.0,
                DeviceId = devId,
                Reason = "EXP",
                Lines = new List<CreditNoteLineSyncDto>
                {
                    new() { LineNo = 1000, Sku = "SKU-NORM", Quantity = 1, BasePrice = 100, Total = 100, Warehouse = "N3", Location = "N3", StockStatus = "A", ReturnCondition = "RET" },
                    new() { LineNo = 2000, Sku = "SKU-DMG", Quantity = 2, BasePrice = 50, Total = 100, Warehouse = "N3", Location = "N3", StockStatus = "R", ReturnCondition = "DEF" },
                    new() { LineNo = 3000, Sku = "SKU-EXP", Quantity = 1, BasePrice = 100, Total = 100, Warehouse = "N3", Location = "N3", StockStatus = "Q", ReturnCondition = "EXP" }
                }
            };

            var res = await controller.SyncCreditNote(payload);

            Assert.IsType<OkObjectResult>(res);
            Assert.NotNull(capturedHeader);
            Assert.NotNull(capturedLines);
            Assert.Equal(3, capturedLines!.Count);
            Assert.Equal("A", capturedLines.Single(l => l.Sku == "SKU-NORM").StockStatus);
            Assert.Equal("R", capturedLines.Single(l => l.Sku == "SKU-DMG").StockStatus);
            Assert.Equal("Q", capturedLines.Single(l => l.Sku == "SKU-EXP").StockStatus);
        }

        [Fact]
        public void BuildSalesInvoiceDetailRecords_WithSFields_ConsolidatesMultiLotSameSkuIntoSingleDWithMultipleS()
        {
            var header = new EnterpriseAuth.Api.Core.Domain.Entities.StagingSalesInvoiceHeader
            {
                InvoiceId = "HICGD08112600026",
                SalesSite = "CGD",
                CustomerCode = "SSM658",
                Lines = new List<EnterpriseAuth.Api.Core.Domain.Entities.StagingSalesInvoiceLine>
                {
                    new()
                    {
                        LineNo = 1, Sku = "8101", Name = "Barilla Macaroni 500g",
                        Quantity = 32, BasePrice = 72.29, DiscountAmount = 0,
                        TaxRule = "TC01", LotNumber = "LOT26092038",
                        Warehouse = "N8", Location = "N8", SalesUnit = "EA", IsFoc = false
                    },
                    new()
                    {
                        LineNo = 2, Sku = "8101", Name = "Barilla Macaroni 500g",
                        Quantity = 17, BasePrice = 72.29, DiscountAmount = 0,
                        TaxRule = "TC01", LotNumber = "LOT26092039",
                        Warehouse = "N8", Location = "N8", SalesUnit = "EA", IsFoc = false
                    },
                    new()
                    {
                        LineNo = 3, Sku = "8101", Name = "Barilla Macaroni 500g FOC",
                        Quantity = 1, BasePrice = 0, DiscountAmount = 0,
                        TaxRule = "VAT0", LotNumber = "LOT26092039",
                        Warehouse = "N8", Location = "N8", SalesUnit = "EA", IsFoc = true, MainItemSku = "8101"
                    }
                }
            };

            var sFields = new List<string> { "/", "PCU", "QTYSTU", "LOT", "LOC", "WRH", "STA" };
            var meta = new Dictionary<string, (string SalesUnit, string TaxLevel)>(StringComparer.OrdinalIgnoreCase);

            var records = SageX3SoapService.BuildSalesInvoiceDetailRecords(
                header,
                fallbackWarehouse: "N8",
                primarySalesRep: "22",
                secondarySalesRep: "22",
                itemMetadata: meta,
                isWarehouseManaged: false,
                validSiteWrhs: null,
                dFields: null,
                sFields: sFields);

            var parts = records.Split('|', StringSplitOptions.RemoveEmptyEntries);
            var dRecords = parts.Where(p => p.StartsWith("D;")).ToList();
            var sRecords = parts.Where(p => p.StartsWith("S;")).ToList();

            Assert.Equal(2, dRecords.Count); // 1 consolidated paid D line (49) + 1 FOC D line (1)
            Assert.Contains(";8101;Barilla Macaroni 500g;EA;49;72.29;", dRecords[0]);
            Assert.EndsWith(";2;", dRecords[0]); // FOCFLG = 2 source
            Assert.Contains(";8101;Barilla Macaroni 500g FOC;EA;1;0;", dRecords[1]);
            Assert.EndsWith(";3;", dRecords[1]); // FOCFLG = 3 free

            Assert.Equal(3, sRecords.Count); // 2 lots for paid + 1 lot for FOC
            Assert.Contains(";32;LOT26092038;N8;N8;A;", sRecords[0]);
            Assert.Contains(";17;LOT26092039;N8;N8;A;", sRecords[1]);
            Assert.Contains(";1;LOT26092039;N8;N8;A;", sRecords[2]);
        }

        [Fact]
        public void BuildSalesInvoiceDetailRecords_WithoutSFields_PreservesPerLotDRecords()
        {
            var header = new EnterpriseAuth.Api.Core.Domain.Entities.StagingSalesInvoiceHeader
            {
                InvoiceId = "HICGD08112600027",
                SalesSite = "CGD",
                CustomerCode = "SSM658",
                Lines = new List<EnterpriseAuth.Api.Core.Domain.Entities.StagingSalesInvoiceLine>
                {
                    new()
                    {
                        LineNo = 1, Sku = "8101", Name = "Barilla Macaroni 500g",
                        Quantity = 32, BasePrice = 72.29, DiscountAmount = 0,
                        TaxRule = "TC01", LotNumber = "LOT26092038",
                        Warehouse = "N8", Location = "N8", SalesUnit = "EA"
                    },
                    new()
                    {
                        LineNo = 2, Sku = "8101", Name = "Barilla Macaroni 500g",
                        Quantity = 17, BasePrice = 72.29, DiscountAmount = 0,
                        TaxRule = "TC01", LotNumber = "LOT26092039",
                        Warehouse = "N8", Location = "N8", SalesUnit = "EA"
                    }
                }
            };

            var records = SageX3SoapService.BuildSalesInvoiceDetailRecords(
                header,
                fallbackWarehouse: "N8",
                primarySalesRep: "22",
                secondarySalesRep: "22",
                itemMetadata: new Dictionary<string, (string, string)>(),
                isWarehouseManaged: false,
                validSiteWrhs: null,
                dFields: null,
                sFields: null);

            var dRecords = records.Split('|', StringSplitOptions.RemoveEmptyEntries)
                .Where(p => p.StartsWith("D;"))
                .ToList();
            Assert.Equal(2, dRecords.Count);
            Assert.Contains(";EA;32;72.29;", dRecords[0]);
            Assert.Contains(";EA;17;72.29;", dRecords[1]);
        }
    }
}
