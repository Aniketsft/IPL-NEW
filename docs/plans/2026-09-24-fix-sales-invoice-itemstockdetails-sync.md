# Fix Sales Invoice Item Stock Details Sync Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Resolve the HTTP 400 Bad Request error (`{errors: {sitecode: ["The sitecode field is required."]}}`) during Sales Invoice item stock details synchronization by ensuring both the ASP.NET Core API controller and Flutter client correctly handle optional and explicit site code query parameters and JWT claims.

**Architecture:** 
1. Make `sitecode` query parameter optional (`string? sitecode = null`) on `SalesInvoiceController.GetItemStockDetails` and `GetProducts` with robust fallback to the authenticated user's `SiteCode` claim.
2. Update Flutter `SalesInvoiceProductRepository.syncSalesInvoiceItemStockDetails` to accept `[String? siteCode]` and pass it as query parameter `?sitecode=...`.
3. Propagate `siteCode` from `SalesInvoiceSyncRepository.synchronizeSalesInvoiceData` to `syncSalesInvoiceItemStockDetails`.
4. Rebuild the backend API and verify end-to-end sync behavior.

**Tech Stack:** ASP.NET Core 8 (.NET 8 C#), Flutter / Dart, Dio, SQLite (sqflite), xUnit, flutter_test / mocktail.

---

### Task 1: Backend Controller Unit Tests for SiteCode Resolution

**Files:**
- Create: `backend/src/EnterpriseAuth.UnitTests/SalesInvoiceControllerTests.cs`
- Reference: `backend/src/EnterpriseAuth.Api/Controllers/SalesInvoiceController.cs`

**Step 1: Write the failing test**

Create `backend/src/EnterpriseAuth.UnitTests/SalesInvoiceControllerTests.cs` with tests checking `GetItemStockDetails`:
1. When query parameter is missing and user has `SiteCode: "IPL"`, it resolves site code as "IPL" and returns 200 OK.
2. When query parameter is provided as "SCG" and user has `SiteCode: "ALL"` or null, it resolves site code as "SCG" and returns 200 OK.
3. When neither query parameter nor user claim is present, it returns 400 Bad Request.

```csharp
using System.Collections.Generic;
using System.Security.Claims;
using System.Threading.Tasks;
using EnterpriseAuth.Api.Controllers;
using EnterpriseAuth.Api.Core.Application.DTOs;
using EnterpriseAuth.Api.Core.Application.Interfaces;
using EnterpriseAuth.Api.Infrastructure.Persistence;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Moq;
using Xunit;

namespace EnterpriseAuth.UnitTests
{
    public class SalesInvoiceControllerTests
    {
        private readonly Mock<ISalesInvoiceRepository> _repoMock;
        private readonly Mock<ISageX3SoapService> _soapMock;
        private readonly ScanProductionDbContext _dbContext;

        public SalesInvoiceControllerTests()
        {
            _repoMock = new Mock<ISalesInvoiceRepository>();
            _soapMock = new Mock<ISageX3SoapService>();

            var options = new DbContextOptionsBuilder<ScanProductionDbContext>()
                .UseInMemoryDatabase(databaseName: "TestSalesInvoiceDb_" + System.Guid.NewGuid())
                .Options;
            _dbContext = new ScanProductionDbContext(options);
        }

        private SalesInvoiceController CreateControllerWithUser(string? siteClaim = null)
        {
            var controller = new SalesInvoiceController(_repoMock.Object, _dbContext, _soapMock.Object);

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
        public async Task GetItemStockDetails_WithNoParamAndNoClaim_ReturnsBadRequest()
        {
            // Arrange
            var controller = CreateControllerWithUser(null);

            // Act
            var result = await controller.GetItemStockDetails(null);

            // Assert
            Assert.IsType<BadRequestObjectResult>(result);
        }
    }
}
```

**Step 2: Run test to verify failure**

Run: `dotnet test backend/src/EnterpriseAuth.UnitTests/EnterpriseAuth.UnitTests.csproj --filter "FullyQualifiedName~SalesInvoiceControllerTests"`
Expected: FAIL or compilation error if Moq / packages or method mismatch.

**Step 3: Refactor minimal implementation in SalesInvoiceController.cs**

Modify `backend/src/EnterpriseAuth.Api/Controllers/SalesInvoiceController.cs` around lines 273-322:

```csharp
        [HttpGet("Products")]
        public async Task<IActionResult> GetProducts([FromQuery] string? sitecode = null)
        {
            var userSiteCode = User.FindFirst("SiteCode")?.Value;

            if (string.IsNullOrWhiteSpace(sitecode) && !string.IsNullOrWhiteSpace(userSiteCode))
            {
                sitecode = userSiteCode;
            }
            else if (!string.IsNullOrWhiteSpace(userSiteCode) && !string.Equals(userSiteCode, "ALL", StringComparison.OrdinalIgnoreCase))
            {
                sitecode = userSiteCode;
            }

            if (string.IsNullOrWhiteSpace(sitecode))
            {
                return BadRequest("A specific sitecode is required to fetch products.");
            }

            try
            {
                var products = await _repository.GetProductsAsync(sitecode);
                return Ok(products);
            }
            catch (System.Exception ex)
            {
                return StatusCode(500, ex.ToString());
            }
        }

        [HttpGet("itemstockdetails")]
        public async Task<IActionResult> GetItemStockDetails([FromQuery] string? sitecode = null)
        {
            var userSiteCode = User.FindFirst("SiteCode")?.Value;

            if (string.IsNullOrWhiteSpace(sitecode) && !string.IsNullOrWhiteSpace(userSiteCode))
            {
                sitecode = userSiteCode;
            }
            else if (!string.IsNullOrWhiteSpace(userSiteCode) && !string.Equals(userSiteCode, "ALL", StringComparison.OrdinalIgnoreCase))
            {
                sitecode = userSiteCode;
            }

            if (string.IsNullOrWhiteSpace(sitecode))
            {
                return BadRequest("A specific sitecode is required to fetch item stock details.");
            }

            try
            {
                var details = await _repository.GetItemStockDetailsAsync(sitecode);
                return Ok(details);
            }
            catch (System.Exception ex)
            {
                return StatusCode(500, ex.ToString());
            }
        }
```

**Step 4: Run test to verify it passes**

Run: `dotnet test backend/src/EnterpriseAuth.UnitTests/EnterpriseAuth.UnitTests.csproj --filter "FullyQualifiedName~SalesInvoiceControllerTests"`
Expected: PASS (all 3 tests passing).

**Step 5: Commit**

```bash
git add backend/src/EnterpriseAuth.Api/Controllers/SalesInvoiceController.cs backend/src/EnterpriseAuth.UnitTests/SalesInvoiceControllerTests.cs
git commit -m "fix(backend): allow optional sitecode query in GetItemStockDetails with claim fallback"
```

---

### Task 2: Frontend Repository Updates for Passing SiteCode

**Files:**
- Modify: `frontend/lib/features/logistics/data/repositories/sales_invoice_product_repository.dart:165-175`
- Modify: `frontend/lib/features/logistics/data/repositories/sales_invoice_sync_repository.dart:127-130`
- Create: `frontend/test/features/logistics/data/sales_invoice_item_stock_sync_test.dart`

**Step 1: Write the failing test**

Create `frontend/test/features/logistics/data/sales_invoice_item_stock_sync_test.dart` to verify that `SalesInvoiceProductRepository.syncSalesInvoiceItemStockDetails` forwards `sitecode` as a query parameter when provided:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:enterprise_auth_system/features/logistics/data/repositories/sales_invoice_product_repository.dart';

class MockDio extends Mock implements Dio {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockDio mockDio;
  late SalesInvoiceProductRepository repository;

  setUp(() {
    mockDio = MockDio();
    repository = SalesInvoiceProductRepository(mockDio);
  });

  test('syncSalesInvoiceItemStockDetails passes sitecode in queryParameters', () async {
    when(() => mockDio.get(
      'SalesInvoice/itemstockdetails',
      queryParameters: any(named: 'queryParameters'),
    )).thenAnswer((_) async => Response(
      data: <dynamic>[],
      statusCode: 200,
      requestOptions: RequestOptions(path: 'SalesInvoice/itemstockdetails'),
    ));

    // When called with siteCode 'IPL'
    try {
      await repository.syncSalesInvoiceItemStockDetails('IPL');
    } catch (_) {
      // Database interaction might throw in pure unit test without sqflite ffi,
      // but the dio.get call should be verified.
    }

    verify(() => mockDio.get(
      'SalesInvoice/itemstockdetails',
      queryParameters: {'sitecode': 'IPL'},
    )).called(1);
  });
}
```

**Step 2: Run test to verify failure**

Run: `flutter test test/features/logistics/data/sales_invoice_item_stock_sync_test.dart`
Expected: FAIL because `syncSalesInvoiceItemStockDetails` does not take arguments or queryParameters is null.

**Step 3: Update SalesInvoiceProductRepository and SalesInvoiceSyncRepository**

1. In `frontend/lib/features/logistics/data/repositories/sales_invoice_product_repository.dart`:
Update `syncSalesInvoiceItemStockDetails`:
```dart
  Future<void> syncSalesInvoiceItemStockDetails([String? siteCode]) async {
    try {
      final response = await _dio.get(
        'SalesInvoice/itemstockdetails',
        queryParameters: (siteCode != null && siteCode.isNotEmpty)
            ? {'sitecode': siteCode}
            : null,
      );
      final List<dynamic> rawData = response.data;
```

2. In `frontend/lib/features/logistics/data/repositories/sales_invoice_sync_repository.dart`:
Update line 128:
```dart
      // 3. Fetch Sales Invoice Item Stock Details
      await _productRepository.syncSalesInvoiceItemStockDetails(siteCode);
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/features/logistics/data/sales_invoice_item_stock_sync_test.dart`
Expected: PASS.

**Step 5: Commit**

```bash
git add frontend/lib/features/logistics/data/repositories/sales_invoice_product_repository.dart frontend/lib/features/logistics/data/repositories/sales_invoice_sync_repository.dart frontend/test/features/logistics/data/sales_invoice_item_stock_sync_test.dart
git commit -m "fix(frontend): forward siteCode to itemstockdetails sync query"
```

---

### Task 3: Backend Build, Server Restart & Verification

**Files:**
- Test verification on running backend and Flutter client.

**Step 1: Build the backend project**

Run: `dotnet build backend/src/EnterpriseAuth.Api/EnterpriseAuth.Api.csproj`
Expected: `0 Error(s)`, `Build succeeded`.

**Step 2: Run all backend and frontend tests**

1. Backend:
Run: `dotnet test backend/src/EnterpriseAuth.UnitTests/EnterpriseAuth.UnitTests.csproj`
Expected: PASS.

2. Frontend:
Run: `flutter test test/features/logistics/data/sales_invoice_item_stock_sync_test.dart`
Expected: PASS.

**Step 3: Restart Backend Service & Live Verification**

1. Restart the backend API on `http://192.168.100.156:5004`.
2. In the running Flutter app (terminal `dart` 29640 or device), trigger "Sync Sales Data".
3. Verify terminal output:
Expected:
```
I/flutter: *** Request ***
I/flutter: uri: http://192.168.100.156:5004/api/SalesInvoice/itemstockdetails?sitecode=IPL
I/flutter: method: GET
I/flutter: *** Response ***
I/flutter: 200 OK
I/flutter: Successfully synced ... sales invoice item stock details.
```
No `DioException [bad response]: 400` occurs.

**Step 4: Commit and finalize**

```bash
git commit --allow-empty -m "chore: verified sales invoice item stock details sync resolution"
```
