# Active Milestone & Context

## Current Status (Updated: 2026-10-26)
- **Customer Return & Credit Note Architecture**:
  - Differentiator: `stockTransaction` field (`1` for physical return + refund, `0` for pure credit note).
  - Selection: Tap or Long-press selects line items; "MAX" button sets exact remaining quantity.
  - Reversal: Catch-weight precision handled (e.g. 0.858 KG) with `_resolveEffectiveQty` using `0.005` tolerance clamping.
  - Disbursement: Cash refund confirmation works without database lock (deadlock resolved by moving `getDefaultBank` before `db.transaction`).
  - Persistence: Header saved in `tbl_si_credit_notes` with `stockTransaction = 1`.
  - **X3 Historic Pricing & Reversal Protection (Implemented 2026-10-26)**:
    - Unit price locked to Sage X3 `NETPRI_0` (or `amtNot / qty` fallback); prevented falling back to full line total amount.
    - Historical VAT rate computed from `(amtInc - amtNot) / amtNot * 100` (e.g. 15% VAT) and preserved throughout return cart.
    - X3 invoice lines tracked in `tbl_si_invoice_line_reversals` by matching `tbl_x3_history_lines.lineNumber`, permanently locking returned quantities against duplicate returns.
    - Stock replenishment on physical returns (`stockTransaction == 1`) defaults warehouse to user site and lot to `'RETURN'` if empty.
    - `allowCatalogProductAddition: false` for returns, ensuring only items from the original X3 invoice can be returned.
  - Next Step: Awaiting user Sage X3 Miscellaneous Receipt SOAP XML and field mapping to wire backend stock-in.

- **Agent Memory System**:
  - Graphify fully uninstalled (`graphify-out/`, `.graphifyignore`, rules, and skills removed).
  - Code-based memory in `.agentMemory/` initialized and synchronized.
  - MCP Memory Server (`@modelcontextprotocol/server-memory`) registered with entities and relations in the knowledge graph.
  - Strict protocol active: Memory checked first on every prompt, updated after every `proceed`.

- **Single Customer Synchronization Architecture (Implemented 2026-10-26)**:
  - **Requirement**: Scoped sync triggered exclusively when a customer is selected, updating only that specific customer's data without global footprint.
  - **Backend Endpoints (`SalesInvoiceController.cs` & `EfSalesInvoiceRepository.cs`)**:
    - `GET api/SalesInvoice/customer/{customerNo}/live-credit`: Returns live balance, credit limit, control status (`BPCUSTOMER`, `GACCDUDATE`).
    - `GET api/SalesInvoice/customer/{customerNo}`: Returns master customer profile (Terms, Tax Rule, Status).
    - `GET api/SalesInvoice/open-invoices?customerno={code}&daysCutoff=90`: Bypasses site-level snapshot cache when `customerno` is provided, live querying Sage X3.
    - `GET api/SalesInvoice/x3-history?customercode={code}&months=6`: Bypasses site-level snapshot cache when `customercode` is provided, live querying 6-month historical lines.
  - **Mobile Database Layer (`LocalDatabaseHelper.dart`)**:
    - `updateCustomerProfileAndFinancials(...)`: Updates `outstandingBalance`, `creditLimit`, `statusFlag`, `paymentTerm`, `taxRule`, `name` in `tbl_si_customers`.
    - `refreshOpenInvoicesForCustomer(...)`: Scoped deletion for this customer only, reconciles with pending unsynced payments (`tbl_si_open_invoice_payments`), atomic insert.
    - `refreshX3HistoryForCustomer(...)`: Scoped deletion for this customer only, chunked batch insert into `tbl_x3_history_header` and `tbl_x3_history_lines`.
  - **Mobile Sync Repository (`SalesInvoiceSyncRepository.dart`)**:
    - `syncSingleCustomerData({required String customerCode, String? siteCode})`: Offline pre-flight session check $\rightarrow$ parallel `Future.wait` fetch $\rightarrow$ atomic local database ingestion $\rightarrow$ returns `CustomerSyncResult`.
  - **UI Representation (Active Only When Customer Selected)**:
    - **Customer Hub Screen (`CustomerHubScreen`)**:
      - Hero Card bottom interactive strip (`Sync This Customer`, live progress indicator, and live feedback).
      - Module AppBar action button (`Icons.cloud_sync_rounded`).
      - Pull-to-refresh (`RefreshIndicator.onRefresh` hooks into customer sync).
    - **Open Invoices Screen (`OpenInvoicesScreen`)**: Scoped AppBar sync icon rendered when filtered/locked to a customer.
    - **Transaction History Screen (`TransactionHistoryScreen`)**: Scoped AppBar sync icon rendered when filtered/locked to a customer.
    - **Customer Directory List (`CustomerSelectionScreen`)**: Quick sync button removed from unselected customer cards so sync is strictly accessible only after a customer is selected.

