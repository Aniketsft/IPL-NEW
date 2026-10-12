# Hardened Implementation Plan: Site Code Enforcement & Product Location Filtering

## 1. Executive Summary & Flaw Assessment

This document rigorously challenges the initial implementation plan, identifies 6 critical security, concurrency, and SQL flaws, and specifies the hardened architecture to guarantee zero-trust site isolation and robust Sage X3 MSSQL queries.

---

## 2. Flaw Analysis & Challenges to Initial Plan

### Flaw 1: Critical Privilege Escalation on Missing `SiteCode` Claim (Security Flaw)
* **Initial Plan Flaw**: The previous `ResolveEffectiveSiteCode` checked:
  ```csharp
  if (!string.IsNullOrWhiteSpace(userSiteCode) && userSiteCode != "ALL") { return (userSiteCode, null); }
  // Fall-through allowed requestedSiteCode!
  ```
  If an attacker or unassigned user had **no** `SiteCode` claim (empty or null), the helper fell through to allow them to query **any site** via `?sitecode=...`, inadvertently granting unassigned users SuperAdmin privileges!
* **Remediation**: Invert the trust model. A user may *only* query an arbitrary site if they possess the `SiteCode == "ALL"` claim OR belong to `Admin` / `SuperAdmin` roles (`User.IsInRole("Admin") || User.IsInRole("SuperAdmin")`). Any user without a valid `SiteCode` and without admin privileges is immediately rejected with `403 Forbidden`.

### Flaw 2: Sage X3 `CHAR(N)` Whitespace Padding Gotcha (Database Flaw)
* **Initial Plan Flaw**: The proposed filter was:
  ```sql
  AND COALESCE(zlw.LOCTYPNAM_0, '') NOT IN ('IPL Spare Parts', 'IPL Hatchery', 'IPL Packaging Materials', 'IPL Diesel')
  ```
  In Sage X3 MSSQL, `LOCTYPNAM_0` is typically defined as a fixed-length `CHAR(30)` column padded with trailing spaces (e.g., `'IPL Spare Parts             '`). A raw `NOT IN` comparison without trimming can evaluate unpredictably depending on SQL Server ANSI padding and collation settings.
* **Remediation**: Follow the established repository convention by wrapping with `LTRIM(RTRIM(...))`:
  ```sql
  AND LTRIM(RTRIM(COALESCE(zlw.LOCTYPNAM_0, ''))) NOT IN (
      'IPL Spare Parts', 'IPL Hatchery', 'IPL Packaging Materials', 'IPL Diesel'
  )
  ```

### Flaw 3: Concurrency Deadlocks on Sage X3 `STOCK` Table (Performance / Reliability Flaw)
* **Initial Plan Flaw**: The queries on `STOCK`, `ITMMASTER`, and `ZLOCWRH` did not specify `WITH (NOLOCK)`.
  In production ERP environments, Sage X3 frequently acquires exclusive update locks on `STOCK` and `STOLOT` during warehouse receipts, allocations, and stock movements. Read-only mobile synchronization requests can cause lock escalation, timeouts, or deadlocks.
