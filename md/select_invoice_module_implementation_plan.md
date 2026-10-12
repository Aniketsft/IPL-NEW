# Implementation Plan: "Open Invoice" Module (INV & CN)

## 1. Executive Summary & Core Mandate

The **"Open Invoice"** module enables field sales agents to view outstanding customer invoices (`INV`) and credit notes (`CN`), select documents, specify payment or allocation amounts (full or partial), and proceed to payment processing with receipt generation.

### Core Architecture Mandates
1. **100% Offline-First**: Open invoices and credit notes are pulled during data sync and stored in local SQLite (`tbl_si_open_invoices`). Field agents browse, filter, select, and process payments without any network dependency.
2. **Unified Open Items (INV + CN)**: Invoices represent positive open balances (`SNS_0 = 1`); credit notes represent negative open balances (`SNS_0 = -1`). The system supports standalone invoice payment, credit note refunds, and offsetting credit notes against invoices.
3. **Card-Based Industrial UI**: Documents are displayed as structured cards with badges, due date countdowns/overdue alerts, customer metadata, and interactive payment amount selectors.
4. **Standard Widget Reuse**: Scaffolding reuses [`IndustrialModuleLayout`](file:///d:/enterprise_auth_system/frontend/lib/core/widgets/industrial_module_layout.dart), [`SearchPickerSheet`](file:///d:/enterprise_auth_system/frontend/lib/core/widgets/search_picker_sheet.dart), and styling from [`SalesOrderCard`](file:///d:/enterprise_auth_system/frontend/lib/features/logistics/presentation/widgets/sales_order_card.dart) to eliminate redundant code.
5. **Strict Authoritative Site Scoping**: Follows the zero-trust `SiteCode` claim enforcement established in the backend API and mirrors the filter in local SQLite queries.

---

## 2. Sage X3 Data Dictionary Mapping & Hardened Query

### Data Dictionary Analysis
| Table | Alias | Column | Type | Business Rule & Mapping |
| :--- | :--- | :--- | :--- | :--- |
| `GACCDUDATE` | `DUD` | `NUM_0` | `CHAR(20)` | Document Number (Invoice or Credit Note number). |
| `GACCDUDATE` | `DUD` | `LIG_0` | `SHORT` | Due date installment line number. |
| `GACCDUDATE` | `DUD` | `DUDDAT_0` | `DATETIME` | Due Date of the installment. |
| `GACCDUDATE` | `DUD` | `AMTCUR_0` | `DECIMAL(14,2)` | Installment amount in transaction currency (always positive). |
| `GACCDUDATE` | `DUD` | `PAYCUR_0` | `DECIMAL(14,2)` | Amount already paid in transaction currency. |
| `GACCDUDATE` | `DUD` | `TMPCUR_0` | `DECIMAL(14,2)` | In-process provisional allocations. Filter: `AMTCUR_0 > PAYCUR_0 + TMPCUR_0`. |
| `GACCDUDATE` | `DUD` | `SNS_0` | `SHORT` | Sign indicator: `+1` = Debit (Invoice), `-1` = Credit (Credit Note / Advance). |
| `GACCDUDATE` | `DUD` | `DUDSTA_0` | `TINYINT` | Open item status: `2` = Open / Authorized for payment (`1` = Draft, `3` = Closed). |
| `GACCDUDATE` | `DUD` | `FCY_0` | `CHAR(5)` | Financial / Sales Site code (e.g. `INL01`). Filtered strictly by user `SiteCode`. |
| `GACCDUDATE` | `DUD` | `CPY_0` | `CHAR(5)` | Legal Company code (e.g. `INL`). |
| `GACCDUDATE` | `DUD` | `CUR_0` | `CHAR(3)` | Currency code. Joined with general ledger currency. |
| `GACCDUDATE` | `DUD` | `BPRPAY_0` | `CHAR(15)` | Pay-by Business Partner code. Joined to `BPCUSTOMER.BPCNUM_0`. |
| `BPCUSTOMER` | `BPC` | `BPCNUM_0` | `CHAR(15)` | Customer Code. |
| `BPCUSTOMER` | `BPC` | `BPCNAM_0` | `CHAR(35)` | Primary Customer Name. Mapped directly to customer code. |
| `BPARTNER` | `BPR` | `BPRNAM_0` | `CHAR(35)` | Business Partner Name (fallback if `BPCNAM_0` is blank). |
| `COMPANY` | `CPY` | `CPY_0` / `ACM_0` | `CHAR(5)` | Legal company master and accounting model. |
| `GACM` | `GCM` | `GCM_0` / `CUR_0` | `CHAR(3)` | General accounting model ledger currency. Joined on `DUD.CUR_0 = GCM.CUR_0`. |

### Hardened MSSQL Query
```sql
SELECT 
    LTRIM(RTRIM(BPC.BPCNUM_0))                                              AS CustomerNo,
    LTRIM(RTRIM(COALESCE(BPC.BPCNAM_0, bpr.BPRNAM_0, '')))                 AS CustomerName,
    LTRIM(RTRIM(DUD.NUM_0))                                                 AS DocumentNo,
    DUD.DUDDAT_0                                                            AS DueDate,
    LTRIM(RTRIM(DUD.FCY_0))                                                 AS Site,
    LTRIM(RTRIM(DUD.CPY_0))                                                 AS Company,
    CASE 
        WHEN SUM((DUD.AMTCUR_0 - DUD.PAYCUR_0) * DUD.SNS_0) < 0 THEN 'CN'
        ELSE 'INV'
    END                                                                     AS DocType,
    SUM((DUD.AMTCUR_0 - DUD.PAYCUR_0) * DUD.SNS_0)                           AS RemainingAmtLCY
FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.[GACCDUDATE] DUD WITH (NOLOCK)
INNER JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.[COMPANY] CPY WITH (NOLOCK)
    ON DUD.CPY_0 = CPY.CPY_0
INNER JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.[GACM] GCM WITH (NOLOCK)
    ON GCM.GCM_0 = CPY.ACM_0 
   AND DUD.CUR_0 = GCM.CUR_0
INNER JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.[BPCUSTOMER] BPC WITH (NOLOCK)
    ON DUD.BPRPAY_0 = BPC.BPCNUM_0
LEFT JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.[BPARTNER] bpr WITH (NOLOCK)
    ON BPC.BPCNUM_0 = bpr.BPRNUM_0
WHERE DUD.AMTCUR_0 > (DUD.PAYCUR_0 + DUD.TMPCUR_0)
  AND DUD.DUDSTA_0 = 2
  AND (@siteCode IS NULL OR @siteCode = '' OR @siteCode = 'ALL' OR DUD.FCY_0 = @siteCode)
  AND (@customerNo IS NULL OR @customerNo = '' OR BPC.BPCNUM_0 = @customerNo)
GROUP BY 
    BPC.BPCNUM_0, 
    COALESCE(BPC.BPCNAM_0, bpr.BPRNAM_0, ''), 
    DUD.NUM_0, 
    DUD.DUDDAT_0, 
    DUD.FCY_0, 
    DUD.CPY_0
ORDER BY DUD.DUDDAT_0 ASC, DUD.NUM_0 ASC;
```

---

## 3. Rigorous Architectural Challenge: 7 Critical Flaws & Solutions

### Challenge 1: Multi-Installment Invoices (`LIG_0`)
* **Flaw**: An invoice in Sage X3 can have multiple due dates/installments (e.g. 50% on Day 30, 50% on Day 60). Grouping by `NUM_0, DUDDAT_0` generates multiple rows with the same `DocumentNo`. If SQLite uses `documentNo PRIMARY KEY`, it crashes with a UNIQUE constraint failure.
* **Solution**: In SQLite, use a composite unique constraint or synthetic primary key:
  ```sql
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  documentNo TEXT NOT NULL,
  dueDate TEXT NOT NULL,
  UNIQUE(documentNo, dueDate)
  ```

### Challenge 2: Credit Note Offset vs Refund Workflow Disambiguation
* **Flaw**: Mixing invoices (positive) and credit notes (negative) creates 3 distinct payment paths that cannot share a single naive checkout button:
  1. **Invoice Only**: Total Payable > 0. Standard payment receipt.
  2. **Invoice + CN Offset**: Total Payable > 0. CN balance reduces cash needed.
  3. **CN Only / CN Exceeds Invoice**: Total Payable < 0. This is a Customer Refund or Payout.
* **Solution**: The checkout bar dynamically detects the sign of `NetPayable`:
  - `NetPayable > 0`: Shows **"Proceed to Payment (RS X,XXX.XX)"**.
  - `NetPayable == 0`: Shows **"Complete Balance Offset (RS 0.00)"** (No cash collected).
  - `NetPayable < 0`: Shows **"Process Credit Refund (-RS X,XXX.XX)"** with confirmation modal.

### Challenge 3: In-Flight Sync Reconciliation (Reversion Bug)
* **Flaw**: If an agent pays RS 4,000 against an invoice of RS 10,000 while offline, the local remaining balance is RS 6,000. When they tap "Sync", if Sage X3 hasn't finished posting the payment entry yet, the fresh pull from `GACCDUDATE` returns the old balance of RS 10,000, resetting the agent's work!
* **Solution**: The sync pull logic in `SalesInvoiceSyncRepository` performs local reconciliation:
  ```dart
  effectiveRemaining = rawRemainingFromX3 - sumOfUnsyncedPaymentsForDocument(docNo);
  if (effectiveRemaining <= 0) isPaid = 1;
  ```

### Challenge 4: Offline Double-Allocation Protection
* **Flaw**: An agent could select the same invoice multiple times across different draft orders or transactions.
* **Solution**: Once a payment is submitted offline, `tbl_si_open_invoices.remainingAmtLCY` is decremented in SQLite immediately inside a database transaction. If the balance reaches 0, `isPaid` is set to `1` and excluded from the active invoice list.

### Challenge 5: IEEE-754 Currency Rounding Errors
* **Flaw**: SQLite stores floating point numbers as `REAL`. Repeating decimal subtraction (e.g. `100.0 - 33.33`) yields `66.67000000000002`, failing exact balance comparisons (`== 0.0`).
* **Solution**: Every balance calculation in Dart and SQLite queries is explicitly rounded to 2 decimals:
  `double.parse(value.toStringAsFixed(2))`.

### Challenge 6: Authoritative Site Code Isolation
* **Flaw**: A user assigned to `INL01` might query SQLite without filtering by site, seeing records belonging to `INL02`.
* **Solution**: Two-tier security:
  - Backend: `SalesInvoiceController.ResolveEffectiveSiteCode` forces user's `SiteCode` claim.
  - Frontend: `LocalDatabaseHelper.getOpenInvoices` injects `WHERE site = ?` based on the authenticated session.

### Challenge 7: Redundant Widget Duplication
* **Flaw**: Creating bespoke cards, search pickers, and headers increases code bloat and creates inconsistent UI.
* **Solution**:
  - Screen Scaffolding: Use [`IndustrialModuleLayout`](file:///d:/enterprise_auth_system/frontend/lib/core/widgets/industrial_module_layout.dart).
  - Search Picker: Use [`SearchPickerSheet`](file:///d:/enterprise_auth_system/frontend/lib/core/widgets/search_picker_sheet.dart) or [`StandardFilter`](file:///d:/enterprise_auth_system/frontend/lib/core/widgets/standard_filter.dart).
  - Card Widget: Create [`OpenInvoiceCard`](file:///d:/enterprise_auth_system/frontend/lib/features/logistics/presentation/widgets/open_invoice_card.dart) adhering strictly to [`SalesOrderCard`](file:///d:/enterprise_auth_system/frontend/lib/features/logistics/presentation/widgets/sales_order_card.dart) design tokens.

---

## 4. Local SQLite Architecture (`LocalDatabaseHelper.dart` v88)

### Table 1: `tbl_si_open_invoices` (Cached Open Items)
```sql
CREATE TABLE IF NOT EXISTS tbl_si_open_invoices (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    documentNo TEXT NOT NULL,
    customerNo TEXT NOT NULL,
    customerName TEXT,
    dueDate TEXT NOT NULL,
    site TEXT NOT NULL,
    company TEXT NOT NULL,
    docType TEXT NOT NULL,          -- 'INV' or 'CN'
    remainingAmtLCY REAL NOT NULL,  -- Positive for INV, Negative for CN
    allocatedAmount REAL DEFAULT 0.0,
    isPaid INTEGER DEFAULT 0,       -- 1 when settled locally offline
    lastSyncAt TEXT,
    UNIQUE(documentNo, dueDate)
);

CREATE INDEX IF NOT EXISTS idx_open_inv_cust ON tbl_si_open_invoices(customerNo);
CREATE INDEX IF NOT EXISTS idx_open_inv_site ON tbl_si_open_invoices(site);
CREATE INDEX IF NOT EXISTS idx_open_inv_type ON tbl_si_open_invoices(docType);
```

### Table 2: `tbl_si_open_invoice_payments` (Offline Staging Outbox)
```sql
CREATE TABLE IF NOT EXISTS tbl_si_open_invoice_payments (
    paymentId TEXT PRIMARY KEY,
    documentNo TEXT NOT NULL,
    customerNo TEXT NOT NULL,
    amount REAL NOT NULL,
    paymentMethod TEXT NOT NULL,    -- 'CASH', 'CHEQUE', 'BLINK', 'MYT MONEY', 'CN_OFFSET'
    bankCode TEXT,
    bankName TEXT,
    chequeNumber TEXT,
    chequeDate TEXT,
    qrTransactionRef TEXT,
    siteCode TEXT,
    company TEXT,
    createdAt TEXT,
    userName TEXT,
    deviceId TEXT,
    isSynced INTEGER DEFAULT 0,
    syncedAt TEXT
);
```

---

## 5. UI Card Component Design Specification

### `OpenInvoiceCard` (Standard Reusable Widget)
* **Container**: Border radius 12, theme card color, subtle elevation / border matching [`SalesOrderCard`](file:///d:/enterprise_auth_system/frontend/lib/features/logistics/presentation/widgets/sales_order_card.dart).
* **Card Header**:
  * **Document Badge**:
    * `INV`: Emerald Green / Primary Blue badge (`[INV] INV2400192`).
    * `CN`: Amber / Purple badge (`[CN] CN2400031`).
  * **Due Date Chip**:
    * If `dueDate < today`: Red badge (`Overdue by X days`).
    * If `dueDate >= today`: Grey/Amber badge (`Due: YYYY-MM-DD`).
* **Customer Info**:
  * Customer Name in bold headline (e.g. `ABC Supermarket Ltd`).
  * Customer Code subtitle in mono font (e.g. `Code: BPC00123`).
* **Financial Row**:
  * **Total Open Amount**: Large formatted text (e.g. `RS 14,500.00` or `-RS 2,500.00`).
* **Selection & Allocation Footer**:
  * Checkbox toggle for selection.
  * When selected, expands inline quick-allocation buttons:
    * `[ Pay Full: RS 14,500.00 ]`
    * `[ Custom Amount: TextField ]`

---

## 6. Phased Implementation Roadmap

### Phase 1: Backend Infrastructure (C# / ASP.NET Core)
1. **DTOs**:
   * Add `OpenInvoiceDto.cs` in `Core.Application.DTOs`.
   * Add `OpenInvoicePaymentSyncDto.cs` for syncing staged payments.
2. **Repository**:
   * Implement `GetOpenInvoicesAsync(string? siteCode, string? customerNo)` in [EfSalesInvoiceRepository.cs](file:///d:/enterprise_auth_system/backend/src/EnterpriseAuth.Api/Infrastructure/Persistence/EfSalesInvoiceRepository.cs) using the query above with `BPCNAM_0` and `bpr.BPRNAM_0`.
3. **Controller**:
   * Add `GET /api/SalesInvoice/open-invoices` in [SalesInvoiceController.cs](file:///d:/enterprise_auth_system/backend/src/EnterpriseAuth.Api/Controllers/SalesInvoiceController.cs), guarded by [ResolveEffectiveSiteCode](file:///d:/enterprise_auth_system/backend/src/EnterpriseAuth.Api/Controllers/SalesInvoiceController.cs#L406-L440).
   * Add `POST /api/SalesInvoice/open-invoices/payments/sync` to ingest staged offline payments.

### Phase 2: Frontend Database & Sync Engine (Flutter / SQLite)
1. **Database Helper**:
   * Increment `_databaseVersion` to `88` in [LocalDatabaseHelper.dart](file:///d:/enterprise_auth_system/frontend/lib/features/logistics/data/local/local_database_helper.dart).
   * Implement `tbl_si_open_invoices` and `tbl_si_open_invoice_payments` in `_onCreate` and `_onUpgrade`.
   * Add CRUD and reconciliation helper methods.
2. **Sync Repository**:
   * Update [SalesInvoiceSyncRepository.dart](file:///d:/enterprise_auth_system/frontend/lib/features/logistics/data/repositories/sales_invoice_sync_repository.dart) to push unsynced invoice payments and pull fresh open items with local payment reconciliation.

### Phase 3: Frontend Presentation & Workflow (Flutter UI)
1. **Sales Menu Screen**:
   * In [SalesMenuScreen.dart](file:///d:/enterprise_auth_system/frontend/lib/features/logistics/presentation/pages/sales_invoice/sales_menu_screen.dart), add the **"Select Invoice"** tile (`Icons.receipt_long_rounded`).
2. **Card Widget**:
   * Create `open_invoice_card.dart` using standard project widgets and theme tokens.
3. **Select Invoice Screen**:
   * Create `select_invoice_screen.dart` with customer search, filter tabs (`All`, `INV`, `CN`), cards list, and dynamic net payable checkout bar.
4. **Payment Flow**:
   * Route to `open_invoice_payment_screen.dart` (Cash, Cheque, QR, CN offset), update SQLite, and generate receipt.

---

## 7. Acceptance & Verification Matrix

1. **Query Accuracy**: Verify query returns both positive `INV` and negative `CN` documents, correctly mapped with customer names and filtered by user `SiteCode`.
2. **Card UX**: Cards display badges, overdue indicators, customer code & name, and amount input smoothly.
3. **100% Offline Workflow**:
   * Field agent opens "Open Invoice" offline.
   * Filters and selects invoice and credit note.
   * Enters amount and completes payment.
   * Invoice is marked paid locally; receipt prints cleanly.
4. **Sync Verification**: Reconnecting and pressing "Sync" pushes staged payments to backend without data loss or reversion.

---

## 8. Implementation Status (Completed)

| Component | Target File | Status | Description |
| :--- | :--- | :--- | :--- |
| **Backend DTOs** | `OpenInvoiceDto.cs` | Completed | Added `OpenInvoiceDto` & `OpenInvoicePaymentSyncDto` |
| **Backend Repository** | `ISalesInvoiceRepository.cs`, `EfSalesInvoiceRepository.cs` | Completed | Hardened query joining `GACCDUDATE`, `COMPANY`, `GACM`, `BPCUSTOMER`, `BPARTNER` with `WITH (NOLOCK)` and site code filtering |
| **Backend Controller** | `SalesInvoiceController.cs` | Completed | Added `GET api/SalesInvoice/open-invoices` (guarded by `ResolveEffectiveSiteCode`) and `POST api/SalesInvoice/open-invoices/payments/sync` |
| **Frontend SQLite** | `LocalDatabaseHelper.dart` | Completed | Upgraded DB version to `88`, added `tbl_si_open_invoices` & `tbl_si_open_invoice_payments`, CRUD & in-flight reconciliation methods |
| **Sync Engine** | `SalesInvoiceSyncRepository.dart` | Completed | Integrated open invoices fetch and offline staged payments push into `synchronizeSalesInvoiceData` |
| **Data Model** | `open_invoice_model.dart` | Completed | Model with `isCreditNote`, `isInvoice`, `fromMap`, `toMap` |
| **Industrial Card UI** | `open_invoice_card.dart` | Completed | Reusable card widget matching `SalesOrderCard` tokens, badges, overdue tags, and inline allocation controls |
| **Payment Flow** | `open_invoice_payment_screen.dart` | Completed | Offline payment allocation across Cash, Cheque, Blink/my.t, CN offset with atomic local updates |
| **Main Screen** | `open_invoices_screen.dart` | Completed | "Open Invoice" module screen using `IndustrialModuleLayout`, search, customer filter, type filter, and sticky checkout |
| **Navigation Tile** | `sales_menu_screen.dart` | Completed | Added **"Open Invoice"** module tile with `Icons.receipt_long_rounded` |

