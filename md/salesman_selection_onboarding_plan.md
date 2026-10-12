# Implementation & Architecture Challenge Plan: Salesman Selection Onboarding Workflow

**Document:** `salesman_selection_onboarding_plan.md`  
**Date:** October 12, 2026  
**Module:** Logistics & Field Sales Mobile (`enterprise_auth_mobile`)  
**Target:** [home_screen.dart](file:///d:/enterprise_auth_system/frontend/lib/features/auth/presentation/pages/home_screen.dart), [sales_rep_selection_dialog.dart](file:///d:/enterprise_auth_system/frontend/lib/features/logistics/presentation/widgets/sales_rep_selection_dialog.dart), [local_database_helper.dart](file:///d:/enterprise_auth_system/frontend/lib/features/logistics/data/local/local_database_helper.dart)

---

## 1. Executive Summary & Problem Analysis

### 1.1 The Root Cause (The "Deadlock Modal")
When a field representative logs in on a new device, after clearing app storage, or following a fresh APK installation:
1. `HomeScreen.initState` schedules `_checkAndPromptSalesRepSelection()` via `addPostFrameCallback`.
2. `_checkAndPromptSalesRepSelection()` notes that `_selectedSalesReps.isEmpty == true` and `isNewLoginPrompt == true`.
3. It immediately invokes `SalesRepSelectionDialog.show(canDismiss: false)`.
4. `SalesRepSelectionDialog._loadData()` reads strictly from local SQLite table `tbl_sales_reps`.
5. Because **no initial data sync has occurred yet**, `tbl_sales_reps` has **0 records**.
6. The modal renders:
   - Header: *"Sales Representative - Select one or multiple reps for transactions"*
   - Body: *"No sales representatives found."*
   - Bottom Action: *"SELECT AT LEAST ONE REP"* (Disabled button `onPressed: null`).
   - Dismissible: `canDismiss = false` (barrier touches disabled, Android system back blocked by `PopScope`).
7. **User Impact**: The user is permanently stuck on a deadlocked black overlay modal. They cannot reach the "Data Sync" button on the Home dashboard to download the data needed to unblock themselves.

---

## 2. Challenging the Workflow (Critical Flaw & Edge Case Analysis)

To ensure an enterprise-grade architecture, we challenge the user's workflow across 5 key dimensions:

### Challenge 1: What signals that the app is in "Initial Startup / Zero Data" mode?
- **Flawed approach**: Using a boolean flag in `SharedPreferences` (`isFirstTimeLaunch`).
  - *Why it fails*: If SQLite is wiped, if database version bumps recreate tables, or if a sync is interrupted midway, the flag might say `false` while the database actually contains 0 sales reps.
- **Robust approach**: Check SQLite table count `SELECT COUNT(*) FROM tbl_sales_reps`.
  - If `count == 0`, prompting the user to select from an empty list is *always mathematically meaningless and harmful*. The app must dynamically suppress the modal whenever `tbl_sales_reps` count is 0.

---

### Challenge 2: Modal Collisions & UI Layering (Z-Index / Stack Clashes)
- **The Pitfall**:
  - The user taps "Data Sync".
  - The `SalesInvoiceSyncOverlay` renders a full-screen semi-transparent modal with progress indicators.
  - When sync completes, `SalesInvoiceSyncSuccess` is emitted.
  - If `HomeScreen` immediately calls `showDialog(SalesRepSelectionDialog)` while `SalesInvoiceSyncOverlay` is still displaying its summary and awaiting the user to tap "DISMISS", two overlays collide!
  - The dialog opens *underneath* or *over* the sync overlay, leading to gesture traps and bad UX.
- **Resolution**:
  - The sales rep prompt must only trigger:
    1. **After** the sync overlay is dismissed (e.g. when state transitions back to `SalesInvoiceSyncInitial` after success), OR
    2. Directly within the sync completion callback once the user acknowledges the sync summary.

---

### Challenge 3: What if Initial Sync Completes, but 0 Reps were Returned from ERP?
- **The Edge Case**:
  - The user performs sync, but their assigned Sage X3 site has no reps configured in `GACCDUDATE` / `BPCUSTOMER` / ERP Sales Rep tables (or backend returns an empty array `[]`).
  - If the prompt opens with `canDismiss: false` simply because "sync finished", the user will hit the exact same deadlock modal again!
- **Resolution (Poka-Yoke / Failsafe)**:
  - Modify `SalesRepSelectionDialog`: If `_allReps.isEmpty`, the dialog **MUST NEVER lock the user out**.
  - If `_allReps.isEmpty`, automatically enable `canDismiss = true` and provide a prominent "Close" or "No Reps Configured - Contact Admin" button.
  - A modal with 0 selectable choices must never prevent the user from escaping.

---

### Challenge 4: Preventing Transactions Before Salesman Selection
- **The Risk**:
  - If we don't force salesman selection on startup, what if the user taps "Sales" -> "Transaction" before doing initial sync or before selecting a rep?
- **Resolution**:
  - In [sales_menu_screen.dart](file:///d:/enterprise_auth_system/frontend/lib/features/logistics/presentation/pages/sales_invoice/sales_menu_screen.dart) and [select_transaction_screen.dart](file:///d:/enterprise_auth_system/frontend/lib/features/logistics/presentation/pages/sales_invoice/select_transaction_screen.dart):
    - Tapping "Transaction" checks if `_selectedSalesReps.isNotEmpty`.
    - If empty, it checks whether `tbl_sales_reps` has records.
      - If reps exist: Prompts `SalesRepSelectionDialog.show(canDismiss: false)`.
      - If 0 reps exist: Shows an alert SnackBar / Dialog: *"Please perform Data Sync first before starting transactions."*

---

### Challenge 5: Multi-User / Shared Device Behavior
- **The Scenario**:
  - Field agent Alice logs in on Tablet A and performs initial sync. `tbl_sales_reps` is now populated. Alice selects Rep 01.
  - Alice logs out. Field agent Bob logs in on the same Tablet A.
  - Does Bob need initial sync? No, `tbl_sales_reps` is already cached locally.
  - Does Bob need to select his sales rep? **YES!** Because Bob's session currently has no selected reps in `tbl_user_selected_sales_reps` for `username == 'bob'`.
- **Resolution**:
  - If `tbl_sales_reps.isNotEmpty` AND `userSelectedReps.isEmpty`: Prompt Bob on startup!
  - If `tbl_sales_reps.isEmpty`: Skip startup prompt and wait for sync.
  - This guarantees perfect offline behavior for shared devices without redundant syncs.

---

## 3. Step-by-Step Architecture & Implementation Plan

```
┌────────────────────────────────────────────────────────┐
│                   App Startup / Login                  │
└───────────────────────────┬────────────────────────────┘
                            │
              Query SQLite tbl_sales_reps count
                            │
               ┌────────────┴────────────┐
               ▼                         ▼
         [ Count == 0 ]            [ Count > 0 ]
               │                         │
     Do NOT prompt dialog        Check User's Rep Selection
     Allow free access to Home           │
     Show Sync indicator                 ├─ Empty? ──► Prompt Sales Rep Dialog
               │                         └─ Selected? ► Proceed silently
               ▼
    User Taps "Data Sync"
    (Downloads Customers, Reps,
     Products, Open Invoices)
               │
      Sync Completes &
   Overlay Dismissed by User
               │
   Check: Has active rep selected?
               │
         ┌─────┴─────┐
         ▼           ▼
       [No]        [Yes]
         │           │
   Prompt Reps     Done
   Dialog with
   Fresh Data!
```

---

### Phase 1: LocalDatabaseHelper Extensions
**Target:** [local_database_helper.dart](file:///d:/enterprise_auth_system/frontend/lib/features/logistics/data/local/local_database_helper.dart)
1. Add `Future<int> getSalesRepsCount()`:
   ```dart
   Future<int> getSalesRepsCount() async {
     final db = await database;
     final count = Sqflite.firstIntValue(
       await db.rawQuery('SELECT COUNT(*) FROM $tableReps'),
     );
     return count ?? 0;
   }
   ```
2. Ensure query is instant, non-blocking, and thread-safe.

---

### Phase 2: HomeScreen Startup Guard & Sync Completion Listener
**Target:** [home_screen.dart](file:///d:/enterprise_auth_system/frontend/lib/features/auth/presentation/pages/home_screen.dart)
1. **Startup Check Adjustment**:
   In `_checkAndPromptSalesRepSelection()`:
   - Check `final repCount = await LocalDatabaseHelper.instance.getSalesRepsCount();`
   - If `repCount == 0`:
     - Set `HomeScreen._promptedSessionUser = null;`
     - Log debug notice: `Home: 0 sales reps in local DB. Deferring prompt until initial sync completes.`
     - **Return immediately without opening the dialog.**
2. **Post-Sync Trigger Mechanism**:
   - Wrap dashboard or add `BlocListener<SalesInvoiceSyncBloc, SalesInvoiceSyncState>` in `HomeScreen`:
   - When sync completes (`SalesInvoiceSyncSuccess`) or when user dismisses sync overlay (`SalesInvoiceSyncInitial` after previous `SalesInvoiceSyncSuccess`), trigger `_checkAndPromptSalesRepSelection(force: true)`.
   - Re-queries `getSalesRepsCount()`. Because sync populated `tbl_sales_reps`, the dialog opens with all available representatives.

---

### Phase 3: Poka-Yoke Deadlock Prevention in Dialog
**Target:** [sales_rep_selection_dialog.dart](file:///d:/enterprise_auth_system/frontend/lib/features/logistics/presentation/widgets/sales_rep_selection_dialog.dart)
1. In `_SalesRepSelectionDialogState`:
   - If `_allReps.isEmpty && !_isLoading`:
     - Allow dialog dismissal regardless of `canDismiss` flag (`canClose = true`).
     - Display a clean empty-state card:
       - Icon: `Icons.sync_problem_rounded`
       - Title: *"No Sales Representatives Found"*
       - Subtitle: *"Please connect to the network and perform a Data Sync from the Home screen."*
       - Button: *"CLOSE"* (Pops dialog safely).
2. Guarantees the app will **never under any circumstance** trap the user in an un-dismissible modal.

---

### Phase 4: Module Entry Gate in Sales Module
**Target:** [sales_menu_screen.dart](file:///d:/enterprise_auth_system/frontend/lib/features/logistics/presentation/pages/sales_invoice/sales_menu_screen.dart)
1. When user taps "Transaction" or "Open Invoice":
   - If `_selectedSalesReps.isEmpty`:
     - Prompt `SalesRepSelectionDialog.show(...)`.
     - If database has 0 reps, prompt: *"Sync required before processing sales transactions."*

---

## 4. Verification & Testing Protocol

| Test Scenario | Starting Condition | Action | Expected Outcome |
| :--- | :--- | :--- | :--- |
| **Fresh Install / Zero Data** | Clear app data / Fresh DB (`tbl_sales_reps` has 0 rows) | Launch app & login | **No modal appears.** User sees Home Screen with "Data Sync" button unobstructed. |
| **Initial Sync Flow** | Home Screen on Fresh Install | Tap "Data Sync", wait for success, tap "DISMISS" | App automatically pops `SalesRepSelectionDialog` showing fresh reps. |
| **Sales Rep Selection** | Dialog open with reps | Select 1+ rep, tap "CONFIRM SELECTION" | Reps saved in SQLite `tbl_user_selected_sales_reps`, dialog closes, user unblocked. |
| **Subsequent App Open** | Reps already selected in previous session | Close app & reopen | User enters Home Screen directly without being blocked. |
| **Zero Reps from ERP (Failsafe)** | ERP returns empty list for site | Trigger sync | Dialog shows "CLOSE" button; user is NOT locked out. |
