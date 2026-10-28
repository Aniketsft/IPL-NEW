import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/transaction_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/sales_invoice_product_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/eod_report_model.dart';

class SalesReportPdfService {
  final NumberFormat _numberFormat = NumberFormat('#,##0.00', 'en_US');

  final DateFormat _dateFormat = DateFormat('dd MMM yyyy HH:mm');

  String _cleanText(String text) {
    if (text.isEmpty) return text;
    var cleaned = text
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('•', '-')
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('…', '...')
        .replaceAll('·', '-')
        .replaceAll('°', ' ')
        // Transliterate accented characters to plain ASCII
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[ÉÈÊË]'), 'E')
        .replaceAll(RegExp(r'[àâäáã]'), 'a')
        .replaceAll(RegExp(r'[ÀÂÄÁÃ]'), 'A')
        .replaceAll(RegExp(r'[îïí]'), 'i')
        .replaceAll(RegExp(r'[ÎÏÍ]'), 'I')
        .replaceAll(RegExp(r'[ôöóõ]'), 'o')
        .replaceAll(RegExp(r'[ÔÖÓÕ]'), 'O')
        .replaceAll(RegExp(r'[ùûüú]'), 'u')
        .replaceAll(RegExp(r'[ÙÛÜÚ]'), 'U')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .replaceAll(RegExp(r'[Ç]'), 'C')
        .replaceAll(RegExp(r'[ñ]'), 'n')
        .replaceAll(RegExp(r'[Ñ]'), 'N')
        .replaceAll('œ', 'oe')
        .replaceAll('Œ', 'OE')
        .replaceAll('æ', 'ae')
        .replaceAll('Æ', 'AE');
    // Strip any remaining characters outside standard printable ASCII (0x20 to 0x7E)
    return cleaned.replaceAll(RegExp(r'[^\x20-\x7E]'), '');
  }

