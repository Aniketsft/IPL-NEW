# Implementation Plan: Refactor Sales UI into Customer-Centric Flow

**Document:** `refactor_sales_customer_centric_flow_plan.md`  
**Date:** October 12, 2026  
**Module:** Enterprise Sales & Logistics (`enterprise_auth_mobile`)  
**Target Architecture:** Offline-First Van Sales / Direct Store Delivery (DSD)  
**Status:** Approved Architecture with Production Hardening & Poka-Yoke Guards  

---

## 1. Executive Summary & Paradigm Shift

### 1.1 The Problem with the Legacy Flow
Previously, tapping **Sales** loaded a disconnected grid of general tiles (`Transaction`, `Open Invoice`, `Sales Order`, `Reports`, `Sales Reps`).  
This forced sales representatives into an anti-pattern:
- Searching and re-selecting the customer repeatedly across different screens.
- Open invoices were viewed globally across all customers, creating dangerous risks of allocating cash/cheque payments to the wrong debtor.
- No unified customer financial view (credit limit, outstanding balance, open orders) during the store visit.

### 1.2 The Customer-Centric Architecture
The flow is re-anchored so that **visiting a customer** is the central atom of field sales:

```mermaid
flowchart TD
    A[Home Screen: Tap 'Sales'] --> B{Sales Rep Selected?}
    B -- No & DB has Reps --> C[SalesRepSelectionDialog]
    C --> D[CustomerSelectionScreen: Route Dispatch]
    B -- Yes --> D
    
    subgraph Route Dispatch Bar
        D1[Truck Inventory on Van]
        D2[Daily Route EOD Report]
        D3[Data Sync & Last Sync Time]
        D4[Sales Rep Switcher]
    end
    D -.-> Route Dispatch Bar
    
    D -->|Tap Customer Card| E[CustomerHubScreen: Selected Customer]
    
    E --> F[New Transaction: Invoice / CN / Return]
    E --> G[Open Invoices: Settle Dues & Receipts]
    E --> H[Transaction History: Past Invoices & CNs]
    E --> I[Sales Orders: Convert Orders to Invoice]
    
    E -->|Finish Visit / Next Customer| D
    
    subgraph Customer Isolation & Safeguards
        F --> F1[OrderSummaryScreen: Pre-loaded Customer, Cart Invariant Guard]
        G --> G1[OpenInvoicesScreen: WHERE customerNo = ?, Live Real-time Balance]
        H --> H1[TransactionHistoryScreen: WHERE customerCode = ?]
        I --> I1[SalesOrdersListScreen: WHERE customerCode = ?]
    end
```

---

## 2. Production Hardening & Safeguard Architecture

### 2.1 Safeguard 1: Cart Invariant Guard (No Cross-Customer Cart Bleed)
* **The Vulnerability:** `SalesInvoiceBloc` maintains cart state. If a rep adds items for Customer A, exits back, and selects Customer B, line items with Customer A's price lists (`SPRICLIST`), taxes (`VACBPR`), and promotions will contaminate Customer B's order.
* **The Rule:** 
  1. When tapping `Switch Customer` or attempting to select another customer from `CustomerSelectionScreen`:
     - If `cartItems.isNotEmpty`, display a blocking modal dialog:
       > **"Active Draft in Progress"**  
       > *"You have an unsaved transaction with [N] items for [Customer Name]. Discard this draft to switch customers?"*  
       > `[Cancel]` `[Discard & Switch]`
  2. If confirmed, dispatch `ClearCart()` and `SetCustomer(newCustomer)`.

### 2.2 Safeguard 2: Real-Time Dynamic Ledger Balance
* **The Vulnerability:** The `outstandingBalance` in SQLite (`tableSalesInvoiceCustomers`) is static from the last Sage X3 sync. If a customer owes Rs 40,000 and pays Rs 25,000 cash in *Open Invoices*, reading the static column still shows Rs 40,000, falsely blocking new credit sales.
* **The Rule:** Compute the **Effective Real-Time Outstanding Balance** dynamically:
  $$\text{Effective Outstanding} = \text{Base Outstanding (Sage X3)} - \sum(\text{Local Unsynced Payments}) + \sum(\text{Local Unsynced Credit Invoices})$$
  $$\text{Available Credit} = \max(0, \text{Credit Limit} - \text{Effective Outstanding})$$
  - The Customer Hub listens for returns from sub-flows and re-queries local sums immediately upon resumption.

### 2.3 Safeguard 3: Customer `HOLD` Status (`BPCSTA = 3`) Policy
* **The Vulnerability:** Sage X3 rejects invoices synced for customers on hold. Reps should not be permitted to issue credit sales to blocked debtors.
* **The Rule:**
  - **Account Status Chip:** High-visibility amber/red chip with an alert banner: `CUSTOMER ON HOLD IN SAGE X3`.
  - **Open Invoices & Debt Collection:** **ENABLED** (Encourages collecting overdue balance to release the hold).
  - **Cash-Only Invoices & Returns:** **ENABLED** (Immediate full payment at checkout).
  - **Credit Invoices:** **BLOCKED**. Tapping Credit Invoice displays:
    > *"This customer is currently on HOLD in Sage X3. Credit transactions are restricted. You may only process Cash sales or collect Open Invoice dues."*

