# Pattern: Sage X3 Customer Return Pricing & Reversal Integrity

## Architecture & Data Flow
When a user processes a Customer Return against an invoice originating from Sage X3:
1. **Invoice History Lines (`tbl_x3_history_lines`)**:
   - `grossPrice` (`GROPRI_0`): Catalog list price before discounts.
   - `netPrice` (`NETPRI_0`): Actual unit selling price paid by customer before tax, net of line discounts.
   - `lineAmountNotTax` (`AMTNOTLIN_0`): Total invoice line net amount.
   - `lineAmountIncTax` (`AMTATILIN_0`): Total invoice line gross amount (with tax).
   - `quantity` (`QTY_0`): Invoiced quantity (EA or catch-weight KG).

2. **Price Loading Rule**:
   - Unit selling price paid by customer:
     ```dart
     final unitNetPrice = netPrice > 0.0001
         ? netPrice
         : ((amtNot > 0.0001 && qty > 0.0001)
             ? (amtNot / qty)
             : ((amtInc > 0.0001 && qty > 0.0001) ? (amtInc / qty) : grossPrice));
     ```
   - Avoid double-discounting: Because `netPrice` is already net of line discounts, `discountAmountFlat` and `discountPercent` are kept at `0.0`.

3. **Tax & VAT Rule**:
   - Historical VAT rate percentage is derived directly from the original invoice:
     ```dart
     final effectiveVatRate = (amtNot > 0.001 && amtInc > amtNot)
         ? (((amtInc - amtNot) / amtNot) * 100).roundToDouble()
         : 0.0;
     ```
   - Stored on `CartItem` as `vatRatePercent` and `taxRule: 'VAT15'` (or `'ZERO'`), ensuring the refund matches the exact tax amount originally paid.

4. **Reversal Tracking against X3 Invoices**:
   - X3 invoices exist in `tbl_x3_history_lines` (not `tbl_si_invoice_lines`).
   - `createStandaloneCreditNote` matches `item.sku` to `tbl_x3_history_lines.productCode` to retrieve `lineNumber`.
   - Reversal record is written into `tbl_si_invoice_line_reversals` (`invoiceId`, `lineId: lineNumber`, `reversedQty`).
   - Prevents duplicate returns and ensures remaining returnable quantity decrements correctly.

5. **Stock Replenishment on Physical Return (`stockTransaction == 1`)**:
   - Defaults warehouse to `salesSite` (e.g. `WH-01`) and lot to `'RETURN'` if not populated on the X3 invoice line.
   - Updates `tbl_sales_invoice_item_stock_details` so physical returns replenish local mobile inventory.
