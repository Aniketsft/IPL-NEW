# Single Customer Synchronization Pattern

## Context & Purpose
In mobile sales and van distribution workflows, performing a full global synchronization (which downloads products, stock levels, all price lists, and all customers) is expensive and slow. Drivers and sales reps frequently need to refresh data for **only one specific customer** at their physical store location (e.g. to see if a recent office payment has cleared, check live credit status, or load historical X3 invoice lines for returns).

## Architecture & Flow

```mermaid
graph TD
    A[User Selects Customer] --> B[Customer Hub Screen]
    B --> C[Tap 'Sync This Customer' / Pull-to-Refresh]
    C --> D[SalesInvoiceSyncRepository.syncSingleCustomerData]
    D --> E[Parallel API Fetch]
    E -->|1| F1[GET api/SalesInvoice/customer/{code}/live-credit]
    E -->|2| F2[GET api/SalesInvoice/customer/{code}]
    E -->|3| F3[GET api/SalesInvoice/open-invoices?customerno={code}]
    E -->|4| F4[GET api/SalesInvoice/x3-history?customercode={code}]
    F1 & F2 & F3 & F4 --> G[LocalDatabaseHelper Scoped Ingestion]
    G --> H[Update tbl_si_customers Profile & Balance]
    G --> I[Wipe & Replace tbl_si_open_invoices for this customer, reconciling pending unsynced payments]
    G --> J[Wipe & Replace tbl_x3_history headers & lines for this customer]
    H & I & J --> K[Refresh UI Instantly]
```

## Key Rules & Guarantees
1. **Trigger Condition**: Scoped sync is **only available once a customer is selected** (inside `CustomerHubScreen`, customer-filtered `OpenInvoicesScreen`, or customer-filtered `TransactionHistoryScreen`). Unselected directory lists do not expose customer-scoped sync.
2. **ERP Live Bypass**: When `customerno` or `customercode` is passed to the ASP.NET Core endpoints, the pre-compressed site-level snapshot cache is bypassed to query live Sage X3 data (`BPCUSTOMER`, `BPARTNER`, `GACCDUDATE`, `SINVOICE`, `SINVOICEV`).
3. **Local Reconciliation Protection**: When replacing open invoices, any pending offline collections (`tbl_si_open_invoice_payments` where `isSynced = 0`) are factored into the remaining balance so offline receipts are not overwritten before they sync to the server.
4. **Deadlock-Free Transactions**: Local SQLite updates run within isolated write transactions on `InnodisApp.db`.
