import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_cart_cubit.dart';

class SalesInvoicePdfService {
  final numberFormat = NumberFormat('#,##0.00', 'en_US');

  Future<Uint8List> generateInvoicePdf({
    required PdfPageFormat pageFormat,
    required String invoiceId,
    required Map<String, dynamic> customer,
    required List<CartItem> items,
    required double subtotal,
    required double discountAmount,
    required double vatAmount,
    required double grandTotal,
    required String paymentMethod,
    required String paymentStatus,
    bool isPartiallyReversed = false,
    double creditedAmount = 0.0,
    double netBalanceDue = 0.0,
  }) async {
    final pdf = pw.Document();

    final format = pageFormat.copyWith(
      height: double.infinity,
      marginTop: 10,
      marginBottom: 10,
      marginLeft: 10,
      marginRight: 10,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        build: (pw.Context context) {
          return pw.Container(
            width: 288,
            alignment: pw.Alignment.topLeft,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildHeader(isPartiallyReversed: isPartiallyReversed),
                pw.SizedBox(height: 10),
                _buildMetadata(
                  invoiceId: invoiceId,
                  customer: customer,
                  paymentMethod: paymentMethod,
                  paymentStatus: isPartiallyReversed ? 'PAID (PARTIAL REV)' : paymentStatus,
                ),
                pw.SizedBox(height: 10),
                _buildDivider(),
                pw.SizedBox(height: 5),
                _buildLineItems(items),
                pw.SizedBox(height: 5),
                _buildTotals(
                  subtotal: subtotal,
                  discountAmount: discountAmount,
                  vatAmount: vatAmount,
                  grandTotal: grandTotal,
                  isPartiallyReversed: isPartiallyReversed,
                  creditedAmount: creditedAmount,
                  netBalanceDue: netBalanceDue,
                ),
                pw.SizedBox(height: 15),
                _buildFooter(),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildHeader({bool isPartiallyReversed = false}) {
    return pw.Center(
      child: pw.Column(
        children: [
          pw.Text(
            'INNODIS',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Sales Invoice',
            style: const pw.TextStyle(
              fontSize: 12,
            ),
          ),
          if (isPartiallyReversed) ...[
            pw.SizedBox(height: 4),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.orange800, width: 1),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
              ),
              child: pw.Text(
                '*** PARTIALLY REVERSED ***',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.orange800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  pw.Widget _buildMetadata({
    required String invoiceId,
    required Map<String, dynamic> customer,
    required String paymentMethod,
    required String paymentStatus,
  }) {
    final dateStr = DateFormat('MMM dd, yyyy').format(DateTime.now());
    final customerName = customer['name']?.toString() ?? 'Unknown';
    final customerCode = customer['code']?.toString() ?? '';

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildMetaRow('Invoice#', invoiceId),
        _buildMetaRow('Date', dateStr),
        _buildMetaRow('Customer', customerName),
        _buildMetaRow('Cust. Code', customerCode),
        _buildMetaRow('Pay. Method', paymentMethod),
        _buildMetaRow('Status', paymentStatus),
      ],
    );
  }

  pw.Widget _buildMetaRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 70,
            child: pw.Text(
              label,
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Text(' : ', style: const pw.TextStyle(fontSize: 10)),
          pw.Expanded(
            child: pw.Text(
              value,
              style: const pw.TextStyle(fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildDivider() {
    return pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed);
  }

  pw.Widget _buildLineItems(List<CartItem> items) {
    return pw.Column(
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              flex: 4,
              child: pw.Text(
                'ITEM',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Expanded(
              flex: 1,
              child: pw.Text(
                'QTY',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Expanded(
              flex: 2,
              child: pw.Text(
                'TOTAL (Rs)',
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 5),
        _buildDivider(),
        pw.SizedBox(height: 5),
        ...items.map((item) {
          return pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 3),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 4,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        item.product.name,
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                      pw.Text(
                        '${item.quantity.toStringAsFixed(0)} ${item.product.salesUnit} x ${numberFormat.format(item.basePrice)}',
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.grey600,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Expanded(
                  flex: 1,
                  child: pw.Text(
                    '${item.quantity.toStringAsFixed(0)} ${item.product.salesUnit}',
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ),
                pw.Expanded(
                  flex: 2,
                  child: pw.Text(
                    numberFormat.format(item.total),
                    textAlign: pw.TextAlign.right,
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  pw.Widget _buildTotals({
    required double subtotal,
    required double discountAmount,
    required double vatAmount,
    required double grandTotal,
    bool isPartiallyReversed = false,
    double creditedAmount = 0.0,
    double netBalanceDue = 0.0,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        _buildDivider(),
        pw.SizedBox(height: 5),
        _buildTotalRow('Subtotal', subtotal),
        _buildTotalRow('Discount', discountAmount, isDiscount: true),
        _buildTotalRow('VAT', vatAmount),
        if (isPartiallyReversed) ...[
          _buildTotalRow('Less Credited', creditedAmount, isDiscount: true),
          _buildTotalRow('Net Balance Due', netBalanceDue),
        ],
        pw.SizedBox(height: 5),
        _buildDivider(),
        pw.SizedBox(height: 5),
        pw.Center(
          child: pw.Column(
            children: [
              pw.Text(
                isPartiallyReversed ? 'NET BALANCE DUE (Rs)' : 'GRAND TOTAL (Rs)',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                numberFormat.format(isPartiallyReversed ? netBalanceDue : grandTotal),
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
              if (isPartiallyReversed) ...[
                pw.SizedBox(height: 2),
                pw.Text(
                  '(Original Grand Total: Rs ${numberFormat.format(grandTotal)})',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _buildTotalRow(String label, double value, {bool isDiscount = false}) {
    final formattedValue = isDiscount ? '-${numberFormat.format(value)}' : numberFormat.format(value);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          pw.Text(
            '$label: ',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.SizedBox(
            width: 60,
            child: pw.Text(
              formattedValue,
              textAlign: pw.TextAlign.right,
              style: const pw.TextStyle(fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildFooter() {
    final printTime = DateFormat('HH:mm MMM dd').format(DateTime.now());
    return pw.Center(
      child: pw.Column(
        children: [
          _buildDivider(),
          pw.SizedBox(height: 5),
          pw.Text(
            'Thank you for your business!',
            style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Printed: $printTime',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }
}
