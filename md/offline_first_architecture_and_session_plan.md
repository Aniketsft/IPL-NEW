# Architecture Challenge & Plan: 100% Offline Operational Mode with Isolated Sync

## 1. Executive Summary & Core Mandate

> **Core Mandate**: The application must be **100% operational in offline mode**. Field workers must be able to log in, create sales invoices, print receipts, look up products, scan barcodes, and manage warehouse workflows without any network connectivity. **The ONLY operation that is not possible while offline is data synchronization (`Sync`) with Sage X3.**

The current architecture violates this mandate: when the device loses connectivity or operates in a warehouse with poor signal, the application automatically logs the user out, blocking all operational work.

---

## 2. Rigorous Architectural Challenge: 5 Core Failure Points

### Failure Point 1: Online-Coupled Session Lifecycle (Flawed Identity Model)
* **Current Flaw**: The client app treats a short-lived server JWT token (15–30 min expiry) as the heartbeat of the local application. The moment the JWT expires locally (`isTokenExpired(token) == true`), or on a touch event (`UserInteracted`), `AuthBloc` attempts a silent refresh. When the network is offline, this refresh fails, and `AuthBloc` threatens or executes session destruction.
* **Architectural Violation**: A mobile field application must decouple the **Local Operating Session** (governed by shift inactivity, e.g. 8 hours, and 7-day offline credential caching) from the **Remote Transport Token (JWT)** (which is only required during network transactions).
* **Target Architecture**:
  1. Once logged in (either online or via cached SHA-256 credentials in SQLite), the user has an authoritative local session.
  2. Local UI access is NEVER gated on JWT validity.
  3. The JWT is purely a transport credential for backend API calls during `Sync`.

---

