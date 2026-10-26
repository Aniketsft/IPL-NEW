# ADR 001: Customer Return vs Credit Note Architecture

## Context
In wholesale distribution (Innodis/IPL), customers may request two distinct operations:
1. **Credit Note**: Purely financial compensation/rebate (e.g. price adjustment, discount error) where no physical goods are returned to warehouse inventory.
2. **Customer Return**: Physical return of damaged or unsold goods (e.g., chilled chicken, sausages, catch-weight KG items) along with a cash refund or credit.

## Decision
- Both operations share the financial document generation (`CreditNoteModel`, `tbl_si_credit_notes`, and Sage X3 `CRN` credit note).
- Added column `stockTransaction INTEGER DEFAULT 0`:
  - `stockTransaction = 1` for **Customer Return**: Triggers a Sage X3 Miscellaneous Receipt stock-in via SOAP web service in backend, replenishing warehouse physical stock.
  - `stockTransaction = 0` for **Credit Note**: Pure money refund without physical stock movement.
- Customer Return navigation flows:
  `Select Transaction Screen (Customer Return)` -> `X3 Invoice History` -> `Select Invoice Lines & Quantities` -> `Order Summary` -> `Payment Processing (Cash Refund Disbursement)`.
