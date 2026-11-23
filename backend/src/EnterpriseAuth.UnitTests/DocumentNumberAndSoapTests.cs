using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using EnterpriseAuth.Api.Controllers;
using EnterpriseAuth.Api.Core.Application.DTOs;
using EnterpriseAuth.Api.Core.Application.Interfaces;
using EnterpriseAuth.Api.Core.Application.Services;
using EnterpriseAuth.Api.Core.Domain.Entities;
using EnterpriseAuth.Api.Core.Domain.Interfaces;
using EnterpriseAuth.Api.Infrastructure.Persistence;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Moq;
using Xunit;

namespace EnterpriseAuth.UnitTests
{
    public class DocumentNumberAndSoapTests
    {
        private sealed class CapturingHttpMessageHandler : HttpMessageHandler
        {
            public string LastRequestBody { get; private set; } = string.Empty;
            private readonly string _responseBody;

            public CapturingHttpMessageHandler(string createdDocId)
            {
                _responseBody = $@"<soapenv:Envelope xmlns:soapenv=""http://schemas.xmlsoap.org/soap/envelope/"">
  <soapenv:Body>
    <runResponse>
      <runReturn>
        <status>1</status>
        <resultXml><![CDATA[<RESULT><GRP ID=""GRP1""><FLD NAME=""O_STATUS"">1</FLD><FLD NAME=""O_MESSA"">Creation of {createdDocId}</FLD></GRP></RESULT>]]></resultXml>
      </runReturn>
    </runResponse>
  </soapenv:Body>
</soapenv:Envelope>";
            }

            protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
            {
                LastRequestBody = request.Content != null
                    ? await request.Content.ReadAsStringAsync(cancellationToken)
                    : string.Empty;

                return new HttpResponseMessage(HttpStatusCode.OK)
                {
                    Content = new StringContent(_responseBody, Encoding.UTF8, "text/xml")
                };
            }
        }

        private static (SageX3SoapService Service, CapturingHttpMessageHandler Handler) CreateSoapService(
            ScanProductionDbContext dbContext,
            string expectedCreatedDocId)
        {
            var handler = new CapturingHttpMessageHandler(expectedCreatedDocId);
            var httpClient = new HttpClient(handler);
            var httpClientFactory = new Mock<IHttpClientFactory>();
            httpClientFactory.Setup(f => f.CreateClient(It.IsAny<string>())).Returns(httpClient);

            var config = new ConfigurationBuilder()
                .AddInMemoryCollection(new Dictionary<string, string?>
                {
                    ["ConnectionStrings:Innodis"] = "Server=localhost;Database=MissingTestDb;User Id=sa;Password=invalid;Connect Timeout=1;Encrypt=False;",
                    ["X3SoapService:Url"] = "http://localhost:9999/soap",
                    ["X3SoapService:PoolAlias"] = "TEST",
                    ["X3SoapService:Username"] = "ADMIN",
                    ["X3SoapService:Password"] = "PASS",
                    ["SyncSettings:X3SchemaName"] = "INLDRYRUN"
                })
                .Build();

            var httpContextAccessor = new HttpContextAccessor();
            var services = new ServiceCollection();
            services.AddScoped(_ => dbContext);
            var sp = services.BuildServiceProvider();

            var service = new SageX3SoapService(
                dbContext,
                config,
                httpClientFactory.Object,
                httpContextAccessor,
                sp.GetRequiredService<IServiceScopeFactory>());

            return (service, handler);
        }

        private static ScanProductionDbContext CreateInMemoryDb()
        {
            var options = new DbContextOptionsBuilder<ScanProductionDbContext>()
                .UseInMemoryDatabase("DocNumSoapTestDb_" + Guid.NewGuid())
                .ConfigureWarnings(w => w.Ignore(InMemoryEventId.TransactionIgnoredWarning))
                .Options;
            return new ScanProductionDbContext(options);
        }

        private static string ExtractIFileFromSoap(string soapBody)
        {
            const string startToken = "<![CDATA[";
            const string endToken = "]]>";
            var s = soapBody.IndexOf(startToken, StringComparison.Ordinal);
            var e = soapBody.IndexOf(endToken, StringComparison.Ordinal);
            Assert.True(s >= 0 && e > s, "CDATA JSON payload not found in SOAP envelope.");
            var json = soapBody.Substring(s + startToken.Length, e - (s + startToken.Length));
            using var doc = JsonDocument.Parse(json);
            return doc.RootElement.GetProperty("GRP1").GetProperty("I_FILE").GetString() ?? string.Empty;
        }

