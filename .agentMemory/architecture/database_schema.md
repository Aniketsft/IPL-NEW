# Local SQLite Database Architecture (`InnodisApp.db`)

## Key Tables & Provenance

### 1. `tbl_si_credit_notes`
- **Purpose**: Stores Credit Notes and Customer Return header records offline.
- **Key Columns**:
  - `creditNoteId` (TEXT PK): e.g., `CN-ST-173...` or `CN-INV-...`
  - `creditNoteType` (TEXT): `RETURN`, `STANDALONE`, `REVERSAL`, `AMOUNT_ONLY`
  - `x3CreditNoteType` (TEXT): Default `'CRN'`
  - `salesSite` (TEXT): Sales site code (e.g. `POD`, `SCG`)
  - `customerCode` (TEXT), `customerName` (TEXT)
  - `grandTotal` (REAL): Refund amount (MUR)
  - `originalInvoiceId` (TEXT): Origin invoice ID if linked, otherwise null
  - `transactionMode` (TEXT): `'1'` = Direct/Standalone, `'4'` = Linked to origin invoice
  - `stockTransaction` (INTEGER): `1` = Customer Return (stock-in required), `0` = Financial refund only
  - `isSynced` (INTEGER): `0` = pending upload, `1` = synced to Sage X3
  - `x3DocumentId` (TEXT): Document ID returned by Sage X3

### 2. `tbl_si_credit_note_lines`
- **Purpose**: Line items for returned/credit-noted items.
- **Key Columns**:
  - `lineId` (INTEGER PK AUTOINCREMENT)
  - `creditNoteId` (TEXT FK)
  - `lineNo` (INTEGER): `1000`, `2000`, etc.
  - `quantity` (REAL)
  - `originInvoiceId` (TEXT), `originLineNo` (INTEGER)
  - `standaloneSku`, `standaloneName`, `standaloneSalesUnit`, `standalonePrice`, `standaloneTaxRule`, `standaloneLot`, `standaloneWarehouse`, `standaloneCce0`

### 3. `tbl_si_credit_note_refunds`
- **Purpose**: Payout / disbursement details.
- **Key Columns**: `refundId`, `creditNoteId`, `method` (`CASH`), `amount`, `bankCode`, `bankName`, `isSynced`

### 4. `tbl_si_invoice_line_reversals`
- **Purpose**: Tracks returned quantities per invoice line to prevent double returns.
- **Key Columns**: `invoiceId`, `lineId`, `reversedQty`, `reversalCreditNoteId`, `createdAt`

### 5. `tbl_si_item_stock_details`
- **Purpose**: Offline stock inventory by item, lot, location, and warehouse.
- When an item is returned, `totalQty = totalQty + returnQty` is immediately updated.