- **Universal Asynchronous Sync & Global Touch-Barrier Overlay Architecture (Implemented 2026-10-28)**:
  - **Core Problem Solved**:
    - Previously, single customer sync inside `CustomerHubScreen`, `OpenInvoicesScreen`, and `TransactionHistoryScreen` ran in unblocked local futures with floating SnackBars. Users could freely tap transactions, invoice reversals, payment settlement, or back navigation while local tables (`tbl_si_open_invoices`, `tbl_x3_history_*`) were truncated and re-populated, exposing operations to race conditions and dirty reads.
  - **Universal Root-Mounted Lock (`main.dart` & `MaterialApp.builder`)**:
    - `SalesInvoiceSyncOverlay` and `SyncOverlay` are mounted globally at the application root inside `MaterialApp.router`'s `builder` `Stack`.
    - Automatically wraps ALL routes, modal sheets, and child navigators with zero screen-level boilerplate.
    - Eliminates redundant local overlay instantiations across `HomeScreen`, `CustomerSelectionScreen`, and `SelectTransactionScreen` (unbalanced delimiter artifacts from local Stack removals resolved).
  - **Touch Barrier & Navigation Guard (`SalesInvoiceSyncOverlay.dart`)**:
    - Frosted glass backdrop with full touch interception via `Positioned.fill` + `BackdropFilter` (10px Gaussian blur) + dark/light responsive translucent scrim.
    - `PopScope(canPop: !isSyncing)` blocks Android hardware and gesture back navigation until synchronization concludes.
    - Minimalist glass HUD card displays live sync states (`Syncing Customer`, `Synchronizing Mobile Sales Data`).
    - Success presentation: displays customer name, formatted live balance (`Rs #,##0.00`), open invoice count, and X3 history invoice count. Auto-dismisses cleanly after 3.2s via `ResetSalesInvoiceSyncRequested`.
    - Error presentation: captures offline blocking or network timeouts with detailed copyable diagnostics and manual dismiss.
  - **BLoC State Orchestration (`SalesInvoiceSyncBloc.dart`, events, and states)**:
    - Injected `SalesInvoiceSyncRepository` into `SalesInvoiceSyncBloc`.
    - Added `StartSingleCustomerSyncRequested(customerCode, customerName, siteCode)`.
    - Added states: `SalesInvoiceCustomerSyncInProgress`, `SalesInvoiceCustomerSyncSuccess(result, customerName)`, `SalesInvoiceCustomerSyncFailure(error)`.
    - Fully asynchronous background execution preventing UI thread freezing.
  - **Reactive Screen Reloading (`CustomerHubScreen`, `OpenInvoicesScreen`, `TransactionHistoryScreen`)**:
    - Wrapped screens in `BlocListener<SalesInvoiceSyncBloc, SalesInvoiceSyncState>`.
    - Upon `SalesInvoiceCustomerSyncSuccess`, triggers reactive reload:
      - `CustomerHubScreen`: calls `_loadFinancials()` to immediately refresh live balance, terms, credit limit, and hold status.
      - `OpenInvoicesScreen`: calls `_loadData()` to reload open invoices and reconciliation status.
      - `TransactionHistoryScreen`: calls `_loadTransactions()` to refresh X3 line history.
    - Sync trigger buttons (card strip and AppBar icons) dynamically reflect BLoC sync state with spinning indicators and disabled states while sync is in progress.