        [Fact]
        public async Task ImportSalesInvoiceAsync_PopulatesGeneratedDocNumberInNumField()
        {
            using var db = CreateInMemoryDb();
            const string docNum = "HIPOD57112600001";
            var (service, handler) = CreateSoapService(db, docNum);

            var invoice = new StagingSalesInvoiceHeader
            {
                InvoiceId = docNum,
                SalesSite = "POD",
                CustomerCode = "C001",
                CreatedAt = "20261117",
                DueDate = "20261117",
                TabletSource = "HM1",
                Lines = new List<StagingSalesInvoiceLine>
                {
                    new StagingSalesInvoiceLine
                    {
                        InvoiceId = docNum,
                        LineNo = 1,
                        Sku = "SKU001",
                        Name = "Test Item",
                        Quantity = 2,
                        BasePrice = 100,
                        SalesUnit = "EA",
                        TaxRule = "VAT15",
                        Warehouse = "POD",
                        Location = "57"
                    }
                }
            };

            var res = await service.ImportSalesInvoiceAsync(invoice);

            Assert.True(res.Success);
            Assert.Equal(docNum, res.DocumentId);

            var iFile = ExtractIFileFromSoap(handler.LastRequestBody);
            var headerParts = iFile.Split('|')[0].Split(';');
            Assert.Equal("V", headerParts[0]);
            Assert.Equal(docNum, headerParts[5]); // Pos 6: NUM
            Assert.Equal(docNum, headerParts[8]); // Pos 9: INVREF
        }

        [Theory]
        [InlineData("HCPOD57112600001", "2")]
        [InlineData("HRPOD57112600001", "3")]
        public async Task ImportCreditNoteAndReturnAsync_PopulatesGeneratedDocNumberInNumField(string docNum, string category)
        {
            using var db = CreateInMemoryDb();
            var (service, handler) = CreateSoapService(db, docNum);

            var crn = new StagingSalesInvoiceHeader
            {
                InvoiceId = docNum,
                InvoiceType = category,
                SalesSite = "POD",
                CustomerCode = "C001",
                CreatedAt = "20261117",
                DueDate = "20261117",
                Reason = "RET",
                SettlementType = "CASH",
                TabletSource = "HM1",
                Lines = new List<StagingSalesInvoiceLine>
                {
                    new StagingSalesInvoiceLine
                    {
                        InvoiceId = docNum,
                        LineNo = 1,
                        Sku = "SKU001",
                        Name = "Test Item",
                        Quantity = 1,
                        BasePrice = 100,
                        SalesUnit = "EA",
                        TaxRule = "VAT15",
                        Warehouse = "POD",
                        Location = "57"
                    }
                }
            };

            var res = await service.ImportCreditNoteAsync(crn);

            Assert.True(res.Success);
            Assert.Equal(docNum, res.DocumentId);

            var iFile = ExtractIFileFromSoap(handler.LastRequestBody);
            var headerParts = iFile.Split('|')[0].Split(';');
            Assert.Equal("V", headerParts[0]);
            Assert.Equal(category, headerParts[4]); // Pos 5: INVTYP
            Assert.Equal(docNum, headerParts[5]);   // Pos 6: NUM
            Assert.Equal(docNum, headerParts[8]);   // Pos 9: INVREF / BPRVCR
        }