* **Remediation**: Add `WITH (NOLOCK)` hints across all joined Sage X3 tables in read queries, matching [`EfSyncRepository.cs`](file:///d:/enterprise_auth_system/backend/src/EnterpriseAuth.Api/Infrastructure/Persistence/EfSyncRepository.cs).

### Flaw 4: `LEFT JOIN` Accidental Conversion to `INNER JOIN` in `GetProductsAsync` (SQL Logic Flaw)
* **Initial Plan Flaw**: `GetProductsAsync` uses `LEFT JOIN STOCK stk` but places `stk.STOFCY_0 = @SiteCode` in the `WHERE` clause. When a product has no stock at `@SiteCode`, `stk.STOFCY_0` is `NULL`, causing `WHERE stk.STOFCY_0 = @SiteCode` to evaluate to `UNKNOWN/FALSE`, completely filtering out active products that have 0 inventory.
* **Remediation**: 
  - If the business requirement is **only sellable products with positive stock** (consistent with [`GetItemStockDetailsAsync`](file:///d:/enterprise_auth_system/backend/src/EnterpriseAuth.Api/Infrastructure/Persistence/EfSalesInvoiceRepository.cs#L110-L126)), make it an explicit `INNER JOIN` with `stk.QTYSTU_0 > 0` for query optimizer efficiency.
  - If the business requirement is to list **all catalog products** even with 0 stock, move the stock conditions into the `LEFT JOIN ... ON` clause.

### Flaw 5: Hardcoded `'IPL'` Site Prefix Violates Multi-Tenant Architecture (Domain Flaw)
* **Initial Plan Flaw**: Filtering only `'IPL Spare Parts'`, `'IPL Hatchery'`, etc., means that if a user belongs to another site (e.g., `'PNT'`), non-saleable locations for that site (e.g., `'PNT Spare Parts'`, `'PNT Diesel'`) would **not** be excluded.
* **Remediation**: Support dynamic site prefix filtering alongside the user's specific exclusion list:
  ```sql
  AND LTRIM(RTRIM(COALESCE(zlw.LOCTYPNAM_0, ''))) NOT IN (
      'IPL Spare Parts', 'IPL Hatchery', 'IPL Packaging Materials', 'IPL Diesel'
  )
  AND LTRIM(RTRIM(COALESCE(zlw.LOCTYPNAM_0, ''))) NOT LIKE '%Spare Parts%'
  AND LTRIM(RTRIM(COALESCE(zlw.LOCTYPNAM_0, ''))) NOT LIKE '%Packaging Materials%'
  AND LTRIM(RTRIM(COALESCE(zlw.LOCTYPNAM_0, ''))) NOT LIKE '%Diesel%'
  ```

### Flaw 6: Silent Parameter Tampering Without Audit Trail (Observability Flaw)
* **Initial Plan Flaw**: Silently replacing `requestedSiteCode` with `userSiteCode` prevented cross-site access but gave SecOps no visibility into whether a client was actively probing unauthorized sites.
* **Remediation**: Log a security warning (`_logger.LogWarning(...)`) whenever a non-admin client sends a `?sitecode=` parameter that does not match their assigned site code, then enforce the user's assigned site.

---

## 3. Hardened Technical Specifications

### A. Centralized Site Code Resolver Helper
In [`SalesInvoiceController.cs`](file:///d:/enterprise_auth_system/backend/src/EnterpriseAuth.Api/Controllers/SalesInvoiceController.cs) and [`LogisticsController.cs`](file:///d:/enterprise_auth_system/backend/src/EnterpriseAuth.Api/Controllers/LogisticsController.cs):

```csharp
private (string? EffectiveSiteCode, IActionResult? Error) ResolveEffectiveSiteCode(string? requestedSiteCode)
{
    var userSiteCode = User.FindFirst("SiteCode")?.Value;
    bool isMultiSiteAdmin = string.Equals(userSiteCode, "ALL", StringComparison.OrdinalIgnoreCase) 
                            || User.IsInRole("Admin") 
                            || User.IsInRole("SuperAdmin");

    // Case 1: Standard user bound to a specific site
    if (!string.IsNullOrWhiteSpace(userSiteCode) && !string.Equals(userSiteCode, "ALL", StringComparison.OrdinalIgnoreCase))
    {
        if (!string.IsNullOrWhiteSpace(requestedSiteCode) && 
            !string.Equals(requestedSiteCode, userSiteCode, StringComparison.OrdinalIgnoreCase))
        {
            _logger.LogWarning("Security: User {User} assigned to {UserSite} attempted to query unauthorized site {RequestedSite}.",
                User.Identity?.Name, userSiteCode, requestedSiteCode);
        }

        // Authoritatively enforce assigned site
        return (userSiteCode, null);
    }

    // Case 2: Multi-site administrator
    if (isMultiSiteAdmin)
    {
        if (string.IsNullOrWhiteSpace(requestedSiteCode) || string.Equals(requestedSiteCode, "ALL", StringComparison.OrdinalIgnoreCase))
        {
            return (null, BadRequest(new { error = "An explicit sitecode is required. 'ALL' is not permitted for this query." }));
        }

        return (requestedSiteCode, null);
    }

    // Case 3: Unassigned / unauthorized user
    _logger.LogWarning("Security: Unassigned user {User} attempted to access site-scoped resource.", User.Identity?.Name);
    return (null, StatusCode(StatusCodes.Status403Forbidden, new { error = "User account is not assigned to a valid site." }));
}
```

---

### B. Hardened SQL Queries in [`EfSalesInvoiceRepository.cs`](file:///d:/enterprise_auth_system/backend/src/EnterpriseAuth.Api/Infrastructure/Persistence/EfSalesInvoiceRepository.cs)

#### 1. `GetProductsAsync(string sitecode)`
```sql
SELECT 
    LTRIM(RTRIM(itm.ITMREF_0)) AS Sku,
    LTRIM(RTRIM(COALESCE(itm.ITMDES1_0, itm.ZFULLDES_0, ''))) AS Name,
    LTRIM(RTRIM(COALESCE(itm.SAU_0, 'UN'))) AS SalesUnit,
    SUM(COALESCE(stk.QTYSTU_0, 0)) AS StockQty
FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.ITMMASTER itm WITH (NOLOCK)
INNER JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.STOCK stk WITH (NOLOCK)
    ON itm.ITMREF_0 = stk.ITMREF_0 AND stk.STA_0 = 'A'
LEFT JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.ZLOCWRH zlw WITH (NOLOCK)
    ON stk.STOFCY_0 = zlw.WAREHOUSE_0 AND stk.LOC_0 = zlw.LOCATION_0
LEFT JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.STOLOT sl WITH (NOLOCK)
    ON stk.ITMREF_0 = sl.ITMREF_0 AND stk.LOT_0 = sl.LOT_0
WHERE 
    itm.ITMSTA_0 = 1
    AND stk.STOFCY_0 = @SiteCode
    AND stk.QTYSTU_0 > 0
    AND (sl.SHLDAT_0 IS NULL OR sl.SHLDAT_0 >= CAST(GETDATE() AS DATE))
    AND LTRIM(RTRIM(COALESCE(zlw.LOCTYPNAM_0, ''))) NOT IN (
        'IPL Spare Parts', 'IPL Hatchery', 'IPL Packaging Materials', 'IPL Diesel'
    )
GROUP BY 
    LTRIM(RTRIM(itm.ITMREF_0)),
    LTRIM(RTRIM(COALESCE(itm.ITMDES1_0, itm.ZFULLDES_0, ''))),
    LTRIM(RTRIM(COALESCE(itm.SAU_0, 'UN')));
```

#### 2. `GetItemStockDetailsAsync(string sitecode)`
```sql
SELECT 
    LTRIM(RTRIM(COALESCE(zlw.WAREHOUSE_0, stk.WRH_0, stk.STOFCY_0))) AS Warehouse, 
    LTRIM(RTRIM(COALESCE(zlw.WRHNAM_0, stk.STOFCY_0))) AS WarehouseName, 
    LTRIM(RTRIM(stk.LOC_0)) AS Location, 
    LTRIM(RTRIM(COALESCE(zlw.LOCTYPNAM_0, ''))) AS LocationType,
    LTRIM(RTRIM(itm.ITMREF_0)) AS ItemCode,
    LTRIM(RTRIM(COALESCE(itm.ITMDES1_0, itm.ZFULLDES_0, ''))) AS ItemName,  
    SUM(COALESCE(stk.QTYSTU_0, 0)) AS TotalQty,
    LTRIM(RTRIM(COALESCE(stk.LOT_0, ''))) AS LotNumber,
    LTRIM(RTRIM(COALESCE(itm.VACITM_0, 'STD'))) AS TaxLevel,
    LTRIM(RTRIM(COALESCE(itm.CCE_0, ''))) AS Cce0,
    LTRIM(RTRIM(COALESCE(itm.SAU_0, 'UN'))) AS SalesUnit,
    LTRIM(RTRIM(COALESCE(itm.EANCOD_0, ''))) AS Barcode,
    LTRIM(RTRIM(stk.STOFCY_0)) AS SiteCode
FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.STOCK stk WITH (NOLOCK)
INNER JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.ITMMASTER itm WITH (NOLOCK)
    ON stk.ITMREF_0 = itm.ITMREF_0 AND itm.ITMSTA_0 = 1
LEFT JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.ZLOCWRH zlw WITH (NOLOCK)
    ON stk.STOFCY_0 = zlw.WAREHOUSE_0 AND stk.LOC_0 = zlw.LOCATION_0
LEFT JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.STOLOT sl WITH (NOLOCK)
    ON stk.ITMREF_0 = sl.ITMREF_0 AND stk.LOT_0 = sl.LOT_0
WHERE stk.STOFCY_0 = @SiteCode 
  AND stk.STA_0 = 'A'
  AND stk.QTYSTU_0 > 0
  AND (sl.SHLDAT_0 IS NULL OR sl.SHLDAT_0 >= CAST(GETDATE() AS DATE))
  AND LTRIM(RTRIM(COALESCE(zlw.LOCTYPNAM_0, ''))) NOT IN (
      'IPL Spare Parts', 'IPL Hatchery', 'IPL Packaging Materials', 'IPL Diesel'
  )
GROUP BY 
    stk.STOFCY_0, COALESCE(zlw.WAREHOUSE_0, stk.WRH_0, stk.STOFCY_0), COALESCE(zlw.WRHNAM_0, stk.STOFCY_0), 
    stk.LOC_0, zlw.LOCTYPNAM_0,
    itm.ITMREF_0, COALESCE(itm.ITMDES1_0, itm.ZFULLDES_0, ''), stk.LOT_0, itm.VACITM_0, itm.CCE_0, itm.SAU_0, itm.EANCOD_0
ORDER BY 
    stk.STOFCY_0, itm.ITMREF_0, stk.LOT_0;
```

---

## 4. Execution Plan & Validation Milestones

- [ ] **Milestone 1**: Apply hardened queries with `LTRIM(RTRIM(...))` and `WITH (NOLOCK)` in [`EfSalesInvoiceRepository.cs`](file:///d:/enterprise_auth_system/backend/src/EnterpriseAuth.Api/Infrastructure/Persistence/EfSalesInvoiceRepository.cs).
- [ ] **Milestone 2**: Implement zero-trust `ResolveEffectiveSiteCode` with security audit logging in [`SalesInvoiceController.cs`](file:///d:/enterprise_auth_system/backend/src/EnterpriseAuth.Api/Controllers/SalesInvoiceController.cs) (`GetProducts`, `GetItemStockDetails`, `GetSalesReps`).
- [ ] **Milestone 3**: Audit and apply site enforcement to [`LogisticsController.cs`](file:///d:/enterprise_auth_system/backend/src/EnterpriseAuth.Api/Controllers/LogisticsController.cs) (`GetProductionTracking`, `GetLocations`, `GetLots`, `GetBarcodeMappings`).
- [ ] **Milestone 4**: Verify compilation via `dotnet build` with 0 warnings/errors.
- [ ] **Milestone 5**: Security & Isolation Testing:
  1. Authenticated user with `SiteCode = 'IPL'` sending `?sitecode=PNT` &rarr; Returns data strictly from `IPL` and logs audit warning.
  2. Authenticated user with no site claim &rarr; Returns `403 Forbidden`.
  3. SuperAdmin with `SiteCode = 'ALL'` &rarr; Successfully queries specific sites via `?sitecode=IPL`.
  4. Query output verification &rarr; Confirm locations `'IPL Spare Parts'`, `'IPL Hatchery'`, `'IPL Packaging Materials'`, and `'IPL Diesel'` are excluded.
