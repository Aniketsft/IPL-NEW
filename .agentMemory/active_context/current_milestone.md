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

## Verified Environment:
- **Device**: Infinix X6528 (`Infinix 2`), Android
- **Backend**: ASP.NET Core API on `192.168.1.57:5004`
- **ERP**: Sage X3 ERP (`INLDRYRUN` schema)