        [Fact]
        public async Task ImportMiscReceiptAsync_PopulatesGeneratedReturnDocNumberInVcrNumField()
        {
            using var db = CreateInMemoryDb();
            const string docNum = "HRPOD57112600001";
            var (service, handler) = CreateSoapService(db, docNum);

            var header = new StagingSalesInvoiceHeader
            {
                InvoiceId = docNum,
                InvoiceType = "3",
                SalesSite = "POD",
                CustomerCode = "C001",
                CreatedAt = "20261117",
                TabletSource = "HM1"
            };
            var lines = new List<StagingSalesInvoiceLine>
            {
                new StagingSalesInvoiceLine
                {
                    InvoiceId = docNum,
                    LineNo = 1,
                    Sku = "SKU001",
                    Quantity = 2,
                    BasePrice = 50,
                    SalesUnit = "EA",
                    StockStatus = "A",
                    Location = "57"
                }
            };

            var res = await service.ImportMiscReceiptAsync(header, lines);

            Assert.True(res.Success);
            Assert.Equal(docNum, res.DocumentId);

            var iFile = ExtractIFileFromSoap(handler.LastRequestBody);
            var eParts = iFile.Split('|')[0].Split(';');
            Assert.Equal("E", eParts[0]);
            Assert.Equal("19", eParts[2]);
            Assert.Equal(docNum, eParts[3]); // Pos 4: VCRNUM
        }

        [Fact]
        public async Task GetDocumentSequences_WhenStagingEmptyAfterCrash_RecoversHighWaterMarkFromSageX3()
        {
            using var db = CreateInMemoryDb();
            var repoMock = new Mock<ISalesInvoiceRepository>();
            repoMock.Setup(r => r.GetFinancialSiteForSalesSiteAsync("POD")).ReturnsAsync("POD");
            repoMock.Setup(r => r.GetExistingHipoDocumentIdsFromX3Async("POD"))
                .ReturnsAsync(new[]
                {
                    "HIPOD57112600042",
                    "HCPOD57112600009",
                    "HRPOD57112600005"
                });

            var soapMock = new Mock<ISageX3SoapService>();
            var loggerMock = new Mock<ILogger<SalesInvoiceController>>();
            var siteResolver = new SiteContextResolver(repoMock.Object, Mock.Of<ILogger<SiteContextResolver>>());
            var controller = new SalesInvoiceController(repoMock.Object, db, soapMock.Object, loggerMock.Object, siteResolver);
            controller.ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = new ClaimsPrincipal(new ClaimsIdentity(new[] { new Claim("SiteCode", "POD") }, "TestAuth"))
                }
            };

            var actionResult = await controller.GetDocumentSequences("POD");
            var ok = Assert.IsType<OkObjectResult>(actionResult);
            var json = JsonSerializer.Serialize(ok.Value);
            using var doc = JsonDocument.Parse(json);
            var items = doc.RootElement.EnumerateArray().ToList();

