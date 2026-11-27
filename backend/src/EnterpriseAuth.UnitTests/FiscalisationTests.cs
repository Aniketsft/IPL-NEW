using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Http;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using EnterpriseAuth.Api.Controllers;
using EnterpriseAuth.Api.Core.Application.Common;
using EnterpriseAuth.Api.Core.Application.DTOs;
using EnterpriseAuth.Api.Core.Application.Interfaces;
using EnterpriseAuth.Api.Core.Application.Services;
using EnterpriseAuth.Api.Core.Domain.Entities;
using EnterpriseAuth.Api.Core.Domain.Interfaces;
using EnterpriseAuth.Api.Infrastructure.Persistence;
using EnterpriseAuth.Api.Infrastructure.Security;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Moq;
using Xunit;

namespace EnterpriseAuth.UnitTests
{
    public class FiscalisationTests
    {
        private const string SampleFiscalisedJson = @"{
  ""hepId"": ""064f4dbd-c373-4bb2-8628-8172bc97034e"",
  ""status"": ""fiscalised"",
  ""summary"": {
    ""createdAt"": ""2026-10-24T12:36:52.448518Z"",
    ""updatedAt"": ""2026-10-24T12:36:52.448518Z"",
    ""invoiceTotal"": 18495,
    ""lineItemCount"": 4,
    ""totalVatAmount"": 1695,
    ""totalAmountPaid"": 18495,
    ""discountTotalAmount"": 0,
    ""totalAmountWithoutVatCur"": 16800,
    ""totalAmountWithoutVatMur"": 16800
  },
  ""mraResponse"": {
    ""status"": ""SUCCESS"",
    ""requestId"": ""20261024123652"",
    ""responseId"": ""LT17928453684684981852124"",
    ""environment"": ""TEST"",
    ""errorMessages"": null,
    ""responseDateTime"": ""20261024 16:36:08"",
    ""fiscalisedInvoices"": [
      {
        ""irn"": ""STD28UD-7ee60598-ed7c-3f1f-bacf-10352271cac3"",
        ""qrCode"": ""iVBORw0KGgoAAAANSUhEUgAAAV4AAAFeAQAAAADlUEq3"",
        ""status"": ""SUCCESS"",
        ""errorMessages"": null,
        ""invoiceIdentifier"": ""UDIS-TC1-0001-9302""
      }
    ]
  },
  ""statusMessage"": ""Invoice successfully cleared and fiscalised by MRA.""
}";

