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
    }
}