            Assert.Equal(3, items.Count);
            Assert.Contains(items, i => i.GetProperty("prefix").GetString() == "HIPOD571126" && i.GetProperty("lastSequence").GetInt32() == 42 && i.GetProperty("lorryCode").GetString() == "57");
            Assert.Contains(items, i => i.GetProperty("prefix").GetString() == "HCPOD571126" && i.GetProperty("lastSequence").GetInt32() == 9);
            Assert.Contains(items, i => i.GetProperty("prefix").GetString() == "HRPOD571126" && i.GetProperty("lastSequence").GetInt32() == 5);
        }

        [Fact]
        public async Task DevicesController_HeartbeatRestoresIdentityAfterReinstall_AndEnforcesUniqueLorryOptionA()
        {
            using var db = CreateInMemoryDb();
            var dev1Id = Guid.NewGuid().ToString();
            var dev2Id = Guid.NewGuid().ToString();
            db.DeviceLocations.AddRange(
                new DeviceLocation
                {
                    DeviceId = dev1Id,
                    DeviceName = "HM1",
                    HardwareIdentifier = "ANDROID_HW_001",
                    SiteCode = "POD",
                    WarehouseCode = "57",
                    LocationCode = "57",
                    IsActive = true
                },
                new DeviceLocation
                {
                    DeviceId = dev2Id,
                    DeviceName = "HM2",
                    HardwareIdentifier = "ANDROID_HW_002",
                    SiteCode = "POD",
                    WarehouseCode = "58",
                    LocationCode = "58",
                    IsActive = true
                });
            await db.SaveChangesAsync();

            var controller = new DevicesController(db, Mock.Of<ISyncRepository>());
            controller.ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = new ClaimsPrincipal(new ClaimsIdentity(new[]
                    {
                        new Claim("SiteCode", "POD"),
                        new Claim("username", "driver2")
                    }, "TestAuth"))
                }
            };

            // 1. Reinstall simulation: client sends empty DeviceId & DeviceName, only HardwareIdentifier
            var hbResult = await controller.Heartbeat(new DeviceHeartbeatRequestDto
            {
                DeviceId = string.Empty,
                DeviceName = string.Empty,
                HardwareIdentifier = "ANDROID_HW_001",
                SiteCode = "POD"
            });
            var hbOk = Assert.IsType<OkObjectResult>(hbResult.Result);
            var hbDto = Assert.IsType<DeviceLocationDto>(hbOk.Value);
            Assert.Equal(dev1Id, hbDto.DeviceId);
            Assert.Equal("HM1", hbDto.DeviceName);
            Assert.Equal("57", hbDto.LocationCode);

            // 2. Option A safeguard: HM2 attempting to claim lorry 57 already held by HM1 must return 409 Conflict
            var conflictResult = await controller.UpdateLocation(dev2Id, new DeviceLocationUpdateRequestDto
            {
                LocationCode = "57",
                WarehouseCode = "57"
            });
            Assert.IsType<ConflictObjectResult>(conflictResult.Result);
        }

        [Fact]
        public async Task DevicesController_GetSiteLorries_UsesLightweightSiteQuery_KeepsWeb_ExcludesDamageBays()
        {
            using var db = CreateInMemoryDb();
            var syncRepoMock = new Mock<ISyncRepository>();
            syncRepoMock
                .Setup(r => r.GetSiteLocationsAsync("SCG"))
                .ReturnsAsync(new[]
                {
                    new LocationLookupDto { Site = "SCG", Location = "N3", Warehouse = "N3", WarehouseName = "9418 DC 12 former 30", LocationType = "N3", LocationTypeName = "5308 JL 16 (former 30)" },
                    new LocationLookupDto { Site = "SCG", Location = "N6", Warehouse = "N6", WarehouseName = "5308 JL 16 former 62", LocationType = "N6", LocationTypeName = "9418 DC 12 (former 62)" },
                    new LocationLookupDto { Site = "SCG", Location = "N8", Warehouse = "N8", WarehouseName = "398 JN 15 former 81", LocationType = "N8", LocationTypeName = "398 JN 15 (former 81)" },
                    new LocationLookupDto { Site = "SCG", Location = "SCGDAM", Warehouse = "SCG", WarehouseName = "Consumer Shop To Shop", LocationType = "CGDAM", LocationTypeName = "SCG Damage" },
                    new LocationLookupDto { Site = "SCG", Location = "WEB", Warehouse = "WEB", WarehouseName = "WEB", LocationType = "WEB", LocationTypeName = "SCG-WEB" },
                });

            var controller = new DevicesController(db, syncRepoMock.Object);
            controller.ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = new ClaimsPrincipal(new ClaimsIdentity(new[]
                    {
                        new Claim("SiteCode", "SCG"),
                        new Claim("username", "admin")
                    }, "TestAuth"))
                }
            };

            var actionResult = await controller.GetSiteLorries("SCG");
            var ok = Assert.IsType<OkObjectResult>(actionResult.Result);
            var lorries = Assert.IsAssignableFrom<IEnumerable<LorryLookupDto>>(ok.Value).ToList();

            Assert.Equal(4, lorries.Count);
            Assert.Contains(lorries, l => l.Location == "N3" && l.PlateNumber == "5308 JL 16 (former 30)" && l.Site == "SCG");
            Assert.Contains(lorries, l => l.Location == "N6" && l.PlateNumber == "9418 DC 12 (former 62)" && l.Site == "SCG");
            Assert.Contains(lorries, l => l.Location == "N8" && l.PlateNumber == "398 JN 15 (former 81)" && l.Site == "SCG");
            Assert.Contains(lorries, l => l.Location == "WEB" && l.PlateNumber == "SCG-WEB" && l.Site == "SCG");
            Assert.DoesNotContain(lorries, l => l.Location == "SCGDAM");

            syncRepoMock.Verify(r => r.GetSiteLocationsAsync("SCG"), Times.Once);
            syncRepoMock.Verify(r => r.GetRefreshPackageAsync(It.IsAny<string>(), It.IsAny<string?>(), It.IsAny<string?>()), Times.Never);
        }

        [Fact]
        public async Task AllocateAndImportSalesInvoiceAsync_WithMultiLotLines_SplitsLotsWithProRatedDiscountsAndEmitsSeparateDRecords()
        {
            using var db = CreateInMemoryDb();
            const string docNum = "HISCGN3112600009";
            var (service, handler) = CreateSoapService(db, docNum);

            var singleCombinedInvoice = new StagingSalesInvoiceHeader
            {
                InvoiceId = docNum,
                SalesSite = "SCG",
                CustomerCode = "C001",
                CreatedAt = "20261118",
                DueDate = "20261118",
                TabletSource = "HM4",
                Lines = new List<StagingSalesInvoiceLine>
                {
                    new()
                    {
                        InvoiceId = docNum,
                        LineNo = 1,
                        Sku = "SKU-MULTI",
                        Name = "Frozen Chicken",
                        Quantity = 18,
                        BasePrice = 100,
                        DiscountAmount = 90,
                        DiscountAmountFlat = 90,
                        Discount3 = 90,
                        VatAmount = 256.50,
                        Total = 1966.50,
                        SalesUnit = "EA",
                        TaxRule = "VAT15",
                        Warehouse = "N3",
                        Location = "N3",
                        LotNumber = "LOT-1"
                    },
                    new()
                    {
                        InvoiceId = docNum,
                        LineNo = 2,
                        Sku = "SKU-MULTI",
                        Name = "Frozen Chicken",
                        Quantity = 2,
                        BasePrice = 0,
                        IsFoc = true,
                        MainItemSku = "SKU-MULTI",
                        SalesUnit = "EA",
                        TaxRule = "VAT0",
                        Warehouse = "N3",
                        Location = "N3",
                        LotNumber = ""
                    }
                }
            };

            var stockMap = new Dictionary<string, List<SageX3SoapService.StockSlot>>(StringComparer.OrdinalIgnoreCase)
            {
                ["SKU-MULTI"] = new List<SageX3SoapService.StockSlot>
                {
                    new() { Warehouse = "N3", Location = "N3", LotNumber = "LOT-1", Qty = 10m },
                    new() { Warehouse = "N3", Location = "N3", LotNumber = "LOT-2", Qty = 15m }
                }
            };

            var modified = SageX3SoapService.AllocateInvoiceLinesByLot(singleCombinedInvoice, stockMap, "N3", "N3");
            Assert.True(modified);
            Assert.Equal(3, singleCombinedInvoice.Lines.Count);

            var linesList = singleCombinedInvoice.Lines.ToList();
            var line1 = linesList[0];
            var line2 = linesList[1];
            var focLine = linesList[2];

            Assert.Equal("LOT-1", line1.LotNumber);
            Assert.Equal(10, line1.Quantity);
            Assert.Equal(50.0, line1.DiscountAmount);

            Assert.Equal("LOT-2", line2.LotNumber);
            Assert.Equal(8, line2.Quantity);
            Assert.Equal(40.0, line2.DiscountAmount);

            Assert.Equal("LOT-2", focLine.LotNumber);
            Assert.Equal(2, focLine.Quantity);
            Assert.True(focLine.IsFoc);

            var soapRes = await service.ImportSalesInvoiceAsync(singleCombinedInvoice);
            Assert.True(soapRes.Success);

            var iFile = ExtractIFileFromSoap(handler.LastRequestBody);
            var dRecords = iFile.Split('|', StringSplitOptions.RemoveEmptyEntries)
                .Where(r => r.StartsWith("D;", StringComparison.Ordinal))
                .Select(r => r.Split(';'))
                .ToList();

            Assert.Equal(3, dRecords.Count);
            Assert.Equal("10", dRecords[0][5]);
            Assert.Equal("50", dRecords[0][9]);
            Assert.Equal("2", dRecords[0][17]);  // Source paid line 1 -> FOCFLG = 2
            Assert.Equal("8", dRecords[1][5]);
            Assert.Equal("40", dRecords[1][9]);
            Assert.Equal("2", dRecords[1][17]);  // Source paid line 2 -> FOCFLG = 2
            Assert.Equal("2", dRecords[2][5]);
            Assert.Equal("3", dRecords[2][17]);  // FOC line -> FOCFLG = 3
        }
    }
}
