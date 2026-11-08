# Architectural Plan: Option B — Module-Level License Lockout

## 1. Objective & Scope

Implement **Option B (Module-Level Lockout)** across frontend and backend:
* When a tablet's license is `UNVALIDATED` (`isLicensed == false`):
  * **Exempt Module**: The **Device Module** (`DevicesScreen` / Tablet Fleet) remains **100% accessible** at all times so administrators can view device health, audit credentials, and toggle the license back to `VALID`.
  * **Locked Modules**: All operational and business modules (`Data Sync`, `Sales`, `Delivery`, `Sales Reports`, `OTP Generation`, `Manufacturing`, `QR Label`, `Printer Settings`, `Export to X3`, and drawer settings) are locked down.
  * **User Experience**:
    * An industrial warning banner appears on the dashboard alerting the operator.
    * Tapping any locked module displays a specialized **Tablet License Suspended Modal** with full device identification (`HM2`, UUID) and direct actions: **"Open Tablet Fleet"**, **"Re-check License"**, and **"Dismiss"**.
  * **Backend Zero-Trust Gate**:
    * Operational API endpoints (`/api/Sync/*`, `/api/SalesInvoice/*`, `/api/Logistics/*`) reject incoming requests from unvalidated devices with `HTTP 403 Forbidden` (`DEVICE_LICENSE_SUSPENDED`).
    * `/api/Devices/*` and `/api/Auth/*` remain accessible so heartbeat, login, and license toggles function seamlessly.

---

## 2. Architecture & Data Flow

```mermaid
sequenceDiagram
    autonumber
    participant Admin as System Administrator
    participant Tablet as Field Tablet (HM2)
    participant UI as HomeScreen / Drawer
    participant Filter as DeviceLicenseCheckFilter
    participant API as ASP.NET Core API
    participant DB as MSSQL (DeviceLocations)

    Admin->>API: POST /api/Devices/{id}/toggle-license (isLicensed: false)
    API->>DB: UPDATE DeviceLocations SET IsLicensed = 0, LicenseStatus = 'UNVALIDATED'
    API-->>Tablet: DeviceLocationDto (isLicensed: false, UNVALIDATED)
    Tablet->>Tablet: Local SharedPreferences & SQLite updated

    Note over Tablet,UI: Operator attempts to use app

    alt Operator taps Device Module (Tablet Fleet)
        UI->>UI: Allow Navigation -> DevicesScreen opens
        Note over UI: Administrator can toggle license back ON
    else Operator taps Sales / Delivery / Data Sync
        UI->>UI: Intercept tap -> Show "TABLET LICENSE UNVALIDATED" Modal
        Note over UI: Module does NOT open; options to Go to Fleet or Re-check
    else Direct API Request from Tablet
        Tablet->>Filter: POST /api/Sync/refresh (Header: X-Device-Id: 7bae...)
        Filter->>DB: Query DeviceLocations where DeviceId = 7bae...
        DB-->>Filter: Device found with IsLicensed = 0 (UNVALIDATED)
        Filter-->>Tablet: HTTP 403 Forbidden (DEVICE_LICENSE_SUSPENDED)
        Tablet->>Tablet: Set local isLicensed = false & show modal
    end
```

---

## 3. Detailed Component Breakdown

### 3.1. Frontend: Mobile Home Screen & Drawer Lockout ([`home_screen.dart`](file:///d:/enterprise_auth_system/frontend/lib/features/auth/presentation/pages/home_screen.dart))

1. **License Status Observability**:
   * Inspect `DeviceInfoService.instance.isLicensed` on render.
   * If `false`:
     * Render an industrial alert banner above the dashboard grid:
       ```
       ⚠️ TABLET OPERATIONAL LICENSE UNVALIDATED
       Operational features (Sales, Delivery, Data Sync) are suspended. 
       [Open Tablet Fleet]
       ```
2. **Module Interception**:
   * In `_buildMenuButton`:
     * If `!isLicensed`: display a subtle padlock badge on the card and route all taps to `_showUnlicensedDeviceModal(context, moduleName: title)`.
   * In top bar `Export to X3` action:
     * If `!isLicensed`: intercept and show modal.
   * In `_buildDrawer`:
     * `Settings`: Intercept if `!isLicensed`.
     * `User Admin`: Intercept if `!isLicensed`.
     * `Sync Logs`: Intercept if `!isLicensed`.
     * **`Devices`**: **EXEMPT** — opens `DevicesScreen()` unconditionally.
     * `Dashboard`, `Theme Toggle`, `Log out`: **EXEMPT**.
