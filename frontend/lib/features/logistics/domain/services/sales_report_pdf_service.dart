import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/transaction_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/sales_invoice_product_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/eod_report_model.dart';

class SalesReportPdfService {
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'RS ',
    decimalDigits: 2,
  );

  final DateFormat _dateFormat = DateFormat('dd MMM yyyy HH:mm');

  String _cleanText(String text) {
    return text.replaceAll('’', "'").replaceAll('“', '"').replaceAll('”', '"');
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
            pw.Text('Date: $reportDate', style: const pw.TextStyle(fontSize: 10)),
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

    int totalUniqueSkus = items.length;
    double totalUnits = items.fold(0.0, (sum, item) => sum + item.stockQty);

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
            _buildHeader('Stock Preview'),
            pw.SizedBox(height: 5),
            pw.Text('Warehouse: $warehouseLabel', style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 10),
            _buildStockTable(items),
            pw.SizedBox(height: 10),
            _buildStockFooter(totalUniqueSkus, totalUnits),
            pw.SizedBox(height: 15),
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
        _buildStatRow('Grand Revenue', _currencyFormat.format(total)),
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
      headers: ['Invoice#', 'Date', 'Customer', 'Total'],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
      cellStyle: const pw.TextStyle(fontSize: 7.5),
      cellAlignment: pw.Alignment.centerLeft,
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
          displayId,
          DateFormat('dd MMM HH:mm').format(date),
          _cleanText(displayCust),
          _currencyFormat.format(inv.grandTotal),
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
            _currencyFormat.format(total),
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
        ],
      ),
    );
  }

  pw.Widget _buildStockTable(List<SalesInvoiceProductModel> items) {
    return pw.TableHelper.fromTextArray(
      headers: ['SKU', 'Item Name', 'Qty'],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
      cellStyle: const pw.TextStyle(fontSize: 7.5),
      cellAlignment: pw.Alignment.centerLeft,
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
          displaySku,
          _cleanText(displayName),
          item.stockQty.toStringAsFixed(2),
        ];
      }).toList(),
    );
  }

  pw.Widget _buildStockFooter(int uniqueSkus, double totalUnits) {
    return pw.Center(
      child: pw.Column(
        children: [
          pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
          pw.SizedBox(height: 4),
          pw.Text(
            'SKUs: $uniqueSkus   |   Units: ${totalUnits.toStringAsFixed(2)}',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
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
  // EOD REPORT
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
        maxPages: 200,
        build: (context) {
          return [
            // ── Header ──────────────────────────────────────────────────────
            _buildEodHeader(data),
            pw.SizedBox(height: 8),
            pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),

            // ── Total Net Sales ──────────────────────────────────────────────
            pw.SizedBox(height: 6),
            _buildEodSectionLabel('Total net sales'),
            pw.SizedBox(height: 4),
            _buildEodSalesBlock(data),
            pw.SizedBox(height: 6),
            pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),

            // ── Cancelled Receipts ───────────────────────────────────────────
            pw.SizedBox(height: 6),
            _buildEodSectionLabel('Cancelled receipts'),
            pw.SizedBox(height: 4),
            _buildEodCancelledTable(data.cancelledReceipts),
            pw.SizedBox(height: 6),
            pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),

            // ── Cash Balance ─────────────────────────────────────────────────
            pw.SizedBox(height: 6),
            _buildEodSectionLabel('Cash balance'),
            pw.SizedBox(height: 4),
            _buildEodCashBalance(data.cashBalance),
            pw.SizedBox(height: 6),
            pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),

            // ── VAT Breakdown ────────────────────────────────────────────────
            pw.SizedBox(height: 6),
            _buildEodSectionLabel('Total revenue per VAT rate'),
            pw.SizedBox(height: 4),
            _buildEodVatTable(data.vatSummaries, data.salesGross, data.totalVat),
            pw.SizedBox(height: 6),
            pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),

            // ── Payment Methods ──────────────────────────────────────────────
            pw.SizedBox(height: 6),
            _buildEodSectionLabel('Total revenue per payment method'),
            pw.SizedBox(height: 4),
            _buildEodPaymentTable(data.paymentSummaries),
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
          pw.Text('Day-end closing',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 5),
          _buildEodInfoRow('Date', '${data.reportDate} ${data.reportTime}'),
          _buildEodInfoRow('Operator', data.operatorName),
          _buildEodInfoRow('Register', data.registerId),
        ],
      ),
    );
  }

  /// Bold left-aligned section label, matching screenshot style.
  pw.Widget _buildEodSectionLabel(String label) {
    return pw.Text(
      label,
      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
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
          pw.Text(value, style: const pw.TextStyle(fontSize: 8)),
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
        // Header row
        pw.Row(
          children: [
            pw.Expanded(flex: 1, child: pw.SizedBox()),
            pw.Expanded(
                flex: 1,
                child: pw.Text('', style: const pw.TextStyle(fontSize: 8))),
            pw.SizedBox(
              width: 60,
              child: pw.Text('RS',
                  textAlign: pw.TextAlign.right,
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
            ),
          ],
        ),
        pw.SizedBox(height: 2),
        // Sales row
        _buildEodCountRow('${data.salesCount}', 'Sales', _currencyFormat.format(data.salesGross)),
        // Returns row
        _buildEodCountRow('${data.returnsCount}', 'Returns', _currencyFormat.format(data.returnsGross)),
        pw.SizedBox(height: 4),
        pw.Divider(thickness: 0.3, borderStyle: pw.BorderStyle.dashed),
        pw.SizedBox(height: 2),
        _buildEodTallyRow('Total net sales:', _currencyFormat.format(netSales)),
        _buildEodTallyRow('Taxes:', _currencyFormat.format(data.totalVat)),
        _buildEodTallyRow('Total gross sum:', _currencyFormat.format(data.salesGross), bold: true),
      ],
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
            child: pw.Text(count, style: const pw.TextStyle(fontSize: 8)),
          ),
          pw.Expanded(
            child: pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
          ),
          pw.SizedBox(
            width: 70,
            child: pw.Text(amount,
                textAlign: pw.TextAlign.right,
                style: const pw.TextStyle(fontSize: 8)),
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
          pw.Text(label,
              style: bold
                  ? pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)
                  : const pw.TextStyle(fontSize: 8)),
          pw.Text(value,
              style: bold
                  ? pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)
                  : const pw.TextStyle(fontSize: 8)),
        ],
      ),
    );
  }

  /// Cancelled receipts compact table.
  pw.Widget _buildEodCancelledTable(List<EodCancelledReceipt> items) {
    if (items.isEmpty) {
      return pw.Text('No cancelled receipts.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600));
    }
    return pw.TableHelper.fromTextArray(
      headers: ['#ID', 'Reason', 'Net', 'Gross'],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.5),
      cellStyle: const pw.TextStyle(fontSize: 7),
      cellAlignment: pw.Alignment.centerLeft,
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      rowDecoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.3))),
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(3),
        2: const pw.FlexColumnWidth(2),
        3: const pw.FlexColumnWidth(2),
      },
      data: items.map((r) {
        final reason = r.reason.length > 10 ? '${r.reason.substring(0, 10)}...' : r.reason;
        return [
          r.invoiceId,
          reason,
          r.net.toStringAsFixed(2),
          r.gross.toStringAsFixed(2),
        ];
      }).toList(),
    );
  }

  /// Cash balance stacked rows matching the POS screenshot.
  pw.Widget _buildEodCashBalance(EodCashBalance balance) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildEodTallyRow('Cash register balance (previous)', balance.previousBalance.toStringAsFixed(2)),
        _buildEodTallyRow('CASH gross sales', balance.cashGrossSales.toStringAsFixed(2)),
        _buildEodTallyRow('${balance.deposits == 0 ? '0' : ''} Deposits', balance.deposits.toStringAsFixed(2)),
        _buildEodTallyRow('${balance.withdrawals == 0 ? '0' : ''} Withdrawals', balance.withdrawals.toStringAsFixed(2)),
        _buildEodTallyRow('Change (for non-cash)', balance.changeForNonCash.toStringAsFixed(2)),
        _buildEodTallyRow('Tip', balance.tip.toStringAsFixed(2)),
        pw.SizedBox(height: 3),
        pw.Divider(thickness: 0.3, borderStyle: pw.BorderStyle.dashed),
        pw.SizedBox(height: 2),
        _buildEodTallyRow('Cash register balance', _currencyFormat.format(balance.expectedBalance)),
        _buildEodTallyRow('Cash register balance (counted)', _currencyFormat.format(balance.expectedBalance)),
        _buildEodTallyRow('Difference', _currencyFormat.format(0.0)),
        pw.SizedBox(height: 3),
        pw.Divider(thickness: 0.3, borderStyle: pw.BorderStyle.dashed),
        pw.SizedBox(height: 2),
        _buildEodTallyRow('Cash register balance new', _currencyFormat.format(balance.expectedBalance), bold: true),
      ],
    );
  }

  /// VAT breakdown 4-column table: %, Net, Tax, Gross.
  pw.Widget _buildEodVatTable(List<EodVatSummary> items, double totalGross, double totalVat) {
    final totalNet = totalGross - totalVat;
    return pw.TableHelper.fromTextArray(
      headers: ['St %', 'Net', 'Tax', 'Gross'],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.5),
      cellStyle: const pw.TextStyle(fontSize: 7),
      cellAlignment: pw.Alignment.centerLeft,
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      rowDecoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.3))),
      columnWidths: {
        0: const pw.FlexColumnWidth(1.5),
        1: const pw.FlexColumnWidth(2.5),
        2: const pw.FlexColumnWidth(2),
        3: const pw.FlexColumnWidth(2),
      },
      data: [
        ...items.map((v) => [
              '${v.taxRatePercent.toStringAsFixed(0)}%',
              v.net.toStringAsFixed(2),
              v.tax.toStringAsFixed(2),
              v.gross.toStringAsFixed(2),
            ]),
        // Totals row
        ['Total', totalNet.toStringAsFixed(2), totalVat.toStringAsFixed(2), totalGross.toStringAsFixed(2)],
      ],
    );
  }

  /// Payment method 2-column table: Method, Amount.
  pw.Widget _buildEodPaymentTable(List<EodPaymentSummary> items) {
    final grandTotal = items.fold(0.0, (sum, p) => sum + p.amount);
    return pw.TableHelper.fromTextArray(
      headers: ['Method', 'Amount'],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.5),
      cellStyle: const pw.TextStyle(fontSize: 7),
      cellAlignment: pw.Alignment.centerLeft,
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      rowDecoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.3))),
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(2),
      },
      data: [
        ...items.map((p) => [p.method, _currencyFormat.format(p.amount)]),
        ['Total', _currencyFormat.format(grandTotal)],
      ],
    );
  }
}