  Future<Uint8List> generateInvoiceSummaryPdf({
    required List<TransactionModel> invoices,
    required String reportDate,
  }) async {
    final pdf = pw.Document();

    int totalInvoices = invoices.where((i) => i.type == 'INVOICE').length;
    int totalCreditNotes = invoices.where((i) => i.type == 'CREDIT_NOTE').length;
    double grandTotalRevenue = invoices
        .where((i) => i.type == 'INVOICE' && i.isReversed == 0)
        .fold(0.0, (sum, item) => sum + item.grandTotal);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat(
          288.0,
          PdfPageFormat.a4.height,
          marginLeft: 8,
          marginRight: 8,
          marginTop: 10,
          marginBottom: 10,
        ),
        maxPages: 200,
        build: (context) {
          return [
            _buildHeader('Invoice Summary'),
            pw.SizedBox(height: 5),
            pw.Text('Date: ${_cleanText(reportDate)}', style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 10),
            _buildSummaryStats(totalInvoices, totalCreditNotes, grandTotalRevenue),
            pw.SizedBox(height: 10),
            _buildInvoiceTable(invoices),
            pw.SizedBox(height: 10),
            _buildGrandTotalFooter(grandTotalRevenue),
            pw.SizedBox(height: 15),
            _buildSharedFooter(),
          ];
        },
      ),
    );

    return pdf.save();
  }

  Future<Uint8List> generateStockPreviewPdf({
    required List<SalesInvoiceProductModel> items,
    required String warehouseLabel,
  }) async {
    final pdf = pw.Document();

    final approvedItems = items.where((i) => i.stockStatus == 'A').toList();
    final quarantineItems = items.where((i) => i.stockStatus == 'Q').toList();
    final rejectedItems = items.where((i) => i.stockStatus == 'R').toList();

    final approvedUnits = approvedItems.fold(0.0, (sum, i) => sum + i.stockQty);
    final quarantineUnits = quarantineItems.fold(0.0, (sum, i) => sum + i.stockQty);
    final rejectedUnits = rejectedItems.fold(0.0, (sum, i) => sum + i.stockQty);
    final grandTotalUnits = approvedUnits + quarantineUnits + rejectedUnits;
    final totalUniqueSkus = items.map((i) => i.sku).toSet().length;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat(
          288.0,
          PdfPageFormat.a4.height,
          marginLeft: 8,
          marginRight: 8,
          marginTop: 10,
          marginBottom: 10,
        ),
        maxPages: 200,
        build: (context) {
          return [
            _buildHeader('Stock Preview Report'),
            pw.SizedBox(height: 5),
            pw.Text('Warehouse: ${_cleanText(warehouseLabel)}', style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 8),

            // ── [A] Approved / Sellable Stock ─────────────────────────────
            _buildStockSection(
              '[A] APPROVED / SELLABLE STOCK',
              '[A]',
              approvedItems,
              PdfColors.blueGrey800,
            ),

            // ── [Q] Customer Returns (Quarantine) ──────────────────────────
            _buildStockSection(
              '[Q] CUSTOMER RETURNS (QUARANTINE)',
              '[Q]',
              quarantineItems,
              PdfColors.orange800,
            ),

            // ── [R] Issue in Stock (Damaged / Defective) ───────────────────
            _buildStockSection(
              '[R] ISSUE IN STOCK (DAMAGED / DEFECTIVE)',
              '[R]',
              rejectedItems,
              PdfColors.red800,
            ),

            // ── Physical Stock Reconciliation ──────────────────────────────
            _buildStockReconciliation(
              totalUniqueSkus: totalUniqueSkus,
              approvedUnits: approvedUnits,
              quarantineUnits: quarantineUnits,
              rejectedUnits: rejectedUnits,
              totalUnits: grandTotalUnits,
            ),
            pw.SizedBox(height: 12),
            _buildSharedFooter(),
          ];
        },
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildHeader(String title) {
    return pw.Center(
      child: pw.Column(
        children: [
          pw.Text(
            'INNODIS LTD',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            title,
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Generated: ${_dateFormat.format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 6),
          pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
        ],
      ),
    );
  }

  pw.Widget _buildSummaryStats(int invoices, int creditNotes, double total) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildStatRow('Total Invoices', '$invoices'),
        _buildStatRow('Total Credit Notes', '$creditNotes'),
        _buildStatRow('Grand Revenue (Rs)', _numberFormat.format(total)),
      ],
    );
  }

  pw.Widget _buildStatRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.Text(value, style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );
  }

  pw.Widget _buildInvoiceTable(List<TransactionModel> invoices) {
    return pw.TableHelper.fromTextArray(
      headers: ['Invoice#', 'Date', 'Customer', 'Total (Rs)'],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
      cellStyle: const pw.TextStyle(fontSize: 7.5),
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerLeft,
        3: pw.Alignment.centerRight,
      },
      headerAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerLeft,
        3: pw.Alignment.centerRight,
      },
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(2),
        2: const pw.FlexColumnWidth(2),
        3: const pw.FlexColumnWidth(2),
      },
      data: invoices.map((inv) {
        final date = DateTime.tryParse(inv.createdAt) ?? DateTime.now();
        final displayId = inv.id.length > 8 ? inv.id.substring(inv.id.length - 8) : inv.id;
        final displayCust = inv.customerName.length > 12 ? '${inv.customerName.substring(0, 12)}...' : inv.customerName;
        return [
          _cleanText(displayId),
          DateFormat('dd MMM HH:mm').format(date),
          _cleanText(displayCust),
          _numberFormat.format(inv.grandTotal),
        ];
      }).toList(),
    );
  }

  pw.Widget _buildGrandTotalFooter(double total) {
    return pw.Center(
      child: pw.Column(
        children: [
          pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
          pw.SizedBox(height: 4),
          pw.Text(
            'GRAND REVENUE',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            'Rs ${_numberFormat.format(total)}',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
        ],
      ),
    );
  }

  pw.Widget _buildStockSection(
    String title,
    String statusBadge,
    List<SalesInvoiceProductModel> sectionItems,
    PdfColor headerColor,
  ) {
    final sectionUnits = sectionItems.fold(0.0, (sum, i) => sum + i.stockQty);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(vertical: 2.5, horizontal: 4),
          decoration: pw.BoxDecoration(
            color: headerColor,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              ),
              pw.Text(
                '${sectionItems.length} SKUs',
                style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.white),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 3),
        if (sectionItems.isEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: pw.Text(
              'No items in this category (0.00)',
              style: pw.TextStyle(fontSize: 7.5, fontStyle: pw.FontStyle.italic, color: PdfColors.grey600),
            ),
          )
        else ...[
          _buildStockTable(sectionItems),
          pw.SizedBox(height: 2),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Subtotal $statusBadge: ${sectionUnits.toStringAsFixed(2)} units',
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
        pw.SizedBox(height: 6),
      ],
    );
  }

  pw.Widget _buildStockTable(List<SalesInvoiceProductModel> items) {
    return pw.TableHelper.fromTextArray(
      headers: ['SKU', 'Item Name', 'Qty'],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
      cellStyle: const pw.TextStyle(fontSize: 7.5),
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.center,
      },
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(4),
        2: const pw.FlexColumnWidth(2),
      },
      data: items.map((item) {
        final displaySku = item.sku.length > 10 ? '${item.sku.substring(0, 10)}...' : item.sku;
        final displayName = item.name.length > 18 ? '${item.name.substring(0, 18)}...' : item.name;
        return [
          _cleanText(displaySku),
          _cleanText(displayName),
          '${item.stockQty.toStringAsFixed(0)} ${_cleanText(item.salesUnit)}',
        ];
      }).toList(),
    );
  }

  pw.Widget _buildStockReconciliation({
    required int totalUniqueSkus,
    required double approvedUnits,
    required double quarantineUnits,
    required double rejectedUnits,
    required double totalUnits,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
        color: PdfColors.grey100,
      ),
      padding: const pw.EdgeInsets.all(6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Center(
            child: pw.Text(
              'PHYSICAL STOCK RECONCILIATION',
              style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Divider(thickness: 0.5, color: PdfColors.grey400),
          _buildReconcileRow('Approved / Sellable [A]:', approvedUnits.toStringAsFixed(2)),
          _buildReconcileRow('Customer Returns (Quarantine) [Q]:', quarantineUnits.toStringAsFixed(2)),
          _buildReconcileRow('Issue / Damaged [R]:', rejectedUnits.toStringAsFixed(2)),
          pw.Divider(thickness: 0.5, color: PdfColors.grey400),
          _buildReconcileRow(
            'TOTAL PHYSICAL STOCK:',
            '${totalUnits.toStringAsFixed(2)} units',
            isBold: true,
          ),
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.Text(
              'Total Unique SKUs: $totalUniqueSkus',
              style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildReconcileRow(String label, String value, {bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
          pw.Text(
            value,
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildSharedFooter() {
    final printTime = DateFormat('HH:mm dd MMM').format(DateTime.now());
    return pw.Center(
      child: pw.Column(
        children: [
          pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
          pw.SizedBox(height: 5),
          pw.Text(
            'Thank you!',
            style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Printed: $printTime',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EOD REPORT (INDUSTRIAL & RECONCILED)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Uint8List> generateEodReportPdf(EodReportModel data) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat(
          288.0,
          PdfPageFormat.a4.height,
          marginLeft: 8,
          marginRight: 8,
          marginTop: 10,
          marginBottom: 10,
        ),
        maxPages: 300,
        build: (context) {
          return [
            // ── Header ──────────────────────────────────────────────────────
            _buildEodHeader(data),
            pw.SizedBox(height: 6),
            pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),

            // ── Executive Sales Summary ──────────────────────────────────────
            pw.SizedBox(height: 5),
            _buildEodSectionLabel('DAY-END TURNOVER SUMMARY'),
            pw.SizedBox(height: 3),
            _buildEodSalesBlock(data),
            pw.SizedBox(height: 6),
            pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),

            // ── Section 1: Cash Invoices (Immediate Settlement) ──────────────
            pw.SizedBox(height: 5),
            _buildEodSectionLabel(
                '1. CASH INVOICES (${data.cashInvoices.length})'),
            pw.SizedBox(height: 3),
            _buildEodCashInvoicesTable(data.cashInvoices),
            pw.SizedBox(height: 6),
            pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),

            // ── Section 2: Credit Invoices (Unsettled AR on Term) ─────────────
            pw.SizedBox(height: 5),
            _buildEodSectionLabel(
                '2. CREDIT INVOICES (${data.creditInvoices.length})'),
            pw.SizedBox(height: 3),
            _buildEodCreditInvoicesTable(data.creditInvoices),
            pw.SizedBox(height: 6),
            pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),

            // ── Section 3: Open Invoice Collections (Debt Recovered) ─────────
            pw.SizedBox(height: 5),
            _buildEodSectionLabel(
                '3. OPEN INVOICES COLLECTIONS (${data.openInvoiceCollections.length})'),
            pw.SizedBox(height: 3),
            _buildEodOpenCollectionsTable(data.openInvoiceCollections),
            pw.SizedBox(height: 6),
            pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),

            // ── Section 4: Cancelled Receipts & Returns ──────────────────────
            pw.SizedBox(height: 5),
            _buildEodSectionLabel(
                '4. RETURNS & CANCELLED RECEIPTS (${data.cancelledReceipts.length})'),
            pw.SizedBox(height: 3),
            _buildEodCancelledTable(data.cancelledReceipts),
            pw.SizedBox(height: 6),
            pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),

            // ── Section 5: Cashier & Safe Reconciliation Box ─────────────────
            pw.SizedBox(height: 5),
            _buildEodSectionLabel('5. CASHIER & SAFE RECONCILIATION'),
            pw.SizedBox(height: 3),
            _buildEodReconciliationBox(data),
            pw.SizedBox(height: 6),
            pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),

            // ── Section 6: Revenue per VAT Rate ──────────────────────────────
            pw.SizedBox(height: 5),
            _buildEodSectionLabel('6. REVENUE PER VAT RATE'),
            pw.SizedBox(height: 3),
            _buildEodVatTable(data.vatSummaries, data.salesGross, data.totalVat),
            pw.SizedBox(height: 6),
            pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),

            // ── Section 7: Combined Payment Methods ──────────────────────────
            pw.SizedBox(height: 5),
            _buildEodSectionLabel('7. TOTAL REVENUE PER PAYMENT METHOD'),
            pw.SizedBox(height: 3),
            _buildEodPaymentTable(data.paymentSummaries),
            pw.SizedBox(height: 10),

            // ── Section 8: Sign-off & Audit ──────────────────────────────────
            _buildEodSignOff(data),
            pw.SizedBox(height: 10),

            // ── Footer ───────────────────────────────────────────────────────
            _buildSharedFooter(),
          ];
        },
      ),
    );

    return pdf.save();
  }

  /// Centered header block for EOD report.
  pw.Widget _buildEodHeader(EodReportModel data) {
    return pw.Center(
      child: pw.Column(
        children: [
          pw.Text('INNODIS LTD',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 2),
          pw.Text('END OF DAY RECONCILIATION REPORT',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.Text('(Day-End Shift Closing)',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          pw.SizedBox(height: 5),
          _buildEodInfoRow('Date & Time', '${data.reportDate} ${data.reportTime}'),
          _buildEodInfoRow('Operator / Rep', _cleanText(data.operatorName)),
          _buildEodInfoRow('Device / Register', _cleanText(data.registerId)),
        ],
      ),
    );
  }

  /// Bold left-aligned section label.
  pw.Widget _buildEodSectionLabel(String label) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      child: pw.Text(
        label,
        style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  /// Small info row used in the header block.
  pw.Widget _buildEodInfoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          pw.Text(value, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  /// Total net sales block: sales row, returns row, then summary lines.
  pw.Widget _buildEodSalesBlock(EodReportModel data) {
    final netSales = data.salesGross - data.totalVat;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildEodCountRow('${data.salesCount}', 'Gross Sales Invoiced', 'Rs ${_numberFormat.format(data.salesGross)}'),
        _buildEodCountRow('${data.returnsCount}', 'Returns / Credit Notes', '-Rs ${_numberFormat.format(data.returnsGross)}'),
        pw.SizedBox(height: 3),
        pw.Divider(thickness: 0.3, borderStyle: pw.BorderStyle.dashed),
        pw.SizedBox(height: 2),
        _buildEodTallyRow('Net Sales (Excl. VAT):', 'Rs ${_numberFormat.format(netSales)}'),
        _buildEodTallyRow('Taxes (VAT):', 'Rs ${_numberFormat.format(data.totalVat)}'),
        _buildEodTallyRow('Total Invoiced Revenue:', 'Rs ${_numberFormat.format(data.salesGross)}', bold: true),
      ],
    );
  }

  /// Section 1: Itemized Cash Invoices Table.
  pw.Widget _buildEodCashInvoicesTable(List<EodInvoiceItem> invoices) {
    if (invoices.isEmpty) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Text('No cash invoices recorded for this date.',
            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
      );
    }

    final total = invoices.fold(0.0, (sum, i) => sum + i.grandTotal);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.TableHelper.fromTextArray(
          headers: ['Inv #', 'Customer', 'Tender', 'Total (Rs)'],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7),
          cellStyle: const pw.TextStyle(fontSize: 6.5),
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.centerLeft,
            3: pw.Alignment.centerRight,
          },
          headerAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.centerLeft,
            3: pw.Alignment.centerRight,
          },
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          rowDecoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.3))),
          columnWidths: {
            0: const pw.FlexColumnWidth(2.2),
            1: const pw.FlexColumnWidth(3.8),
            2: const pw.FlexColumnWidth(2.5),
            3: const pw.FlexColumnWidth(2.5),
          },
          data: invoices.map((inv) {
            final shortId = inv.invoiceId.length > 8
                ? inv.invoiceId.substring(inv.invoiceId.length - 8)
                : inv.invoiceId;
            final cust = inv.customerName.length > 15
                ? '${inv.customerName.substring(0, 15)}..'
                : inv.customerName;
            final tender = inv.tenderSummary.length > 13
                ? '${inv.tenderSummary.substring(0, 13)}..'
                : inv.tenderSummary;
            return [
              _cleanText(shortId),
              _cleanText(cust),
              _cleanText(tender),
              _numberFormat.format(inv.grandTotal),
            ];
          }).toList(),
        ),
        pw.SizedBox(height: 3),
        _buildEodTallyRow('Subtotal Cash Invoices (${invoices.length}):',
            'Rs ${_numberFormat.format(total)}',
            bold: true),
      ],
    );
  }

  /// Section 2: Itemized Credit Invoices Table.
  pw.Widget _buildEodCreditInvoicesTable(List<EodInvoiceItem> invoices) {
    if (invoices.isEmpty) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Text('No credit invoices recorded for this date.',
            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
      );
    }

    final total = invoices.fold(0.0, (sum, i) => sum + i.grandTotal);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.TableHelper.fromTextArray(
          headers: ['Inv #', 'Customer', 'Term', 'Total (Rs)'],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7),
          cellStyle: const pw.TextStyle(fontSize: 6.5),
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.centerLeft,
            3: pw.Alignment.centerRight,
          },
          headerAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.centerLeft,
            3: pw.Alignment.centerRight,
          },
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          rowDecoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.3))),
          columnWidths: {
            0: const pw.FlexColumnWidth(2.2),
            1: const pw.FlexColumnWidth(4.5),
            2: const pw.FlexColumnWidth(1.8),
            3: const pw.FlexColumnWidth(2.5),
          },
          data: invoices.map((inv) {
            final shortId = inv.invoiceId.length > 8
                ? inv.invoiceId.substring(inv.invoiceId.length - 8)
                : inv.invoiceId;
            final cust = inv.customerName.length > 18
                ? '${inv.customerName.substring(0, 18)}..'
                : inv.customerName;
            return [
              _cleanText(shortId),
              _cleanText(cust),
              _cleanText(inv.paymentTerm.isNotEmpty ? inv.paymentTerm : 'CREDIT'),
              _numberFormat.format(inv.grandTotal),
            ];
          }).toList(),
        ),
        pw.SizedBox(height: 3),
        _buildEodTallyRow('Subtotal Credit Invoices (${invoices.length}):',
            'Rs ${_numberFormat.format(total)}',
            bold: true),
      ],
    );
  }

  /// Section 3: Itemized Open Invoices Collections Table.
  pw.Widget _buildEodOpenCollectionsTable(
      List<EodOpenInvoiceCollectionItem> collections) {
    if (collections.isEmpty) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Text('No open invoice collections recorded for this date.',
            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
      );
    }

    final total = collections.fold(0.0, (sum, c) => sum + c.amount);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.TableHelper.fromTextArray(
          headers: ['Doc #', 'Customer', 'Method & Ref', 'Amt (Rs)'],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7),
          cellStyle: const pw.TextStyle(fontSize: 6.5),
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.centerLeft,
            3: pw.Alignment.centerRight,
          },
          headerAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.centerLeft,
            3: pw.Alignment.centerRight,
          },
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          rowDecoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.3))),
          columnWidths: {
            0: const pw.FlexColumnWidth(2.2),
            1: const pw.FlexColumnWidth(3.6),
            2: const pw.FlexColumnWidth(3.0),
            3: const pw.FlexColumnWidth(2.2),
          },
          data: collections.map((col) {
            final doc = col.documentNo.length > 9
                ? col.documentNo.substring(col.documentNo.length - 9)
                : col.documentNo;
            final cust = col.customerName.length > 14
                ? '${col.customerName.substring(0, 14)}..'
                : col.customerName;

            String ref = col.paymentMethod;
            if (col.paymentMethod == 'CHEQUE') {
              ref = col.chequeNumber.isNotEmpty
                  ? 'CHQ #${col.chequeNumber}'
                  : 'CHEQUE';
            } else if (col.qrTransactionRef.isNotEmpty) {
              ref = '${col.paymentMethod} (${col.qrTransactionRef})';
            }
            if (ref.length > 14) ref = '${ref.substring(0, 14)}..';

            return [
              _cleanText(doc),
              _cleanText(cust),
              _cleanText(ref),
              _numberFormat.format(col.amount),
            ];
          }).toList(),
        ),
        pw.SizedBox(height: 3),
        _buildEodTallyRow('Subtotal Collections (${collections.length}):',
            'Rs ${_numberFormat.format(total)}',
            bold: true),
      ],
    );
  }

  /// Section 4: Cancelled receipts compact table.
  pw.Widget _buildEodCancelledTable(List<EodCancelledReceipt> items) {
    if (items.isEmpty) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Text('No cancelled receipts or returns.',
            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
      );
    }
    return pw.TableHelper.fromTextArray(
      headers: ['#ID', 'Reason / Customer', 'Net (Rs)', 'Gross (Rs)'],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7),
      cellStyle: const pw.TextStyle(fontSize: 6.5),
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
      },
      headerAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
      },
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      rowDecoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.3))),
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(3.5),
        2: const pw.FlexColumnWidth(2.5),
        3: const pw.FlexColumnWidth(2.5),
      },
      data: items.map((r) {
        final reason = r.reason.length > 14 ? '${r.reason.substring(0, 14)}..' : r.reason;
        return [
          _cleanText(r.invoiceId),
          _cleanText(reason),
          _numberFormat.format(r.net),
          _numberFormat.format(r.gross),
        ];
      }).toList(),
    );
  }

  /// Section 5: Cashier & Safe Reconciliation Box.
  pw.Widget _buildEodReconciliationBox(EodReportModel data) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.8),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('CASHIER RECONCILIATION SUMMARY',
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),

          // 1. Physical Cash Breakdown
          pw.Text('A. Physical Cash Handover',
              style: pw.TextStyle(
                  fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
          pw.SizedBox(height: 2),
          _buildEodSubRow('- Cash from Today\'s Invoices:',
              'Rs ${_numberFormat.format(data.physicalCashFromInvoices)}'),
          _buildEodSubRow('- Cash from Open Invoices:',
              'Rs ${_numberFormat.format(data.physicalCashFromCollections)}'),
          if (data.cashRefundedOnReturns > 0)
            _buildEodSubRow('- Less Cash Refunded (Returns):',
                '-Rs ${_numberFormat.format(data.cashRefundedOnReturns)}'),
          _buildEodTallyRow('> TOTAL PHYSICAL CASH IN HAND:',
              'Rs ${_numberFormat.format(data.netPhysicalCashInHand)}',
              bold: true),

          pw.SizedBox(height: 5),
          pw.Divider(thickness: 0.3, borderStyle: pw.BorderStyle.dashed),
          pw.SizedBox(height: 3),

          // 2. Physical Cheques Breakdown
          pw.Text('B. Physical Cheques Handover (${data.chequeList.length} Cheques)',
              style: pw.TextStyle(
                  fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
          pw.SizedBox(height: 2),
          if (data.chequeList.isEmpty)
            pw.Text('  No cheques received today.',
                style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600))
          else ...[
            ...data.chequeList.map((chq) {
              final bank = chq.bankName.isNotEmpty ? chq.bankName : 'BANK';
              final no = chq.chequeNumber.isNotEmpty ? '#${chq.chequeNumber}' : '#N/A';
              final cust = chq.customerName.length > 12
                  ? '${chq.customerName.substring(0, 12)}..'
                  : chq.customerName;
              return _buildEodSubRow(
                  _cleanText('  $no ($bank) - $cust'), 'Rs ${_numberFormat.format(chq.amount)}');
            }),
          ],
          _buildEodTallyRow('> TOTAL CHEQUES VALUE:',
              'Rs ${_numberFormat.format(data.totalChequesAmount)}',
              bold: true),

          pw.SizedBox(height: 5),
          pw.Divider(thickness: 0.3, borderStyle: pw.BorderStyle.dashed),
          pw.SizedBox(height: 3),

          // 3. Digital Transfers
          pw.Text('C. Digital Remittances (Juice / Blink / Card)',
              style: pw.TextStyle(
                  fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
          pw.SizedBox(height: 2),
          _buildEodSubRow('- Digital from Invoices:',
              'Rs ${_numberFormat.format(data.digitalFromSales)}'),
          _buildEodSubRow('- Digital from Open Invoices:',
              'Rs ${_numberFormat.format(data.digitalFromOpenCollections)}'),
          _buildEodTallyRow('> TOTAL DIGITAL VALUE:',
              'Rs ${_numberFormat.format(data.totalDigitalAmount)}',
              bold: true),

          pw.SizedBox(height: 5),
          pw.Divider(thickness: 0.8),
          pw.SizedBox(height: 3),

          // 4. Executive Daily Grand Settlement
          _buildEodTallyRow('TOTAL FUNDS COLLECTED (Cash + Chq + Dig):',
              'Rs ${_numberFormat.format(data.grandTotalFundsCollected)}',
              bold: true),
          _buildEodTallyRow('TOTAL CREDIT EXTENDED (Terms):',
              'Rs ${_numberFormat.format(data.totalCreditInvoicesAmount)}'),
          _buildEodTallyRow('DAILY INVOICED TURNOVER (Sales):',
              'Rs ${_numberFormat.format(data.grandTotalTurnover)}',
              bold: true),
        ],
      ),
    );
  }

  /// Compact sub-row inside reconciliation container.
  pw.Widget _buildEodSubRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 0.8, horizontal: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Text(label, style: const pw.TextStyle(fontSize: 6.8, color: PdfColors.grey800)),
          ),
          pw.Text(value,
              textAlign: pw.TextAlign.right,
              style: const pw.TextStyle(fontSize: 6.8)),
        ],
      ),
    );
  }

  /// Count + label + amount row for sales/returns.
  pw.Widget _buildEodCountRow(String count, String label, String amount) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 20,
            child: pw.Text(count, style: const pw.TextStyle(fontSize: 7.5)),
          ),
          pw.Expanded(
            child: pw.Text(label, style: const pw.TextStyle(fontSize: 7.5)),
          ),
          pw.SizedBox(
            width: 75,
            child: pw.Text(amount,
                textAlign: pw.TextAlign.right,
                style: const pw.TextStyle(fontSize: 7.5)),
          ),
        ],
      ),
    );
  }

  /// Right-aligned label/value tally row.
  pw.Widget _buildEodTallyRow(String label, String value, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Text(label,
                style: bold
                    ? pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)
                    : const pw.TextStyle(fontSize: 7.5)),
          ),
          pw.Text(value,
              textAlign: pw.TextAlign.right,
              style: bold
                  ? pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)
                  : const pw.TextStyle(fontSize: 7.5)),
        ],
      ),
    );
  }

  /// VAT breakdown 4-column table: %, Net, Tax, Gross.
  pw.Widget _buildEodVatTable(List<EodVatSummary> items, double totalGross, double totalVat) {
    final totalNet = totalGross - totalVat;
    return pw.TableHelper.fromTextArray(
      headers: ['St %', 'Net (Rs)', 'Tax (Rs)', 'Gross (Rs)'],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7),
      cellStyle: const pw.TextStyle(fontSize: 6.5),
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerRight,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
      },
      headerAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerRight,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
      },
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      rowDecoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.3))),
      columnWidths: {
        0: const pw.FlexColumnWidth(1.5),
        1: const pw.FlexColumnWidth(2.5),
        2: const pw.FlexColumnWidth(2.5),
        3: const pw.FlexColumnWidth(2.5),
      },
      data: [
        ...items.map((v) => [
              '${v.taxRatePercent.toStringAsFixed(0)}%',
              _numberFormat.format(v.net),
              _numberFormat.format(v.tax),
              _numberFormat.format(v.gross),
            ]),
        // Totals row
        [
          'Total',
          _numberFormat.format(totalNet),
          _numberFormat.format(totalVat),
          _numberFormat.format(totalGross)
        ],
      ],
    );
  }

  /// Payment method 2-column table: Method, Amount.
  pw.Widget _buildEodPaymentTable(List<EodPaymentSummary> items) {
    final grandTotal = items.fold(0.0, (sum, p) => sum + p.amount);
    return pw.TableHelper.fromTextArray(
      headers: ['Method', 'Amount (Rs)'],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7),
      cellStyle: const pw.TextStyle(fontSize: 6.5),
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerRight,
      },
      headerAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerRight,
      },
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      rowDecoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.3))),
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(2),
      },
      data: [
        ...items.map((p) => [_cleanText(p.method), _numberFormat.format(p.amount)]),
        ['Total', _numberFormat.format(grandTotal)],
      ],
    );
  }

  /// Dual sign-off block for Sales Rep & Cashier.
  pw.Widget _buildEodSignOff(EodReportModel data) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('AUDIT & VERIFICATION SIGN-OFF',
            style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Sales Representative:',
                      style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700)),
                  pw.SizedBox(height: 16),
                  pw.Container(
                    height: 0.5,
                    color: PdfColors.black,
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(_cleanText(data.operatorName),
                      style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
            pw.SizedBox(width: 20),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Depot Cashier / Supervisor:',
                      style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700)),
                  pw.SizedBox(height: 16),
                  pw.Container(
                    height: 0.5,
                    color: PdfColors.black,
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text('Verified & Received',
                      style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