3. **`_showUnlicensedDeviceModal` (Custom Industrial Dialog)**:
   * Header: Warning badge with `Icons.gpp_bad_rounded` in amber/red.
   * Body:
     * Device Name (`HM2`) & UUID (`7bae7c3e-...`).
     * Status: `UNVALIDATED`.
     * Explanation: *"Access to [Module Name] is blocked because this tablet's operational license is currently unvalidated."*
   * Action buttons:
     * **"Open Tablet Fleet"**: Navigates straight to [`DevicesScreen`](file:///d:/enterprise_auth_system/frontend/lib/features/administration/ui/screens/devices_screen.dart) for administrative review.
     * **"Re-Check License"**: Calls `/api/Devices/heartbeat` to refresh status live from the server. If an admin has validated the device remotely, access is restored immediately.
     * **"Dismiss"**: Closes modal.

---

### 3.2. Backend: Zero-Trust Action Filter ([`DeviceLicenseActionFilter.cs`](file:///d:/enterprise_auth_system/backend/src/EnterpriseAuth.Api/Infrastructure/Security/DeviceLicenseActionFilter.cs))

1. **`[ValidateDeviceLicense]` Action Filter**:
   * Inspects `X-Device-Id` header (or fallback query parameter / body).
   * Queries `ScanProductionDbContext.DeviceLocations` (using cached query for high performance).
   * If the device exists in `DeviceLocations` and `!device.IsLicensed` or `device.LicenseStatus != "VALID"`:
     * Returns:
       ```json
       {
         "statusCode": 403,
         "error": "DEVICE_LICENSE_SUSPENDED",
         "message": "Device 'HM2' operational license is UNVALIDATED. Access suspended."
       }
       ```
2. **Applied Controllers**:
   * `SyncController`: All sync actions (`refresh`, `push`, `log-event`).
   * `SalesInvoiceController`: Invoicing, payments, and credit note synchronization.
   * `LogisticsController`: Delivery and production tracking.
3. **Strictly Exempt Controllers**:
   * `DevicesController`: Completely unblocked so tablets can send heartbeat, load lorries, and toggle licenses.
   * `AuthController`: Completely unblocked so field users can log in and view their credentials.

---

## 4. Implementation Checklist

| Step | Component | Description | Status | Files Affected |
| :--- | :--- | :--- | :--- | :--- |
| **1** | Backend Filter | Create `ValidateDeviceLicenseAttribute` & `DeviceLicenseActionFilter` | Completed | `backend/.../Infrastructure/Security/DeviceLicenseActionFilter.cs` |
| **2** | Backend Registration | Register filter in dependency injection container | Completed | `backend/.../Program.cs` |
| **3** | Backend Decoration | Add `[ValidateDeviceLicense]` to operational controllers | Completed | `SyncController.cs`, `SalesInvoiceController.cs`, `LogisticsController.cs` |
| **4** | Frontend Modal | Create `_showUnlicensedDeviceModal` with "Open Tablet Fleet" & "Re-check License" | Completed | `frontend/.../presentation/pages/home_screen.dart` |
| **5** | Frontend Home Grid | Gate all dashboard buttons (`Data Sync`, `Sales`, `Delivery`, `Reports`, etc.) | Completed | `frontend/.../presentation/pages/home_screen.dart` |
| **6** | Frontend Top Bar | Gate `Export to X3` button | Completed | `frontend/.../presentation/pages/home_screen.dart` |
| **7** | Frontend Drawer | Gate `Settings`, `User Admin`, and `Sync Logs`; keep `Devices` exempt | Completed | `frontend/.../presentation/pages/home_screen.dart` |
| **8** | Frontend Network | Handle `DEVICE_LICENSE_SUSPENDED` HTTP 403 response to auto-lock tablet | Completed | `frontend/.../core/network_service.dart` |

---

## 5. Verification Plan

1. **Exempt Module Test**: Toggle license off $\to$ Verify Drawer $\to$ `Devices` opens normally and displays `UNVALIDATED`.
2. **Operational Module Lockout**: On `HomeScreen`, tap `Sales` $\to$ verify modal pops up: *"Access to Sales is blocked because tablet license is UNVALIDATED"*. Tap `Delivery` $\to$ verify same modal. Tap `Data Sync` $\to$ verify same modal.
3. **Re-Check Live Restoration**: With tablet showing lockout modal, toggle license to `VALID` in `DevicesScreen` $\to$ return to Home or tap "Re-check License" $\to$ verify operational modules immediately unlock.
4. **Backend Zero-Trust Test**: Send curl/Postman to `GET /api/Sync/refresh` with header `X-Device-Id: 7bae7c3e-...` $\to$ verify `HTTP 403 Forbidden` (`DEVICE_LICENSE_SUSPENDED`).

