# Implementation Plan: Map User Site Code to Tested Open Invoices Query

**Document:** `user_site_open_invoices_query_plan.md`  
**Date:** October 12, 2026  
**Module:** Enterprise Sales & Accounting Sync (`EnterpriseAuth.Api` & `enterprise_auth_mobile`)  
**Targets:**
- [EfSalesInvoiceRepository.cs](file:///d:/enterprise_auth_system/backend/src/EnterpriseAuth.Api/Infrastructure/Persistence/EfSalesInvoiceRepository.cs)
- [OpenInvoiceDto.cs](file:///d:/enterprise_auth_system/backend/src/EnterpriseAuth.Api/Core/Application/DTOs/OpenInvoiceDto.cs)
- [SalesInvoiceController.cs](file:///d:/enterprise_auth_system/backend/src/EnterpriseAuth.Api/Controllers/SalesInvoiceController.cs)
- [open_invoice_model.dart](file:///d:/enterprise_auth_system/frontend/lib/features/logistics/data/models/open_invoice_model.dart)
- [local_database_helper.dart](file:///d:/enterprise_auth_system/frontend/lib/features/logistics/data/local/local_database_helper.dart)

---

## 1. Context & Objectives

The user tested and validated the following T-SQL query in MSSQL for Sage X3 (`INLPROD`):

```sql
SELECT  
    BPC.BPCNUM_0                                                         AS CustomerNo,
    LTRIM(RTRIM(COALESCE(BPC.BPCNAM_0, '')))                             AS CustomerName,
    DUD.NUM_0                                                            AS DocumentNo,
    DUD.DUDDAT_0                                                         AS DueDate,
    LTRIM(RTRIM(DUD.FCY_0))                                              AS Site,
    LTRIM(RTRIM(DUD.CPY_0))                                              AS Company,
    CASE 
        WHEN SUM((DUD.AMTCUR_0 - DUD.PAYCUR_0) * DUD.SNS_0) < 0 THEN 'CN'
        ELSE 'INV'
    END                                                                  AS DocType,
    SUM((DUD.AMTCUR_0 - DUD.PAYCUR_0) * DUD.SNS_0)                       AS RemainingAmtLCY

FROM INLPROD.[GACCDUDATE] DUD,  
     INLPROD.[COMPANY] CPY, 
     INLPROD.[GACM] GCM, 
     INLPROD.[BPCUSTOMER] BPC

WHERE DUD.CPY_0    = CPY.CPY_0
  AND GCM.GCM_0    = CPY.ACM_0 
  AND DUD.CUR_0    = GCM.CUR_0
  AND DUD.BPRPAY_0 = BPC.BPCNUM_0
  AND DUD.AMTCUR_0 > DUD.PAYCUR_0 + DUD.TMPCUR_0 
  AND DUD.DUDSTA_0 = 2
  -- Filtered strictly by site attached to user:
  AND LTRIM(RTRIM(DUD.FCY_0)) = 'IPL'
  
  -- Rolling 90-day cutoff:
  AND DUD.DUDDAT_0 >= DATEADD(day, -90, CAST(GETDATE() AS DATE))

GROUP BY  
    BPC.BPCNUM_0,
    BPC.BPCNAM_0,
    DUD.NUM_0,
    DUD.DUDDAT_0, 
    DUD.FCY_0, 
    DUD.CPY_0

ORDER BY DUD.DUDDAT_0 ASC, DUD.NUM_0 ASC;
```

### Objectives
1. Replace the hardcoded `'IPL'` site with the **site code attached to the authenticated user** (`User.FindFirst("SiteCode")?.Value`).
2. Remove `REP_1` completely from query and projections, filtering **solely by site** attached to the user.
3. Ensure the 90-day cutoff (`DATEADD(day, -90, CAST(GETDATE() AS DATE))`) is enforced.
4. Maintain full multi-tenant schema compatibility (`{_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}`).

---

## 2. Technical Mapping Architecture

### 2.1 User Site Code Resolution & Flow

```
┌────────────────────────────────────────────────────────┐
│             Mobile Client (JWT Authenticated)          │
│             User: Field Rep / Van Salesman             │
│             Claims: { "SiteCode": "IPL", ... }         │
└───────────────────────────┬────────────────────────────┘
                            │
              GET api/SalesInvoice/open-invoices
                            │
                            ▼
┌────────────────────────────────────────────────────────┐
│         SalesInvoiceController.GetOpenInvoices         │
│                                                        │
│  var (effectiveSite, error) = ResolveEffectiveSiteCode()│
│  - Extracts User.FindFirst("SiteCode")?.Value          │
│  - Prevents querying other sites (anti-tamper)         │
│  - Resolves 'IPL' from user identity                   │
└───────────────────────────┬────────────────────────────┘
                            │
              GetOpenInvoicesAsync(effectiveSite, ...)
                            │
                            ▼
┌────────────────────────────────────────────────────────┐
│             EfSalesInvoiceRepository                   │
│                                                        │
│  WHERE ...                                             │
│    AND LTRIM(RTRIM(DUD.FCY_0)) = @SiteCode             │
│    AND DUD.DUDDAT_0 >= DATEADD(day, -90, GETDATE())   │
│                                                        │
│  Dapper: new { SiteCode = effectiveSite }              │
└────────────────────────────────────────────────────────┘
```

---

## 3. Implementation Steps

### Step 1: Update DTOs (Backend & Frontend)
**Backend Target:** [OpenInvoiceDto.cs](file:///d:/enterprise_auth_system/backend/src/EnterpriseAuth.Api/Core/Application/DTOs/OpenInvoiceDto.cs)
- Add property `public string Rep1 { get; set; } = string.Empty;`.

**Frontend Target:** [open_invoice_model.dart](file:///d:/enterprise_auth_system/frontend/lib/features/logistics/data/models/open_invoice_model.dart)
- Add field `final String rep1;`.
- Map `rep1: (map['rep1'] ?? map['REP_1'] ?? map['Rep1'] ?? '').toString().trim()`.

---

### Step 2: Implement User-Scoped Query in Repository
**Target:** [EfSalesInvoiceRepository.cs](file:///d:/enterprise_auth_system/backend/src/EnterpriseAuth.Api/Infrastructure/Persistence/EfSalesInvoiceRepository.cs)
- Update `GetOpenInvoicesAsync` to adopt the user's tested query structure while dynamically parameterizing the Site Code and Schema:

```csharp
public async Task<IEnumerable<OpenInvoiceDto>> GetOpenInvoicesAsync(
    string? siteCode = null, 
    string? customerNo = null, 
    string? salesReps = null, 
    int daysCutoff = 90)
{
    using IDbConnection db = new SqlConnection(_connectionString);
    var dbName = _syncSettings.X3DatabaseName;
    var schema = _schemaProvider.GetSchemaName();

    string sql = $@"
        SELECT  
            LTRIM(RTRIM(BPC.BPCNUM_0))                                              AS CustomerNo,
            LTRIM(RTRIM(COALESCE(BPC.BPCNAM_0, '')))                             AS CustomerName,
            LTRIM(RTRIM(DUD.NUM_0))                                                 AS DocumentNo,
            DUD.DUDDAT_0                                                            AS DueDate,
            LTRIM(RTRIM(DUD.FCY_0))                                                 AS Site,
            LTRIM(RTRIM(DUD.CPY_0))                                                 AS Company,
            CASE 
                WHEN SUM((DUD.AMTCUR_0 - DUD.PAYCUR_0) * DUD.SNS_0) < 0 THEN 'CN'
                ELSE 'INV'
            END                                                                     AS DocType,
            SUM((DUD.AMTCUR_0 - DUD.PAYCUR_0) * DUD.SNS_0)                           AS RemainingAmtLCY

        FROM {dbName}.{schema}.[GACCDUDATE] DUD WITH (NOLOCK),  
             {dbName}.{schema}.[COMPANY] CPY WITH (NOLOCK), 
             {dbName}.{schema}.[GACM] GCM WITH (NOLOCK), 
             {dbName}.{schema}.[BPCUSTOMER] BPC WITH (NOLOCK)

        WHERE DUD.CPY_0    = CPY.CPY_0
          AND GCM.GCM_0    = CPY.ACM_0 
          AND DUD.CUR_0    = GCM.CUR_0
          AND DUD.BPRPAY_0 = BPC.BPCNUM_0
          AND DUD.AMTCUR_0 > DUD.PAYCUR_0 + DUD.TMPCUR_0 
          AND DUD.DUDSTA_0 = 2
          
          -- Enforce site code attached to the user:
          AND (@SiteCode = '' OR @SiteCode = 'ALL' OR LTRIM(RTRIM(DUD.FCY_0)) = @SiteCode)
          
          -- 90-day rolling cutoff window:
          AND DUD.DUDDAT_0 >= DATEADD(day, -@DaysCutoff, CAST(GETDATE() AS DATE))

          -- Optional single customer filter if requested:
          AND (@CustomerNo = '' OR BPC.BPCNUM_0 = @CustomerNo)

        GROUP BY  
            BPC.BPCNUM_0,
            BPC.BPCNAM_0,
            DUD.NUM_0,
            DUD.DUDDAT_0, 
            DUD.FCY_0, 
            DUD.CPY_0

        ORDER BY DUD.DUDDAT_0 ASC, DUD.NUM_0 ASC;
    ";

    return await db.QueryAsync<OpenInvoiceDto>(sql, new 
    { 
        SiteCode = (siteCode ?? "").Trim(),
        CustomerNo = (customerNo ?? "").Trim(),
        DaysCutoff = daysCutoff > 0 ? daysCutoff : 90
    });
}
```

---

### Step 3: Verify Controller Authoritative Site Binding
**Target:** [SalesInvoiceController.cs](file:///d:/enterprise_auth_system/backend/src/EnterpriseAuth.Api/Controllers/SalesInvoiceController.cs)
- Confirm `ResolveEffectiveSiteCode(sitecode)` extracts the authenticated user's claim:
  ```csharp
  var userSiteCode = User.FindFirst("SiteCode")?.Value;
  ```
- If a standard user has claim `SiteCode = 'IPL'`, `effectiveSite` will always resolve to `'IPL'` regardless of what was requested on the wire, ensuring strict multi-tenant site isolation.

---

### Step 4: Update Frontend Storage & Sync
**Target:** [local_database_helper.dart](file:///d:/enterprise_auth_system/frontend/lib/features/logistics/data/local/local_database_helper.dart)
- In `refreshOpenInvoices`:
  Store `rep1: (map['rep1'] ?? map['REP_1'] ?? '').toString().trim()`.
- Add column `rep1 TEXT` in SQLite table if needed or map into model.

---

## 4. Verification & Testing Checklist

| Test Item | Steps | Expected Result |
| :--- | :--- | :--- |
| **Site Code Mapping** | Login as user with `SiteCode = 'IPL'`. Call `GET api/SalesInvoice/open-invoices`. | Query binds `@SiteCode = 'IPL'`. Only documents for site `IPL` are returned. |
| **90-Day Filter** | Check oldest `DueDate` in returned records. | All returned records have `DueDate >= Today - 90 Days`. |
| **REP_1 Mapping** | Inspect JSON response. | Each record includes `rep1` corresponding to `BPC.REP_1`. |
| **Credit Notes (CN)** | Review records with negative amounts. | `DocType = 'CN'` and negative `RemainingAmtLCY`. |
| **Mobile Sync** | Run mobile sync with logged in user. | Open invoices synced seamlessly into SQLite. |
