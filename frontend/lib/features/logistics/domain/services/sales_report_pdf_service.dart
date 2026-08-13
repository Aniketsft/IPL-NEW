import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/transaction_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/sales_invoice_product_model.dart';

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
}