### 2.4 Safeguard 4: Route Dispatch Bar in `CustomerSelectionScreen`
* **The Vulnerability:** Global operations (checking overall truck stock, end-of-day cash bag reconciliation, delta sync) have no natural home if Sales jumps straight to a customer list.
* **The Rule:** `CustomerSelectionScreen` acts as the **Route Dispatch Dashboard**. The top AppBar and header include:
  1. **Truck Inventory Button:** Quick access to inventory on the van (`SalesInvoiceProductSelectionScreen` in stock inquiry mode).
  2. **Daily EOD Report Button:** View total collections (Cash, Cheque, Bank, QR) across all route stops.
  3. **Data Sync Button:** Manual delta sync trigger with last sync timestamp.
  4. **Sales Rep Switcher:** Shows active representative badge, tap to re-select if authorized.

### 2.5 Safeguard 5: Open Invoices Unified Horizon (Sage X3 + Local Unsynced Dues)
* **The Vulnerability:** If a rep creates a credit invoice at 10:00 AM, and the client decides to pay for it at 10:15 AM before the rep departs, the invoice would be missing from `OpenInvoicesScreen` if it only queries `tableSiOpenInvoices`.
* **The Rule:**
  - `getOpenInvoices` in SQLite queries:
    1. Open documents pulled from Sage X3 (`tableSiOpenInvoices` WHERE `customerNo = ?`).
    2. Plus unpaid credit invoices generated locally in the current session (`tableTransactions` WHERE `customerCode = ?` AND `status = 'Open'` / `paymentMethod = 'CREDIT'`).
  - Marked as paid instantly upon recording payment.

### 2.6 Safeguard 6: Resilient Navigation Stack & Post-Action Confirmation
* **The Vulnerability:** Deep navigation dumping reps back to the home screen after completing an invoice or payment, losing visit continuity.
* **The Rule:**
  - Standardize `Navigator.pop(context, true)` upon successful payment or transaction completion.
  - Returns directly to `CustomerHubScreen`.
  - Customer Hub triggers an immediate financial refresh, shows a green confirmation toast (`"Invoice CGDINV... confirmed. Outstanding balance updated."`), and presents receipt re-print options.
  - The rep taps **"Finish Visit / Next Customer"** to deliberately return to `CustomerSelectionScreen`.

---

## 3. UI/UX Specification: `CustomerHubScreen`

### 3.1 Customer Identity & Financial Health Hero Card
```
┌────────────────────────────────────────────────────────┐
│ [WIN001] WINNER'S BEL AIR                 [HOLD Badge] │
│ Contact: Mr. Rajen  •  Terms: 30 DAYS NET   [Switch ❯] │
├────────────────────────────────────────────────────────┤
│  CREDIT LIMIT        OUTSTANDING          AVAIL. CREDIT │
│  RS 150,000.00       RS 42,350.00         RS 107,650.00 │
│                      (Dynamic Real-Time)               │
└────────────────────────────────────────────────────────┘
```

### 3.2 Action Cards Grid (2x2 Layout)
1. **New Transaction** (`Icons.shopping_cart_checkout_rounded`)
   - Accent: Brand Orange
   - Subtitle: *Invoice, Credit Note, Customer Return*
   - Pre-binds customer; skips customer picker and navigates directly to `OrderSummaryScreen`.
2. **Open Invoices** (`Icons.receipt_long_rounded`)
   - Accent: Emerald Green
   - Subtitle: *Settle dues, Cash / Cheque / Bank / QR*
   - Live Badge: `3 Open Docs • RS 42,350.00`
   - Scoped strictly to `WHERE customerNo = @SelectedCustomer`.
3. **Transaction History** (`Icons.history_rounded`)
   - Accent: Indigo Blue
   - Subtitle: *Past invoices, reprints, line-item reversals*
   - Scoped strictly to `WHERE customerCode = @SelectedCustomer`.
4. **Sales Orders** (`Icons.list_alt_rounded`)
   - Accent: Purple
   - Subtitle: *Pending customer orders to convert*
   - Scoped strictly to `WHERE customerCode = @SelectedCustomer`.

---

## 4. Detailed Implementation Tasks

### Task 1: Create `CustomerHubScreen` (`customer_hub_screen.dart`)
- **File:** `frontend/lib/features/logistics/presentation/pages/sales_invoice/customer_hub_screen.dart` (New)
- **Implementation:**
  - Build stateful widget receiving `Map<String, dynamic> customer`.
  - Calculate real-time dynamic outstanding balance:
    ```dart
    final baseOutstanding = double.tryParse(widget.customer['outstandingBalance']?.toString() ?? '0') ?? 0.0;
    final unsyncedPayments = await LocalDatabaseHelper.instance.getUnsyncedPaymentsSum(customerCode);
    final unsyncedInvoices = await LocalDatabaseHelper.instance.getUnsyncedCreditInvoicesSum(customerCode);
    final effectiveOutstanding = baseOutstanding - unsyncedPayments + unsyncedInvoices;
    ```
  - Fetch open invoice count & remaining sum for badge display.
  - Implement **Cart Invariant Guard** on back/switch action.
  - Render Hero Card with status enforcement (`HOLD` alert banner).
  - Render 4 action tiles.