        private const string SampleMraErrorJson = @"{
  ""hepId"": ""e3088ba0-1c88-48c3-8b79-3429f727af4b"",
  ""status"": ""mraError"",
  ""mraResponse"": {
    ""status"": ""ERROR"",
    ""requestId"": ""20261025081618"",
    ""responseId"": ""LT17929161340077044258822"",
    ""environment"": ""TEST"",
    ""errorMessages"": null,
    ""responseDateTime"": ""20261025 12:15:34"",
    ""fiscalisedInvoices"": [
      {
        ""irn"": null,
        ""qrCode"": null,
        ""status"": ""ERROR"",
        ""errorMessages"": [
          { ""code"": ""ERR0600"", ""description"": ""Sales transactions should not be blank"" },
          { ""code"": ""ERR0600"", ""description"": ""Item Number 3: Tax Code of items should not be blank"" }
        ],
        ""invoiceIdentifier"": ""UDIS-TC1-0001-4113""
      }
    ]
  },
  ""statusMessage"": ""MRA error, rejected by MRA""
}";

        private const string SampleDuplicateJson = @"{
  ""status"": ""duplicate"",
  ""statusMessage"": ""Invoice 'UDIS-TC1-0001-6791' has already been fiscalised. Returning existing fiscal credentials."",
  ""hepId"": ""c93d8f4d-bc7a-4f71-8ed5-4f12fb80230e"",
  ""mraResponse"": {
    ""responseId"": ""LT17929162263102082069888"",
    ""responseDateTime"": ""20261025 12:17:06"",
    ""requestId"": ""20261025081750"",
    ""status"": ""SUCCESS"",
    ""environment"": ""TEST"",
    ""fiscalisedInvoices"": [
      {
        ""invoiceIdentifier"": ""UDIS-TC1-0001-6791"",
        ""irn"": ""STD28UD-14f0aa43-0215-3213-9c10-49008f48017a"",
        ""qrCode"": ""iVBORw0KGgoAAAANSUhEUgAAAV4AAAFeAQAAAADlUEq3DUPLICATE"",
        ""status"": ""SUCCESS"",
        ""errorMessages"": null
      }
    ]
  }
}";

        private const string SampleHepErrorJson = @"{
  ""status"": ""hepError"",
  ""statusMessage"": ""Authentication failed: Missing or invalid API key or Bearer token."",
  ""hepId"": null,
  ""summary"": null,
  ""mraResponse"": null
}";

        private sealed class StubHttpHandler : HttpMessageHandler
        {
            private readonly Func<HttpRequestMessage, HttpResponseMessage> _responder;
            public int CallCount { get; private set; }
            public string? LastUrl { get; private set; }
            public string? LastApiKeyHeader { get; private set; }
            public string? LastBody { get; private set; }

            public StubHttpHandler(Func<HttpRequestMessage, HttpResponseMessage> responder)
            {
                _responder = responder;
            }

            protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
            {
                CallCount++;
                LastUrl = request.RequestUri?.ToString();
                LastApiKeyHeader = request.Headers.TryGetValues("X-API-Key", out var vals) ? string.Join(",", vals) : null;
                LastBody = request.Content != null ? await request.Content.ReadAsStringAsync(cancellationToken) : null;
                return _responder(request);
            }
        }

        private static ScanProductionDbContext CreateDb()
        {
            var options = new DbContextOptionsBuilder<ScanProductionDbContext>()
                .UseInMemoryDatabase("FiscalTestDb_" + Guid.NewGuid())
                .ConfigureWarnings(w => w.Ignore(InMemoryEventId.TransactionIgnoredWarning))
                .Options;
            return new ScanProductionDbContext(options);
        }

        [Fact]
        public void ParseHepResponse_HandlesAllFourSamplePayloads()
        {
            var ok = FiscalInvoiceMapper.ParseHepResponse(SampleFiscalisedJson, 200);
            Assert.True(ok.IsSuccess);
            Assert.Equal("fiscalised", ok.HepStatus);
            Assert.Equal("STD28UD-7ee60598-ed7c-3f1f-bacf-10352271cac3", ok.Irn);
            Assert.StartsWith("iVBOR", ok.QrBase64);

            var dup = FiscalInvoiceMapper.ParseHepResponse(SampleDuplicateJson, 200);
            Assert.True(dup.IsSuccess);
            Assert.Equal("duplicate", dup.HepStatus);
            Assert.Equal("STD28UD-14f0aa43-0215-3213-9c10-49008f48017a", dup.Irn);

            var mraErr = FiscalInvoiceMapper.ParseHepResponse(SampleMraErrorJson, 400);
            Assert.False(mraErr.IsSuccess);
            Assert.Equal("mraError", mraErr.HepStatus);
            Assert.Equal(2, mraErr.Errors.Count);
            Assert.Contains(mraErr.Errors, e => e.Code == "ERR0600" && e.Description.Contains("Tax Code"));

            var hepErr = FiscalInvoiceMapper.ParseHepResponse(SampleHepErrorJson, 401);
            Assert.False(hepErr.IsSuccess);
            Assert.Equal("hepError", hepErr.HepStatus);
            Assert.Contains(hepErr.Errors, e => e.Description.Contains("Authentication failed"));
        }

        [Theory]
        [InlineData("MICAS", "INVOICE", "STD")]
        [InlineData("MICRE", "INVOICE", "STD")]
        [InlineData("MSINV", "INVOICE", "STD")]
        [InlineData("MRCAS", "CREDIT_NOTE", "CRN")]
        [InlineData("MRCRE", "RETURN", "CRN")]
        [InlineData("MSCRN", "CREDIT_NOTE", "CRN")]
        public void Mapper_MapsInvoiceTypesCorrectly(string rawType, string category, string expected)
        {
            Assert.Equal(expected, FiscalInvoiceMapper.ResolveInvoiceTypeDesc(rawType, category));
        }

        [Fact]
        public void Mapper_MapsSalesTransactionsAndMixedPayments()
        {
            Assert.Equal("CASH", FiscalInvoiceMapper.ResolveSalesTransactions(new[] { new FiscalisePaymentDto { Method = "CASH", Amount = 100 } }));
            Assert.Equal("CHEQUE", FiscalInvoiceMapper.ResolveSalesTransactions(new[] { new FiscalisePaymentDto { Method = "CHEQUE", Amount = 100 } }));
            Assert.Equal("OTHER", FiscalInvoiceMapper.ResolveSalesTransactions(new[] { new FiscalisePaymentDto { Method = "BLINK", Amount = 100 } }));
            Assert.Equal("OTHER", FiscalInvoiceMapper.ResolveSalesTransactions(new[] { new FiscalisePaymentDto { Method = "MYT MONEY", Amount = 100 } }));
            // Any credit portion -> CREDIT
            Assert.Equal("CREDIT", FiscalInvoiceMapper.ResolveSalesTransactions(new[]
            {
                new FiscalisePaymentDto { Method = "CASH", Amount = 50 },
                new FiscalisePaymentDto { Method = "CREDIT", Amount = 50 }
            }));
            // Multiple non-credit -> CASH
            Assert.Equal("CASH", FiscalInvoiceMapper.ResolveSalesTransactions(new[]
            {
                new FiscalisePaymentDto { Method = "CASH", Amount = 50 },
                new FiscalisePaymentDto { Method = "CHEQUE", Amount = 50 }
            }));
        }

        [Fact]
        public async Task FiscaliseAsync_Success_InsertsOnlyHepFiscalInvoices_AndReusesOnRetry()
        {
            using var db = CreateDb();
            var protector = new HepSecretProtector(new EphemeralDataProtectionProvider());
            var devId = Guid.NewGuid().ToString();
            db.DeviceLocations.Add(new DeviceLocation
            {
                DeviceId = devId,
                DeviceName = "HM1",
                SiteCode = "POD",
                LocationCode = "57",
                HepProfileId = "PROF-POD-01",
                HepApiKey = protector.Protect("secret-api-key-1234"),
                EbsCounterNo = "7",
                IsActive = true
            });
            await db.SaveChangesAsync();

            var repoMock = new Mock<ISalesInvoiceRepository>();
            repoMock.Setup(r => r.GetCustomerByCodeAsync("C001")).ReturnsAsync(new SalesInvoiceCustomerDto
            {
                Code = "C001",
                Name = "Test Supermarket Ltd",
                TaxRule = "VAT",
                TransactionType = "1", // -> B2B
                Tan = "20001234",
                Brn = "C07001234",
                Address = "Port Louis"
            });

            var handler = new StubHttpHandler(_ => new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(SampleFiscalisedJson, Encoding.UTF8, "application/json")
            });
            var factoryMock = new Mock<IHttpClientFactory>();
            factoryMock.Setup(f => f.CreateClient("HepClient")).Returns(new HttpClient(handler));

            var config = new ConfigurationBuilder().Build();
            var service = new FiscalisationService(
                db,
                repoMock.Object,
                protector,
                factoryMock.Object,
                Options.Create(new FiscalSettings { BaseUrl = "http://192.168.120.10:5162" }),
                Options.Create(new SyncSettings()),
                config,
                Mock.Of<ILogger<FiscalisationService>>());

            var req = new FiscaliseDocumentRequestDto
            {
                DocumentNo = "HIPOD57112600001",
                DocumentCategory = "INVOICE",
                CustomerCode = "C001",
                Lines =
                {
                    new FiscaliseLineDto
                    {
                        LineNo = 1000,
                        Sku = "SKU1",
                        Name = "Chicken 1KG",
                        Quantity = 2,
                        UnitPrice = 100,
                        DiscountAmount = 10,
                        VatAmount = 28.5m,
                        Total = 218.5m,
                        TaxCode = "VAT15"
                    }
                },
                Payments = { new FiscalisePaymentDto { Method = "CASH", Amount = 218.5m } }
            };

            var (status, res) = await service.FiscaliseAsync(req, devId, "cashier1", "POD");
            Assert.Equal(200, status);
            Assert.True(res.Success);
            Assert.True(res.IsFiscalised);
            Assert.Equal("STD28UD-7ee60598-ed7c-3f1f-bacf-10352271cac3", res.Irn);
            Assert.Equal("http://192.168.120.10:5162/api/v1/connectors/PROF-POD-01/ingest", handler.LastUrl);
            Assert.Equal("secret-api-key-1234", handler.LastApiKeyHeader);
            Assert.Equal(1, handler.CallCount);

            // Verify HepFiscalInvoices row inserted & failure table empty
            Assert.Equal(1, await db.HepFiscalInvoices.CountAsync());
            Assert.Equal(0, await db.HepFiscalFailureLogs.CountAsync());

            var saved = await db.HepFiscalInvoices.FirstAsync();
            Assert.True(saved.IsFiscalised);
            Assert.Equal("B2B", saved.TransactionType);
            Assert.Equal("CASH", saved.SalesTransactions);
            Assert.Equal("7", saved.EbsCounterNo);
            Assert.False(saved.X3Synced);

            // Verify posted JSON structure
            using var doc = JsonDocument.Parse(handler.LastBody!);
            var root = doc.RootElement[0];
            Assert.Equal("1", root.GetProperty("invoiceCounter").GetString());
            Assert.Equal("STD", root.GetProperty("invoiceTypeDesc").GetString());
            Assert.Equal("B2B", root.GetProperty("transactionType").GetString());
            Assert.Equal("7", root.GetProperty("seller").GetProperty("ebsCounterNo").GetString());

            // Retry must be idempotent without calling HEP again
            var (status2, res2) = await service.FiscaliseAsync(req, devId, "cashier1", "POD");
            Assert.Equal(200, status2);
            Assert.Equal("duplicate", res2.HepStatus);
            Assert.Equal(1, handler.CallCount);
        }

        [Fact]
        public async Task FiscaliseAsync_MraError_DoesNotInsertHepFiscalInvoices_LogsFailureOnly()
        {
            using var db = CreateDb();
            var protector = new HepSecretProtector(new EphemeralDataProtectionProvider());
            var devId = Guid.NewGuid().ToString();
            db.DeviceLocations.Add(new DeviceLocation
            {
                DeviceId = devId,
                DeviceName = "HM1",
                SiteCode = "POD",
                LocationCode = "57",
                HepProfileId = "PROF-POD-01",
                HepApiKey = protector.Protect("secret-key"),
                IsActive = true
            });
            await db.SaveChangesAsync();

            var repoMock = new Mock<ISalesInvoiceRepository>();
            repoMock.Setup(r => r.GetCustomerByCodeAsync("C001")).ReturnsAsync(new SalesInvoiceCustomerDto
            {
                Code = "C001",
                Name = "Walk-in",
                TaxRule = "NVT",
                TransactionType = "B2C"
            });

            var handler = new StubHttpHandler(_ => new HttpResponseMessage(HttpStatusCode.BadRequest)
            {
                Content = new StringContent(SampleMraErrorJson, Encoding.UTF8, "application/json")
            });
            var factoryMock = new Mock<IHttpClientFactory>();
            factoryMock.Setup(f => f.CreateClient("HepClient")).Returns(new HttpClient(handler));

            var service = new FiscalisationService(
                db, repoMock.Object, protector, factoryMock.Object,
                Options.Create(new FiscalSettings { BaseUrl = "http://192.168.120.10:5162" }),
                Options.Create(new SyncSettings()),
                new ConfigurationBuilder().Build(),
                Mock.Of<ILogger<FiscalisationService>>());

            var req = new FiscaliseDocumentRequestDto
            {
                DocumentNo = "HIPOD57112600099",
                DocumentCategory = "INVOICE",
                CustomerCode = "C001",
                Lines = { new FiscaliseLineDto { LineNo = 1, Sku = "SKU1", Quantity = 1, UnitPrice = 100, VatAmount = 0, Total = 100, TaxCode = "ZERO" } },
                Payments = { new FiscalisePaymentDto { Method = "CASH", Amount = 100 } }
            };

            var (status, res) = await service.FiscaliseAsync(req, devId, "cashier1", "POD");
            Assert.Equal(422, status);
            Assert.False(res.Success);
            Assert.Equal("mraError", res.HepStatus);
            Assert.Equal(2, res.Errors.Count);

            Assert.Equal(0, await db.HepFiscalInvoices.CountAsync());
            Assert.Equal(1, await db.HepFiscalFailureLogs.CountAsync());
        }

        [Fact]
        public async Task SalesInvoiceController_X3Gate_BlocksUnfiscalisedInvoiceAndCreditNote()
        {
            using var db = CreateDb();
            var repoMock = new Mock<ISalesInvoiceRepository>();
            var soapMock = new Mock<ISageX3SoapService>();
            var siteResolver = new SiteContextResolver(repoMock.Object, Mock.Of<ILogger<SiteContextResolver>>());
            var controller = new SalesInvoiceController(
                repoMock.Object, db, soapMock.Object,
                Mock.Of<ILogger<SalesInvoiceController>>(),
                siteResolver);

            controller.ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = new ClaimsPrincipal(new ClaimsIdentity(new[] { new Claim("SiteCode", "POD") }, "TestAuth"))
                }
            };

            var invPayload = new SalesInvoiceSyncDto
            {
                InvoiceId = "HIPOD57112600123",
                SalesSite = "POD",
                CustomerCode = "C001",
                Lines = { new SalesInvoiceLineDto { LineNo = 1, Sku = "SKU1", Quantity = 1, BasePrice = 100, Total = 100 } }
            };

            var invResult = await controller.SyncInvoice(invPayload);
            var invConflict = Assert.IsType<ConflictObjectResult>(invResult);
            Assert.Equal(409, invConflict.StatusCode);
            soapMock.Verify(s => s.ImportSalesInvoiceAsync(It.IsAny<StagingSalesInvoiceHeader>()), Times.Never);

            var crnPayload = new CreditNoteSyncDto
            {
                CreditNoteId = "HCPOD57112600123",
                SalesSite = "POD",
                CustomerCode = "C001",
                GrandTotal = 100,
                Lines = { new CreditNoteLineSyncDto { LineNo = 1, Sku = "SKU1", Quantity = 1, BasePrice = 100 } }
            };

            var crnResult = await controller.SyncCreditNote(crnPayload);
            var crnConflict = Assert.IsType<ConflictObjectResult>(crnResult);
            Assert.Equal(409, crnConflict.StatusCode);
            soapMock.Verify(s => s.ImportCreditNoteAsync(It.IsAny<StagingSalesInvoiceHeader>()), Times.Never);
        }

        [Fact]
        public async Task DevicesController_EncryptsAndMasksHepApiKey_PreservesMaskedOnUpdate()
        {
            using var db = CreateDb();
            var protector = new HepSecretProtector(new EphemeralDataProtectionProvider());
            var controller = new DevicesController(db, Mock.Of<ISyncRepository>(), protector);
            controller.ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = new ClaimsPrincipal(new ClaimsIdentity(new[]
                    {
                        new Claim("SiteCode", "POD"),
                        new Claim("username", "admin"),
                        new Claim(ClaimTypes.Role, "Admin")
                    }, "TestAuth"))
                }
            };

            var provRes = await controller.Provision(new DeviceProvisionRequestDto
            {
                DeviceName = "HM99",
                SiteCode = "POD",
                LocationCode = "57",
                HepProfileId = "PROF-99",
                HepApiKey = "my-super-secret-9999",
                EbsCounterNo = "3"
            });
            var created = Assert.IsType<CreatedAtActionResult>(provRes.Result);
            var dto = Assert.IsType<DeviceLocationDto>(created.Value);

            Assert.Contains("9999", dto.HepApiKey);
            Assert.DoesNotContain("my-super-secret", dto.HepApiKey);
            Assert.Equal("3", dto.EbsCounterNo);

            var stored = await db.DeviceLocations.FirstAsync(d => d.DeviceId == dto.DeviceId);
            Assert.StartsWith("dp:", stored.HepApiKey);
            Assert.Equal("my-super-secret-9999", protector.UnprotectOrPlaintext(stored.HepApiKey));

            // Updating with masked placeholder must preserve original secret
            var updRes = await controller.UpdateAdminConfig(dto.DeviceId, new DeviceAdminConfigRequestDto
            {
                DeviceName = "HM99",
                HepProfileId = "PROF-99",
                HepApiKey = dto.HepApiKey,
                EbsCounterNo = "4"
            });
            var updOk = Assert.IsType<OkObjectResult>(updRes.Result);
            var updDto = Assert.IsType<DeviceLocationDto>(updOk.Value);
            Assert.Equal("4", updDto.EbsCounterNo);

            var storedAfter = await db.DeviceLocations.AsNoTracking().FirstAsync(d => d.DeviceId == dto.DeviceId);
            Assert.Equal("my-super-secret-9999", protector.UnprotectOrPlaintext(storedAfter.HepApiKey));
        }
    }
}
