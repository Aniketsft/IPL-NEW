# Customer-Centric Sales Workflow & UI Refactor Implementation Plan

> **For Claude / Antigravity:** REQUIRED SUB-SKILL: Use `writing-plans` and `executing-plans` to implement this plan task-by-task.

**Goal:** Refactor the mobile Sales navigation and screen flow so that selecting a Customer is the primary entry point (`Sales -> Select Customer`), transitioning into a Customer Hub where all sub-operations (Transactions, Open Invoices, Sales Orders, History) are strictly isolated and pre-filtered for the selected customer only.

**Architecture:** Introduce a dedicated `CustomerHubScreen` acting as the operational dashboard for a selected customer. Modify `CustomerSelectionScreen` to navigate into `CustomerHubScreen`, and update all downstream modules (`OpenInvoicesScreen`, `TransactionHistoryScreen`, `SalesOrdersListScreen`, `AmountOnlyCreditNoteScreen`, `OrderSummaryScreen`) to accept and lock customer parameters, ensuring zero cross-customer data leakage.

**Tech Stack:** Flutter 3.x, Flutter Bloc (`SalesInvoiceBloc`), SQLite (`LocalDatabaseHelper`), GoRouter & Navigator.

---

## 1. Flow Comparison

### Current Flow (Disjointed & Global)
```
Home Screen
  └─► Sales Menu ("Sales")
        ├─► Transaction -> Select Transaction Type (Invoice, Credit Note, Return)
        │     └─► Customer Selection (picks customer)
        │           └─► Cart / Order Summary
        ├─► Open Invoice (Lists all open invoices across the entire site!)
        ├─► Reports
        ├─► Sales Order (Lists all sales orders across the entire site)
        └─► Sales Reps dialog
```

### New Customer-Centric Flow
```
Home Screen / Bottom Nav / Drawer
  └─► Sales ("Sales")
        │
        └─► Customer Selection Screen ("Sales - Select Customer")
              │ • Filter & Search by Name / Code / Status / Terms
              │ • Shows Credit Limit & Outstanding Balance
              │ • Sales Rep / Sync action in AppBar
              │
              └─► Customer Hub Screen ("Customer Dashboard")
                    │
                    ├── [Customer Profile Card: Code, Name, Site, Credit Limit, Outstanding, Switch Customer]
                    │
                    ├──► [Action 1: Transactions]
                    │       ├── New Invoice (seeds customer into SalesInvoiceBloc -> opens Catalog/Cart)
                    │       ├── New Credit Note (Amount-Only or Goods-Return for this customer)
                    │       ├── New Customer Return (seeds customer -> opens Catalog/Cart)
                    │       └── Transaction History (strictly filtered to this customer)
                    │
                    ├──► [Action 2: Open Invoices & Credit Notes]
                    │       ├── Displays count & remaining balance for this customer
                    │       └── Open Invoices Screen (locked strictly to this customer; collect payments)
                    │
                    ├──► [Action 3: Sales Orders]
                    │       ├── Displays open sales orders for this customer
                    │       └── Sales Orders List (strictly filtered to this customer -> Convert to Invoice)
                    │
                    └──► [Action 4: Customer Summary & Statement]
                            └── Visual breakdown of Credit vs. Debt & payment terms
```

---

## 2. Granular Task Breakdown