### Task 2: Refactor `CustomerSelectionScreen` as Route Dispatch Hub
- **File:** `frontend/lib/features/logistics/presentation/pages/sales_invoice/customer_selection_screen.dart`
- **Implementation:**
  - Add AppBar actions:
    - **Truck Stock Inquiry:** opens `SalesInvoiceProductSelectionScreen(siteCode: userSiteCode)`.
    - **Daily EOD Report:** opens `SalesReportsScreen`.
    - **Data Sync:** triggers `SalesInvoiceSyncBloc`.
    - **Sales Rep Profile:** opens `SalesRepSelectionDialog`.
  - On tap customer card:
    - Dispatch `SetCustomer(customer)` to `SalesInvoiceBloc`.
    - Navigate to `CustomerHubScreen(customer: customer)`.
  - Preserve `isPickerMode` flag for instances when opened strictly as an inline picker.

### Task 3: Scope `OpenInvoicesScreen` to Single Customer
- **File:** `frontend/lib/features/logistics/presentation/pages/sales_invoice/open_invoices_screen.dart`
- **Implementation:**
  - Add parameters:
    ```dart
    final String? initialCustomerNo;
    final String? initialCustomerName;
    final bool lockToCustomer;
    ```
  - If `lockToCustomer == true`:
    - Auto-initialize `_selectedCustomerNo = initialCustomerNo;` and `_selectedCustomerName = initialCustomerName;`.
    - Replace the customer search dropdown with a locked, read-only customer badge.
    - Query local database with `customerNo: _selectedCustomerNo`.
    - On payment completion, return `true` to `CustomerHubScreen`.

### Task 4: Scope `TransactionHistoryScreen` to Single Customer
- **File:** `frontend/lib/features/logistics/presentation/pages/sales_invoice/transaction_history_screen.dart`
- **Implementation:**
  - Add parameters:
    ```dart
    final String? initialCustomerCode;
    final String? initialCustomerName;
    final bool lockToCustomer;
    ```
  - If `lockToCustomer == true`:
    - Auto-initialize `_selectedCustomerCode = initialCustomerCode;`.
    - Hide or lock customer filter in `_buildFilterSheet`.
    - Query transactions with `customerCode: _selectedCustomerCode`.

### Task 5: Scope `SalesOrdersListScreen` & `SISalesOrderService`
- **Files:**
  - `frontend/lib/features/logistics/domain/services/si_sales_order_service.dart`
  - `frontend/lib/features/logistics/presentation/pages/sales_invoice/sales_orders_list_screen.dart`
- **Implementation:**
  - Update `SISalesOrderService.getSalesOrders({String? customerCode})` to query `WHERE customerCode = ?`.
  - Update `SalesOrdersListScreen` to accept `customerCode` and display only orders matching the active customer.
  - On converting an order, mark `status = 'Converted'` in SQLite to prevent duplicate conversions.

### Task 6: Wire Home Navigation & Routes
- **Files:**
  - `frontend/lib/features/auth/presentation/pages/home_screen.dart`
  - `frontend/lib/core/navigation/app_router.dart`
  - `frontend/lib/core/navigation/app_routes.dart`
- **Implementation:**
  - Add `AppRoutes.customerHub = '/customer-hub'`.
  - In `HomeScreen.dart`:
    - When user taps **Sales**, check sales rep selection session.
    - Navigate to `CustomerSelectionScreen`.

---

## 5. Verification & Testing Protocol

1. **Cart Bleed Prevention Test:**
   - Select Customer A ➡️ Add 3 items to cart ➡️ Tap "Switch Customer" ➡️ Verify confirmation prompt appears ➡️ Confirm discard ➡️ Select Customer B ➡️ Verify cart is completely empty and pricing list applies to Customer B.
2. **Dynamic Outstanding Balance Test:**
   - Note Customer A's outstanding balance: `Rs 50,000`.
   - Pay `Rs 15,000` in Open Invoices.
   - Return to Customer Hub ➡️ Verify displayed outstanding balance immediately updates to `Rs 35,000`.
3. **`HOLD` Status Enforcement Test:**
   - Select a customer with `statusFlag == '3'`.
   - Verify red alert banner displays.
   - Verify *Open Invoices* allows debt collection.
   - Verify *Credit Invoice* shows the block dialog.
4. **Data Isolation Integrity Test:**
   - Open *Open Invoices* ➡️ Verify 0 documents belonging to other customers appear.
   - Open *Transaction History* ➡️ Verify only past documents for this customer appear.
   - Open *Sales Orders* ➡️ Verify only orders for this customer appear.
5. **Route Dispatch Test:**
   - In `CustomerSelectionScreen`, tap Truck Stock ➡️ Verify truck inventory displays.
   - Tap EOD Report ➡️ Verify route total collections display.
   - Tap Sync ➡️ Verify delta sync executes without errors.