### Failure Point 2: Blind Session Destruction in Dio Interceptor (`network_service.dart` + `main.dart`)
* **Current Flaw**: In [`network_service.dart`](file:///d:/enterprise_auth_system/frontend/lib/core/network_service.dart#L67-L87):
  ```dart
  if (token == null || token.isEmpty || isTokenExpired(token)) {
    onUnauthorized?.call(); // <-- Blindly called on client-side check
    return handler.reject(...);
  }
  ```
  In [`main.dart`](file:///d:/enterprise_auth_system/frontend/lib/main.dart#L162-L164):
  ```dart
  context.read<NetworkService>().onUnauthorized = () {
    authBloc.add(LogoutRequested()); // <-- Blindly wipes all storage!
  };
  ```
* **Architectural Violation**: Client-side network interceptors assume every blocked or expired network call is an authentication breach. In offline mode, an expired JWT is normal; treating it as an eviction event wipes all local storage and dumps the worker back to the login screen mid-task.
* **Target Architecture**:
  1. `NetworkService` must NEVER trigger `onUnauthorized` on client-side token expiration when offline.
  2. `onUnauthorized` must only be invoked when the server is reachable and returns an actual HTTP `401 Unauthorized` that cannot be resolved via token refresh.
  3. `main.dart` must check `isOfflineSessionValid()` before ever processing a logout.

---

### Failure Point 3: Screen-Level Network Leaks (Violating Local Database Exclusivity)
* **Current Flaw**: In [`home_screen.dart`](file:///d:/enterprise_auth_system/frontend/lib/features/auth/presentation/pages/home_screen.dart#L63-L65) and [`sales_rep_selection_dialog.dart`](file:///d:/enterprise_auth_system/frontend/lib/features/logistics/presentation/widgets/sales_rep_selection_dialog.dart#L106-L110):
  On initial frame render, `SalesRepSelectionDialog` calls `syncRepository.fetchAndSyncSalesReps()`, firing an HTTP GET to `SalesInvoice/salesreps`.
* **Architectural Violation**: This directly violates [`docs/offline_first_workflow.md`](file:///d:/enterprise_auth_system/docs/offline_first_workflow.md) (Rule 3: *"Screens must NEVER trigger API calls on initialization; data must ONLY be synced via the global Sync Button"*). When launched offline, this unprompted network call triggers the interceptor failure described in Failure Point 2, instantly aborting the session on startup.
* **Target Architecture**:
  1. All screens, dialogs, dropdowns, and views must query **strictly from local SQLite (`LocalDatabaseHelper`)**.
  2. Zero HTTP requests may be executed during screen navigation or widget building.

---

### Failure Point 4: Storage Metadata Amputation During Offline Login
* **Current Flaw**: In [`auth_repository.dart`](file:///d:/enterprise_auth_system/frontend/lib/features/auth/data/repositories/auth_repository.dart#L76-L117):
  `_attemptOfflineLogin` verifies the cached password hash in `tbl_cached_users` and returns a `User` entity, but **never writes `username`, `siteCode`, or an offline session token to `SecureStorageService`**.
* **Architectural Violation**: Later, when `isOfflineSessionValid()` is called, it checks `final username = await _storageService.getUsername(); if (username == null) return false;`. Because `_attemptOfflineLogin` neglected to save the username, `isOfflineSessionValid()` returns `false`, causing `AuthBloc` to trigger an auto-logout on the user's very first screen tap!
* **Target Architecture**:
  `_attemptOfflineLogin` must write the active session metadata (`username`, `siteCode`, and an offline session token marker) into `SecureStorageService`.

---

### Failure Point 5: Uncontained Sync Failures
* **Current Flaw**: The Sync action doesn't cleanly isolate network failures from the application state. If network connectivity drops mid-sync, exceptions bubble up, risk triggering `onUnauthorized`, or leave the UI in an unhandled state.
* **Target Architecture**:
  1. **Pre-flight Connectivity Check**: When the user presses the `Sync` button, verify server reachability.
  2. If unreachable: Emit a clean, informative UI message: *"Sync Unavailable: Device is offline. All records are safely saved locally and will be synchronized when connectivity is restored."*
  3. **Containment Guarantee**: A failed sync must NEVER touch the local authentication state, delete cached master data, or trigger a logout.

---

## 3. The Target Operational Model

```
┌────────────────────────────────────────────────────────────────────────┐
│                        FIELD APPLICATION (MOBILE)                      │
│                                                                        │
│   ┌────────────────────────────────────────────────────────────────┐   │
│   │                    100% OPERATIONAL OFFLINE                    │   │
│   │                                                                │   │
│   │  • Offline Login (Cached SHA-256 Credentials, up to 7 days)    │   │
│   │  • Sales Invoicing & Credit Notes Creation                     │   │
│   │  • Customer & Sales Rep Selection (Local SQLite)               │   │
│   │  • Product Catalog & Stock Inspection (Local SQLite)           │   │
│   │  • Barcode Scanning & Delivery Preparation                     │   │
│   │  • Bluetooth / Network Receipt Printing                        │   │
│   │  • 8-Hour Work Shift Inactivity Lifetime (No Mid-Task Logout)  │   │
│   └────────────────────────────────────────────────────────────────┘   │
│                                   │                                    │
│                       Local Outbox & Staging DB                        │
│                     (tbl_sales_invoices_staging)                       │
│                                   │                                    │
│   ┌───────────────────────────────▼────────────────────────────────┐   │
│   │                  ONLY SYNC REQUIRES NETWORK                    │   │
│   │                                                                │   │
│   │  • Explicit User Action: "Sync Now" button                     │   │
│   │  • If Online: Refreshes JWT -> Pushes Staging -> Pulls Master  │   │
│   │  • If Offline: Shows graceful banner ("Offline: Records saved  │   │
│   │    locally") -> Zero impact on session or local data           │   │
│   └────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Technical Implementation Plan

### Milestone 1: Fix Offline Login Persistence in `AuthRepository`
* **File**: [`frontend/lib/features/auth/data/repositories/auth_repository.dart`](file:///d:/enterprise_auth_system/frontend/lib/features/auth/data/repositories/auth_repository.dart)
* **Actions**:
  1. In `_attemptOfflineLogin`:
     - Save `username` to `_storageService.saveUsername(user.username)`.
     - Save `siteCode` to `_storageService.saveSiteCode(user.siteCode)`.
     - Save an offline session token marker: `_storageService.saveToken('OFFLINE_SESSION_${user.username}')`.
  2. In `isOfflineSessionValid()`:
     - Check `tableCachedUsers` last sync timestamp against `AuthConfig.offlineLoginWindow` (7 days).

---

### Milestone 2: Decouple `NetworkService` and Suppress Client-Side Evictions
* **File**: [`frontend/lib/core/network_service.dart`](file:///d:/enterprise_auth_system/frontend/lib/core/network_service.dart)
* **Actions**:
  1. Remove `onUnauthorized?.call()` from `onRequest` interceptor when token is missing or locally expired.
  2. If token is expired or missing in `onRequest`, reject the request with `DioExceptionType.connectionError` ("Device is offline / token expired") so repositories fall back to local SQLite without triggering session eviction.
  3. Only invoke `onUnauthorized` inside `onError` when the backend explicitly returns an HTTP `401 Unauthorized` response to a live online request.

---

### Milestone 3: Guard `onUnauthorized` Handler in `main.dart`
* **File**: [`frontend/lib/main.dart`](file:///d:/enterprise_auth_system/frontend/lib/main.dart)
* **Actions**:
  1. In `onUnauthorized` callback:
     - Check `isOfflineSessionValid()`.
     - If an offline session is active, suppress the logout and log a debug message.
     - Only dispatch `LogoutRequested()` if the session has truly expired beyond `AuthConfig.offlineLoginWindow` or `sessionTimeout`.

---

### Milestone 4: Enforce Zero-Network Screen Rule
* **File**: [`frontend/lib/features/logistics/presentation/widgets/sales_rep_selection_dialog.dart`](file:///d:/enterprise_auth_system/frontend/lib/features/logistics/presentation/widgets/sales_rep_selection_dialog.dart)
* **Actions**:
  1. In `_loadData()`:
     - Remove the direct HTTP call `syncRepository.fetchAndSyncSalesReps()`.
     - Load exclusively from `LocalDatabaseHelper.instance.getSalesReps()`.
     - Allow manual sync only through the explicit sync overlay.

---

### Milestone 5: Robust Offline Sync Gate in Sync BLoCs
* **Files**: 
  - [`frontend/lib/features/logistics/presentation/bloc/sales_invoice_sync_bloc.dart`](file:///d:/enterprise_auth_system/frontend/lib/features/logistics/presentation/bloc/sales_invoice_sync_bloc.dart)
  - [`frontend/lib/features/logistics/presentation/bloc/sync_bloc.dart`](file:///d:/enterprise_auth_system/frontend/lib/features/logistics/presentation/bloc/sync_bloc.dart)
* **Actions**:
  1. Wrap sync operations in an offline pre-flight check.
  2. When offline, emit `SyncFailure("Cannot sync while offline. All records are safely saved locally.")`.
  3. Guarantee that sync failures NEVER dispatch `LogoutRequested()` or delete staging tables.

---

### Milestone 6: Decouple Inactivity & Refresh Timers in `AuthBloc`
* **File**: [`frontend/lib/features/auth/presentation/bloc/auth_bloc.dart`](file:///d:/enterprise_auth_system/frontend/lib/features/auth/presentation/bloc/auth_bloc.dart)
* **Actions**:
  1. In `_onUserInteracted`:
     - If network refresh throws, verify `isOfflineSessionValid()`.
     - When offline, slide the inactivity timer forward and let the user continue working.
  2. In `_onValidateSession`:
     - Do not log out on expired JWT if `isOfflineSessionValid()` is true.
     - Only log out if idle time exceeds `AuthConfig.sessionTimeout` (8 hours of zero activity).

---

## 5. Verification & Acceptance Criteria

1. **Cold Offline Launch**: Turn off Wi-Fi/cellular. Launch app. Log in with previously cached credentials.
   - *Expected Result*: Successful login into `HomeScreen` with 0 auto-logouts.
2. **Offline Operations**:
   - Open Sales Invoicing, select sales reps, select customers, add items from cached stock, save invoice.
   - *Expected Result*: Invoice saves cleanly to local SQLite staging table; print preview works.
3. **Attempt Offline Sync**:
   - Tap "Sync" button while offline.
   - *Expected Result*: Shows graceful snackbar/overlay: "Device is offline. Records saved locally." Session remains fully active.
4. **Reconnect & Sync**:
   - Turn Wi-Fi/cellular on. Tap "Sync".
   - *Expected Result*: Token refreshes automatically, staging records push to Sage X3, fresh master data pulls into SQLite.

---

## 6. Implementation Status (Completed)

| Milestone | Target Component | Status | Verification Detail |
| :--- | :--- | :--- | :--- |
| **Milestone 1** | `auth_repository.dart` | Completed | `_attemptOfflineLogin` stores `username`, `siteCode`, and `'OFFLINE_SESSION_${username}'` in `SecureStorageService`. `isOfflineSessionValid()` returns `true`. |
| **Milestone 2** | `network_service.dart` | Completed | Suppressed client-side eviction from `onRequest`; offline session / missing token rejects safely with `DioExceptionType.connectionError` without calling `onUnauthorized`. |
| **Milestone 3** | `main.dart` | Completed | `onUnauthorized` callback verifies `isOfflineSessionValid()` before evicting session; suppresses logout when offline session is valid. |
| **Milestone 4** | `sales_rep_selection_dialog.dart` | Completed | Zero-network rule enforced; dialog queries exclusively from local SQLite database on open. |
| **Milestone 5** | `sales_invoice_sync_bloc.dart`, `sync_bloc.dart`, `sales_invoice_sync_repository.dart` | Completed | Connection errors caught and reported with user-friendly notification: *"Cannot sync while offline. All records are safely saved locally."* Staging tables preserved. |
| **Milestone 6** | `auth_bloc.dart` | Completed | Decoupled timers; background token refresh and expiry timers skipped for offline sessions; `_onUserInteracted` and `_onValidateSession` keep offline sessions active for full shift. |