### Task 1: Create `CustomerHubScreen` (`customer_hub_screen.dart`)
**Files:**
- Create: [customer_hub_screen.dart](file:///d:/enterprise_auth_system/frontend/lib/features/logistics/presentation/pages/sales_invoice/customer_hub_screen.dart)
- Reference: [industrial_module_layout.dart](file:///d:/enterprise_auth_system/frontend/lib/core/widgets/industrial_module_layout.dart)
- Reference: [local_database_helper.dart](file:///d:/enterprise_auth_system/frontend/lib/features/logistics/data/local/local_database_helper.dart)

**Details:**
1. Accepts `required Map<String, dynamic> customer`.
2. Header:
   - Sticky industrial card showing:
     - Customer Name (`BPCNAM_0`), Customer Code (`BPCNUM_0`)
     - Assigned Site, Payment Term (`PTE_0`), Status (`Check` / `No Check` / `Hold`)
     - Financial indicators: Credit Limit (`OSTAUZ_0`), Current Outstanding (`BPCCDTISR_0` or local balance).
     - "Switch Customer" button to pop back to Customer Selection.
3. Summary KPI Badges:
   - Queries `LocalDatabaseHelper.instance.getOpenInvoices(customerNo: customer['code'])` to show:
     - Open Invoice count and total remaining LCY.
   - Queries `SISalesOrderService.getSalesOrders()` to show pending Sales Orders count for this customer.
4. Action Cards:
   - **Transaction Processing**:
     - *New Invoice*: Clears cart, fires `InitializeTransaction(transactionType: 'INVOICE')`, fires `SetCustomer(customer)`, navigates to `AppRoutes.orderSummary`.
     - *New Credit Note*: Modal prompt for "Amount-Only Credit Note" (`AmountOnlyCreditNoteScreen(initialCustomerCode: customer['code'])`) or "Reversal Credit Note".
     - *Customer Return*: Clears cart, fires `InitializeTransaction(transactionType: 'RETURN')`, fires `SetCustomer(customer)`, navigates to `AppRoutes.orderSummary`.
     - *Transaction History*: Navigates to `TransactionHistoryScreen(preselectedCustomerCode: customer['code'], preselectedCustomerName: customer['name'], isCustomerLocked: true)`.
   - **Open Invoices**:
     - Navigates to `OpenInvoicesScreen(preselectedCustomerNo: customer['code'], preselectedCustomerName: customer['name'], isCustomerLocked: true)`.
   - **Sales Orders**:
     - Navigates to `SalesOrdersListScreen(customerNo: customer['code'])`.

---

### Task 2: Update `CustomerSelectionScreen` Navigation (`customer_selection_screen.dart`)
**Files:**
- Modify: [customer_selection_screen.dart](file:///d:/enterprise_auth_system/frontend/lib/features/logistics/presentation/pages/sales_invoice/customer_selection_screen.dart#L309-L315)

**Details:**
1. When tapping a customer card, instead of pushing `AppRoutes.orderSummary`, navigate to `CustomerHubScreen(customer: customer)`:
   ```dart
   Navigator.push(
     context,
     MaterialPageRoute(
       builder: (_) => CustomerHubScreen(customer: customer),
     ),
   );
   ```
2. Add an optional `bool isPickerOnly` flag so if an external caller strictly wants to pick and return a customer (e.g. for a custom dialog), it can pop with the result, while default behavior opens the `CustomerHubScreen`.
3. Add Sync button and Sales Rep button in the app bar for convenient field access while in Customer Selection.

---

### Task 3: Lock `OpenInvoicesScreen` to Selected Customer (`open_invoices_screen.dart`)
**Files:**
- Modify: [open_invoices_screen.dart](file:///d:/enterprise_auth_system/frontend/lib/features/logistics/presentation/pages/sales_invoice/open_invoices_screen.dart)

**Details:**
1. Add constructor properties:
   ```dart
   final String? preselectedCustomerNo;
   final String? preselectedCustomerName;
   final bool isCustomerLocked;
   ```
2. In `initState()`, if `preselectedCustomerNo` is provided:
   - Set `_selectedCustomerNo = widget.preselectedCustomerNo`.
   - Set `_selectedCustomerName = widget.preselectedCustomerName`.
3. When `isCustomerLocked` is true:
   - Hide or disable customer selection filter sheets (prevent picking other customers).
   - Show a persistent customer header chip indicating data is locked to the selected customer.
4. In `_loadData()`:
   - Query `LocalDatabaseHelper.instance.getOpenInvoices(siteCode: siteCode, customerNo: _selectedCustomerNo)`.
   - Only invoices and credit notes for this specific customer are retrieved and displayed.

---

### Task 4: Lock `TransactionHistoryScreen` to Selected Customer (`transaction_history_screen.dart`)
**Files:**
- Modify: [transaction_history_screen.dart](file:///d:/enterprise_auth_system/frontend/lib/features/logistics/presentation/pages/sales_invoice/transaction_history_screen.dart#L19-L26)

**Details:**
1. Add constructor properties:
   ```dart
   final String? preselectedCustomerCode;
   final String? preselectedCustomerName;
   final bool isCustomerLocked;
   ```
2. In `initState()`, initialize:
   ```dart
   _selectedCustomerCode = widget.preselectedCustomerCode;
   _selectedCustomerName = widget.preselectedCustomerName;
   ```
3. When `isCustomerLocked` is true:
   - Disable changing the customer in the filter modal.
   - Show badge: "Showing history for [Customer Name]".
4. `_loadTransactions()` automatically queries transactions where `customerCode == widget.preselectedCustomerCode`.

---

### Task 5: Lock `SalesOrdersListScreen` to Selected Customer (`sales_orders_list_screen.dart`)
**Files:**
- Modify: [sales_orders_list_screen.dart](file:///d:/enterprise_auth_system/frontend/lib/features/logistics/presentation/pages/sales_invoice/sales_orders_list_screen.dart#L14-L20)
- Reference: [si_sales_order_service.dart](file:///d:/enterprise_auth_system/frontend/lib/features/logistics/domain/services/si_sales_order_service.dart)

**Details:**
1. Add constructor property:
   ```dart
   final String? customerNo;
   ```
2. In `_loadOrders()`:
   - Filter `_orders` so only orders where `(order['customerCode'] ?? order['BPCORD_0']) == widget.customerNo` are listed.
   - Display customer-specific order list with order status and "Convert to Invoice" action.

---

### Task 6: Lock `AmountOnlyCreditNoteScreen` to Selected Customer (`amount_only_credit_note_screen.dart`)
**Files:**
- Modify: [amount_only_credit_note_screen.dart](file:///d:/enterprise_auth_system/frontend/lib/features/logistics/presentation/pages/sales_invoice/amount_only_credit_note_screen.dart)

**Details:**
1. When `initialCustomerCode` is provided, automatically query local customer record in `initState()` and populate `_selectedCustomer`.
2. Disable the "Change Customer" button if invoked from the Customer Hub, locking the credit note to that customer.

---

### Task 7: Update App Navigation & Home Screen Entry Point (`home_screen.dart` & `app_router.dart`)
**Files:**
- Modify: [home_screen.dart](file:///d:/enterprise_auth_system/frontend/lib/features/auth/presentation/pages/home_screen.dart#L356-L363)
- Modify: [app_router.dart](file:///d:/enterprise_auth_system/frontend/lib/core/navigation/app_router.dart#L70-L88)
- Modify: [sales_menu_screen.dart](file:///d:/enterprise_auth_system/frontend/lib/features/logistics/presentation/pages/sales_invoice/sales_menu_screen.dart)

**Details:**
1. In `home_screen.dart`:
   - When tapping "Sales", verify sales rep selection onboarding.
   - Route directly to `CustomerSelectionScreen()` (as `SalesCustomerSelectionScreen`).
2. In `app_router.dart`:
   - Point `AppRoutes.salesMenu` directly to `CustomerSelectionScreen()`, or maintain a streamlined route `AppRoutes.customerHub`.
3. In `sales_menu_screen.dart`:
   - Deprecate the old disconnected menu or repurpose it as a secondary tools drawer if needed, ensuring the primary path is always Customer Selection first.

---

## 3. Data Scoping & Security Matrix

| Feature | Data Source / Method | Scoping Parameter | Cross-Customer Access Allowed? |
| :--- | :--- | :--- | :--- |
| **Customer Selection** | `getPaginatedSalesInvoiceCustomers` | User's Site Code | No (only site customers) |
| **Customer Hub** | `customer` Map passed directly | Selected Customer | **Locked to Selected Customer** |
| **New Invoice / Cart** | `SalesInvoiceBloc.SetCustomer` | Selected Customer | **Locked to Selected Customer** |
| **Open Invoices** | `getOpenInvoices` | `customerNo: customer.code` | **Locked to Selected Customer** |
| **Credit Note (Amount)** | `CreditNoteService.createCreditNote` | `customerCode: customer.code` | **Locked to Selected Customer** |
| **Sales Orders** | `getSalesOrders` | `customerCode: customer.code` | **Locked to Selected Customer** |
| **Transaction History** | `TransactionHistoryRepository` | `customerCode: customer.code` | **Locked to Selected Customer** |

---

## 4. Testing & Verification Steps

1. **Customer Selection**:
   - Tap "Sales" on Home Screen -> Verify Customer Selection screen opens immediately.
   - Search for a customer (e.g. `BPC001`) -> verify cards show correct outstanding and credit limit.
2. **Customer Hub**:
   - Tap customer card -> Verify `CustomerHubScreen` opens with customer header card.
   - Verify KPI badge on "Open Invoices" matches the actual count of unpaid documents for that customer.
3. **Transaction Flow**:
   - Tap "Invoice" -> verify it goes straight to product catalog / cart without re-asking for customer.
   - Complete or back out -> returns cleanly to `CustomerHubScreen`.
4. **Open Invoice Isolation**:
   - Tap "Open Invoices" -> verify ONLY documents where `customerNo == selectedCustomer` appear.
   - Verify payment allocation and recording works seamlessly for this customer.
5. **History & Orders Isolation**:
   - Tap "Transaction History" -> verify only transactions for this customer appear.
   - Tap "Sales Orders" -> verify only sales orders for this customer appear.
6. **Switch Customer**:
   - Tap "Switch Customer" or back button -> verify it cleanly returns to customer list to pick another customer.
