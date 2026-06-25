# Payment SOAP Data Source & Schema Plan

Here is the updated breakdown of exactly where every placeholder from the `ZPAYWEBA` SOAP template should come from, including the new master data tables, dynamic selections, and how they map to the internal Sage X3 Database tables.

## 1. Data Source Mapping

| Placeholder | Value | Data Source Origin | Status in Mobile DB | Sage X3 DB Mapping |
| :--- | :--- | :--- | :--- | :--- |
| **`{PaymentType}`** | `REC` | **Hardcoded** in Backend/API | N/A | `PAYMENTH.PAYTYP` |
| **`{CustomerCode}`** | `WIN001` | User selected Customer | ✅ Exists (`tbl_si_invoices.customerCode`) | `PAYMENTH.BPR` |
| **`{CompanyCode}`** | `INL` | Typically mapped from the User's `SiteCode` in X3 | N/A | `PAYMENTH.CPY` |
| **`{ControlAccount}`**| `122001` | **X3 Database (Customer Master)** | ❌ **Missing** (Add to `tbl_si_customers`) | `PAYMENTH.BPRSAC` / `BPCUSTOMER.BPCINV` |
| **`{PaymentMethod}`** | `CHQ` | **User Input** (Dropdown) | ✅ Exists (`tbl_si_payments.method`) | `PAYMENTH.PAM` |
| **`{SiteCode}`** | `CGD` | **Select Transaction Screen** | ⚠️ Fetch from transaction screen UI state | `PAYMENTH.FCY` |
| **`{BankCode}`** | `MCB92` | **User Selection from Master Data** | ❌ **Missing** (Add `tbl_bank_codes` & UI dropdown) | `PAYMENTH.BAN` |
| **`{Status}`** | `2` | **Hardcoded** in Backend (2 = Validated/Posted) | N/A | `PAYMENTH.STA` |
| **`{Currency}`** | `MUR` | **X3 Database (Customer or Global)** | ❌ **Missing** (Add to Customer/Invoices) | `PAYMENTH.CUR` |
| **`{Amount}`** | `93.36` | **User Input** (Amount paid) | ✅ Exists (`tbl_si_payments.amount`) | `PAYMENTH.AMTCUR` |
| **`{PaymentDate}`** | `20251230`| **Device Database** (Date created/Cheque date) | ✅ Exists (`tbl_si_payments.chequeDate` or `createdAt`) | `PAYMENTH.ACCDAT` / `PAYMENTH.DAT` |
| **`{AppliedDocType}`**| `SINV` | **Hardcoded** for Sales Invoices | N/A | `PAYMENTD.VCRTYP` |
| **`{AppliedDocId}`** | `CGDSI...`| **X3 Database (The real X3 Invoice ID)** | ❌ **Missing** (App needs to save `x3DocumentId`) | `PAYMENTD.VCRNUM` |

---

## 2. Implementation Plan

To make offline payments work properly and accurately tie them to X3, we will execute the following steps:

### Step 1: Add `controlAccount` and `currency` to Customers
X3 needs to know which GL Control Account to credit and the transaction currency.
*   **Action:** Update the `/api/SalesInvoice/customers` backend endpoint to retrieve `ControlAccount` and `Currency` from Sage X3 (`BPCUSTOMER` / `BPCINV` tables). Update the Flutter DB `_onUpgrade` to add `controlAccount` (TEXT) and `currency` (TEXT) to `tbl_si_customers`.

### Step 2: Save the `x3DocumentId` when an Invoice Syncs
When a Sales Invoice successfully syncs to the backend, the API returns the real X3 document ID (e.g., `CGDSI251223450`). For the payment to know *which* invoice to pay (`PAYMENTD.VCRNUM`), it needs this ID.
*   **Action:**
    1.  Add `x3DocumentId` (TEXT) to `tbl_si_invoices` in `LocalDatabaseHelper.dart`.
    2.  Update `SalesInvoiceSyncRepository` to extract `response.data['x3DocumentId']` on a 200 OK.
    3.  Update `LocalDatabaseHelper.instance.markSalesInvoiceSynced` to save this `x3DocumentId` locally.

### Step 3: Implement Bank Codes Master Data
X3 requires a Bank Code (`PAYMENTH.BAN`). We will fetch these from the backend so the user can dynamically select the correct bank.
*   **Action:**
    1.  **Backend:** Create a new API endpoint (e.g., `/api/MasterData/banks`) to fetch active Bank Codes from Sage X3.
    2.  **Database:** Create `tbl_bank_codes` (e.g., `code`, `name`, `currency`) in `LocalDatabaseHelper.dart`.
    3.  **Sync:** Add logic to the mobile app's daily master data sync to pull and store these banks.
    4.  **UI:** Update the payment creation screen to include a Bank Code dropdown that reads from `tbl_bank_codes`.

### Step 4: Ensure Dynamic `SiteCode` Propagation
*   **Action:** Verify the frontend logic to ensure that the `{SiteCode}` is dynamically read from the "Select Transaction" screen state rather than relying on a hardcoded or global fallback when constructing the payment payload.

### Step 5: Backend SOAP Service
*   **Action:** Build the `ImportPaymentAsync` method in `SageX3SoapService.cs` using the mapping placeholders defined above, injecting the data into the `ZPAYWEBA` template structure.