## Current Status (Updated: 2026-10-27)
- **Stock Status Architecture & Return Quarantine (Critical Risk Guard Implemented)**:
  - **Global Stock Status Parameter (`StockStatus` enum & codes)**:
    - `A`: Approved / Prime Sellable stock (Strictly available for sales invoices).
    - `Q`: Returned Goods (Quarantined customer returns awaiting inspection).
    - `R`: Issue in Stock (Damaged, defective, or rejected inventory).
  - **Critical Risk Guard (Preventing Re-Selling Customer Returns)**:
    - `sales_invoice_product_repository.dart`: `getSalesInvoiceProducts`, `getProductByItemCode`, and `getSalesInvoiceItemStockDetails` enforce `WHERE (S.stockStatus = 'A' OR S.stockStatus IS NULL OR S.stockStatus = '')` by default, making returned/quarantined goods completely invisible in product catalog and lot selection during sales order/invoicing.
    - `add_item_detail_screen.dart`: FOC item queries and specific lot stock lookups restricted strictly to `stockStatus = 'A'`.
    - `lot_selection_screen.dart`: Lots loaded strictly for `stockStatus = 'A'`.
    - `payment_processing_screen.dart`: Checkout stock deductions target `stockStatus = 'A'` exclusively.
    - `credit_note_service.dart`: Physical returns (`stockTransaction == 1`) quarantine items into `stockStatus = 'Q'` (or `'R'` if reason is `DEF`/`DAM`/`REJ`), permanently preventing returns from merging into sellable stock.
    - `_applyUnsyncedLedgerToStock`: Deducts invoices from `stockStatus = 'A'` and adds back credit notes to `stockStatus = 'Q'`.
  - **Database Migration v96 (`LocalDatabaseHelper.dart`)**:
    - Bumped database version to `96`.
    - `tbl_si_item_stock_details` upgraded with column `stockStatus TEXT DEFAULT 'A'`.
    - Composite primary key migrated to `PRIMARY KEY (itemCode, lotNumber, location, warehouse, stockStatus)` allowing simultaneous approved and returned lots for the same item.
  - **Backend Sage X3 Integration (`SalesInvoiceItemStockDto.cs` & `EfSalesInvoiceRepository.cs`)**:
    - Added `StockStatus` property to `SalesInvoiceItemStockDto`.
    - `GetItemStockDetailsAsync`: Selects `LTRIM(RTRIM(COALESCE(stk.STA_0, 'A'))) AS StockStatus`, queries `stk.STA_0 IN ('A', 'Q', 'R')`, and groups by `stk.STA_0`.
    - `GetProductsAsync`: Preserved strictly `stk.STA_0 = 'A'` for commercial catalog.
  - **Separated Stock Preview Report (`SalesReportPdfService.dart` & `SalesReportsScreen.dart`)**:
    - `SalesReportsScreen`: Fetches stock with `stockStatus: 'ALL'`.
    - `SalesReportPdfService.generateStockPreviewPdf`: Clearly partitions report into 3 distinct visual sections:
      1. `[A] APPROVED / SELLABLE STOCK` (with SKU count and subtotal units).
      2. `[Q] CUSTOMER RETURNS (QUARANTINE)` (with SKU count and subtotal units, or zero-state indicator).
      3. `[R] ISSUE IN STOCK (DAMAGED / DEFECTIVE)` (with SKU count and subtotal units, or zero-state indicator).
      4. **Physical Stock Reconciliation Block**: Detailed breakdown of Approved, Returned, and Damaged units, culminating in **TOTAL PHYSICAL STOCK** and unique SKU counts.

