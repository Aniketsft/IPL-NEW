# Currency & Monetary Presentation Standards

## 1. Centralized Formatter Architecture
All monetary values in the mobile application must be formatted via the centralized utility:
- **Location**: `frontend/lib/core/utils/currency_formatter.dart`
- **Class**: `CurrencyFormatter`
- **Standard Symbol**: `Rs` (Strictly `Rs` with a trailing space in standard output, e.g. `Rs 1,234.50`). Never use `'RS'`, `'RS '`, or `'MUR'`.
- **Locale & NumberFormat**: `en_US` locale with thousands/millions separators (`,`) and strictly 2 decimal places (`#,##0.00`).

## 2. API & Methods
- `CurrencyFormatter.format(double amount, {bool explicitSign = false})`:
  - Standard format: `CurrencyFormatter.format(1250.5)` -> `'Rs 1,250.50'`
  - Negative format: `CurrencyFormatter.format(-50.0)` -> `'-Rs 50.00'`
  - Explicit sign format: `CurrencyFormatter.format(50.0, explicitSign: true)` -> `'+Rs 50.00'`
- `CurrencyFormatter.formatNumber(double amount)`:
  - Formats without symbol: `1250.5` -> `'1,250.50'`
- `CurrencyFormatter.formatDiscount(double amount)`:
  - Formats discount with minus prefix: `25.0` -> `'-Rs 25.00'`
- `CurrencyFormatter.currencyFormat`:
  - Direct `NumberFormat` instance (`NumberFormat.currency(locale: 'en_US', symbol: 'Rs ', decimalDigits: 2)`).

## 3. UI Alignment & Layout Rules
1. **Right-Alignment**:
   - Every monetary figure in lists, tables, cards, dialogs, and summaries must have `textAlign: TextAlign.right` or be aligned to `CrossAxisAlignment.end` / `Alignment.centerRight`.
2. **Summary Row Wrapping**:
   - Labels in summary rows must be wrapped in `Expanded` (e.g. `Expanded(child: Text(label))`) to ensure that trailing monetary text (`Text(amount, textAlign: TextAlign.right)`) is pinned to the right edge and never pushed or overflowed.
3. **Table Column Headers**:
   - When column data is right-aligned (`cellAlignments: { N: pw.Alignment.centerRight }`), the corresponding header MUST also be explicitly configured with `headerAlignments: { N: pw.Alignment.centerRight }`.
4. **Editable & Read-Only Monetary Form Fields**:
   - Both read-only and editable monetary inputs in forms (`_buildInputField`, `_buildReadOnlyField`, dialog `TextField`) must pass `alignRight: true`.
   - For `_buildInputField`, when `alignRight: true`, use a balanced horizontal tile with the label on the left and a dedicated monetary input pill on the right (`isDark ? Colors.grey[800] : Colors.grey[100]` background, 6px border radius, subtle border).
   - Inside the pill, `prefixText` ('Rs ') and `TextField` (`textAlign: TextAlign.left`, wrapped in `ConstrainedBox(minWidth: 20)` and `IntrinsicWidth`) are kept contiguous with zero void gap, while remaining flush right.
5. **Bottom Sticky Action Bars**:
   - In item configuration / detail screens (`AddItemDetailScreen`), bottom action bars must enforce mathematical symmetry:
     - Outer `Row(crossAxisAlignment: CrossAxisAlignment.start)`.
     - Left column: Uppercase header `QUANTITY` (11px, bold, letterSpacing: 0.5) at y=0, `SizedBox(height: 6)`, stepper container (`height: 48, width: 144`).
     - Right column: Uppercase header `ITEM TOTAL` (11px, bold, letterSpacing: 0.5) at y=0, `SizedBox(height: 6)`, total container (`height: 48, alignment: Alignment.centerRight`, child `Text(CurrencyFormatter.format(...), style: 20px bold primaryColor)`).
     - Both headers share the identical baseline and both interactive/value elements share matching 48px heights, preventing vertical staggering.

## 4. PDF Reporting Standards
- **Invoice PDF (`SalesInvoicePdfService.dart`)**:
  - Line items: Unit price explicitly prefixed with `Rs ` (`Rs #,##0.00`).
  - Total summary rows: Right-aligned with `pw.TextAlign.right` and value box widened to `85` points.
- **Credit Note PDF (`CreditNotePdfService.dart`)**:
  - Return line items: Unit price prefixed with `Rs `.
  - Total refund: Right-aligned with `pw.TextAlign.right` and prefixed with `Rs `.
- **Cash Collection PDF (`CashCollectionPdfService.dart`)**:
  - Replaced legacy uppercase `'RS '` with standardized `'Rs '`.
- **Sales & EOD Reports (`SalesReportPdfService.dart`)**:
  - Grand Revenue header and figures formatted as `GRAND REVENUE` and `'Rs #,##0.00'`.
  - Cash Invoices, Credit Invoices, Open Collections, Cancelled Receipts, VAT, and Payment summary tables all enforce matching `headerAlignments` to ensure headers and figures are right-aligned.
  - Reconciliation tallies and sub-rows use `pw.Expanded` labels and `textAlign: pw.TextAlign.right`.