- **Direct 3-Tile Sales Architecture & Granular Permissions**:
  - **Permission Restructuring**:
    - Renamed "Sales Invoice" permission to "Salesman" (`logistics.salesman`) while preserving legacy `logistics.sales_invoice` fallback.
    - Added dedicated permission for "Reports" (`logistics.reports`).
    - Added dedicated permission for "OTP Generation" (`logistics.otp_generation`).
    - Seeded in `DbInitializer.cs` and managed in User Management (`user_management_screen.dart`).
  - **Clean 3-Tile Home Screen Architecture**:
    - **Tile 1 — Sales**: Guarded by `logistics.salesman.read` (or legacy `logistics.sales_invoice.read`). Reverted to the clean, original direct navigation to [CustomerSelectionScreen](file:///d:/enterprise_auth_system/frontend/lib/features/logistics/presentation/pages/sales_invoice/customer_selection_screen.dart) after checking active sales reps.
    - **Tile 2 — Sales Reports**: Guarded by `logistics.reports.read`. Directly opens [SalesReportsScreen](file:///d:/enterprise_auth_system/frontend/lib/features/logistics/presentation/pages/sales_invoice/sales_reports_screen.dart) for Invoice Summary, Stock Preview, and EOD Cash Collection PDF reports.
    - **Tile 3 — OTP Generation**: Guarded by `logistics.otp_generation.read`. Directly opens [OtpGenerationScreen](file:///d:/enterprise_auth_system/frontend/lib/features/logistics/presentation/pages/sales_invoice/otp_generation_screen.dart) for generating time-based supervisor override PINs.
  - **Codebase Cleanliness & Decoupling**:
    - Deleted intermediate `sales_operations_screen.dart` completely.
    - Removed `Sales Operations` hub tile from Home Screen, keeping user navigation lean and direct.

- **Industrial & Futureproof End of Day (EOD) Reconciliation Report (Implemented 2026-10-27)**:
  - **Data Models (`eod_report_model.dart`)**:
    - `EodInvoiceItem`: Itemized invoice model capturing `invoiceId`, `customerCode`, `customerName`, `grandTotal`, `paymentTerm`, `tenderSummary`, `cashAmount`, `chequeAmount`, `digitalAmount`, `creditAmount`, and `isCredit`.
    - `EodOpenInvoiceCollectionItem`: Model for payments collected on the road against open invoices (`tbl_si_open_invoice_payments`), capturing `paymentId`, `documentNo`, `customerNo`, `customerName`, `amount`, `paymentMethod`, `bankName`, `chequeNumber`, `qrTransactionRef`, and sync status.
    - `EodChequeDetail`: Itemized cheque model for depot deposit slip tracking (`chequeNumber`, `bankName`, `customerName`, `source`, `amount`, `date`).
    - Upgraded `EodReportModel`: Integrated breakdown lists (`cashInvoices`, `creditInvoices`, `openInvoiceCollections`, `chequeList`) and computed physical cash-in-hand (`netPhysicalCashInHand`), cheque total, digital remittances, and gross turnovers.
  - **Repository Layer (`TransactionHistoryRepository.dart`)**:
    - Upgraded `getEodReportData(date)`:
      - Classifies today's invoices into `cashInvoices` (spot cash, cheque, juice settlement) and `creditInvoices` (unsettled on terms).
      - Queries `tbl_si_open_invoice_payments` joined with `tbl_si_customers` to capture all debt recoveries.
      - Queries `tbl_si_credit_note_refunds` to deduct cash paid out for returns from physical cash in hand.
      - Aggregates multi-tender receipts across all payment channels.
  - **Industrial PDF Presentation (`SalesReportPdfService.dart`)**:
    - Re-architected `generateEodReportPdf` into 8 modular, high-contrast sections on standard continuous thermal roll format:
      1. **Header & Metadata**: INNODIS LTD, Shift closing date/time, Rep, Register ID.
      2. **Turnover Summary**: Gross sales, credit notes, net sales, VAT, and total invoiced.
      3. **Section 1: Cash Invoices**: Itemized table (`Inv#`, `Customer`, `Tender`, `Amount`) with subtotal.
      4. **Section 2: Credit Invoices**: Itemized table (`Inv#`, `Customer`, `Terms`, `Amount`) with subtotal.
      5. **Section 3: Open Invoice Collections**: Itemized table (`Doc#`, `Customer`, `Method & Ref`, `Amount`) with subtotal.
      6. **Section 4: Returns & Cancelled Receipts**: Detailed return reversals.
      7. **Section 5: Cashier & Safe Reconciliation Box**: Framed audit box calculating net physical cash to deposit, itemized physical cheques list, digital remittances, credit extended, and grand funds collected.
      8. **Section 6 & 7: VAT Breakdown & Combined Payment Summaries**.
      9. **Section 8: Audit Sign-off**: Dual signatures for Sales Representative and Depot Cashier/Supervisor.
    - **MultiPage Assertion & Unicode Fix (2026-10-27)**:
      - Resolved `multi_page.dart:252` assertion error (`pageFormat.height < double.infinity`) by utilizing finite standard height `PdfPageFormat.a4.height` in `generateEodReportPdf`.
      - Resolved `Helvetica has no Unicode support` font warnings by deploying comprehensive diacritic transliteration (`é, è, à, ç` $\rightarrow$ `e, a, c`, smart quotes/dashes $\rightarrow$ ASCII equivalents) and stripping non-ASCII characters in `_cleanText`.
      - Wrapped all dynamic report fields across all tables, headers, and footer sign-offs in `_cleanText` to guarantee 100% 7-bit ASCII compatibility for PDF rastering.
      - Addressed hot reload raster race condition in `PdfPreviewRaster` by ensuring pristine, instant rendering.

- **Centralized Currency Standardization & Universal Right-Alignment (Implemented 2026-10-27)**:
  - **Core Utility (`CurrencyFormatter.dart`)**:
    - Centralized under `lib/core/utils/currency_formatter.dart`.
    - Standard currency symbol: strictly `Rs ` (no `'RS '`, no `'MUR'`).
    - Format pattern: `#,##0.00` (thousands/millions commas, strictly 2 decimal places).
    - Methods: `format(amount)`, `formatNumber(amount)`, `formatDiscount(amount)`, and `currencyFormat`.
  - **Screen-by-Screen Standardization (13 Screens & Widgets Updated)**:
    - `CustomerSelectionScreen`: `creditLimitStr` and `outstandingStr` use `CurrencyFormatter.format`; OUTSTANDING column right-aligned (`CrossAxisAlignment.end`, `textAlign: TextAlign.right`).
    - `CustomerHubScreen`: Replaced `'RS '` formatter with `CurrencyFormatter.currencyFormat` and `CurrencyFormatter.format(amount)`.
    - `AddItemDetailScreen`: Removed double space `'RS  '`; discount and VAT use `formatDiscount` and explicit signed format; form inputs right-aligned with `alignRight: true`; Base Price input upgraded with a balanced single-row tile placing label on the left and a dedicated interactive monetary pill on the right (`Rs ` + number contiguous with zero void gap, right-aligned, locked when `_isReturnMode`); bottom sticky action bar mathematically aligned with both `QUANTITY` and `ITEM TOTAL` headers sharing top baseline (y=0) and both stepper and item total sharing matching 48px heights with total vertically centered.
    - `OrderSummaryScreen`: Replaced custom patterns; `_buildCalcRow` wraps labels in `Expanded` and right-aligns amounts; Reversal Total and Grand Total right-aligned.
    - `PaymentProcessingScreen`: Credit limit snackbar uses `CurrencyFormatter.format`; payment methods display right-aligned amounts; payment amount `_amountController` `TextField` right-aligned (`textAlign: TextAlign.right`); sticky footer labels wrapped in `Expanded` with amounts right-aligned.
    - `OpenInvoicesScreen`: Selection bar, collection item cards, and receipt details modal labels wrapped in `Expanded` and amounts right-aligned.
    - `OpenInvoiceCard`: Replaced `'RS '` in cards and history modals; Original Due, Already Collected, and Remaining Balance right-aligned; allocation helper text shows `Maximum: Rs ...` with prefix `Rs `.
    - `SalesOrdersListScreen`: Total order amounts formatted via `CurrencyFormatter.format` with `Expanded` label and right-alignment.
    - `SalesOrderDetailsScreen`: Subtitle unit price formatted with `Rs `, trailing line total right-aligned, summary rows wrapped in `Expanded` and right-aligned.
    - `TransactionHistoryScreen`: Formatted via `CurrencyFormatter.currencyFormat` and right-aligned trailing amounts.
    - `InvoiceItemReversalScreen`: Bottom bar reversal total wrapped in `Expanded` and right-aligned.
    - `AmountOnlyCreditNoteScreen`: Available balance and checkbox secondary invoice amounts right-aligned.
    - `InvoicePreviewScreen`: Summary card rows (Subtotal, Discount, VAT, Credited, Refund/Net Due) wrapped in `Expanded` and right-aligned.
  - **PDF Services Standardization (4 Services Updated)**:
    - `SalesInvoicePdfService`: Unit price prefixed with `Rs ` (`Rs #,##0.00`), summary value box widened to `85` points, right-aligned with `pw.TextAlign.right`.
    - `CreditNotePdfService`: Returned unit price prefixed with `Rs `, Total Refund right-aligned and prefixed with `Rs `.
    - `CashCollectionPdfService`: Replaced legacy uppercase `'RS '` with `'Rs '` across all sections.
    - `SalesReportPdfService`: Grand Revenue header and total formatted as `GRAND REVENUE` and `'Rs #,##0.00'`; all EOD tables (Cash Invoices, Credit Invoices, Collections, Returns, VAT, Payment Methods) enforce matching `headerAlignments` to ensure headers and figures are right-aligned; reconciliation tallies and sub-rows use `pw.Expanded` labels and `textAlign: pw.TextAlign.right`.

## Verified Environment:
- **Device**: Infinix X6528 (`Infinix 2`), Android
- **Backend**: ASP.NET Core API on `192.168.100.156:5004` / `192.168.1.57:5004`
- **ERP**: Sage X3 ERP (`INLDRYRUN` schema)

