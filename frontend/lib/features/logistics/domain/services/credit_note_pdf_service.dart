import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:enterprise_auth_mobile/features/logistics/data/models/credit_note_model.dart';

class CreditNotePdfService {
  final currencyFormat = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'RS ',
    decimalDigits: 2,
  );

  Future<Uint8List> generateCreditNotePdf({
    required PdfPageFormat pageFormat,
    required CreditNoteModel creditNote,
    List<Map<String, dynamic>> resolvedLines = const [],
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
                _buildHeader(),
                pw.SizedBox(height: 10),
                _buildMetadata(creditNote),
                pw.SizedBox(height: 10),
                _buildDivider(),
                pw.SizedBox(height: 5),
                if (resolvedLines.isNotEmpty) ...[
                  _buildLineItems(resolvedLines),
                  pw.SizedBox(height: 5),
                ],
                _buildTotals(creditNote),
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

  pw.Widget _buildHeader() {
    return pw.Center(
      child: pw.Column(
        children: [
          pw.Text(
            'INNODIS LTD',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'CREDIT NOTE / RETURN VOUCHER',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Official Commercial Return',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildMetadata(CreditNoteModel creditNote) {
    DateTime parsedDate;
    try {
      parsedDate = DateTime.parse(creditNote.createdAt);
    } catch (_) {
      parsedDate = DateTime.now();
    }
    final formattedDate = DateFormat('dd MMM yyyy, HH:mm').format(parsedDate);

    String typeLabel = 'REVERSAL';
    if (creditNote.creditNoteType == CreditNoteType.standalone) {
      typeLabel = 'STANDALONE RETURN';
    } else if (creditNote.creditNoteType == CreditNoteType.cashOnly) {
      typeLabel = 'AMOUNT ONLY REFUND';
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildMetaRow('Credit Note #:', creditNote.creditNoteId, isBold: true),
        _buildMetaRow('Date:', formattedDate),
        _buildMetaRow('Type:', typeLabel),
        if (creditNote.originalInvoiceId != null && creditNote.originalInvoiceId!.isNotEmpty)
          _buildMetaRow('Origin Invoice:', creditNote.originalInvoiceId!),
        if (creditNote.linkedInvoiceIds.isNotEmpty)
          _buildMetaRow('Linked Invoices:', creditNote.linkedInvoiceIds.join(', ')),
        pw.SizedBox(height: 4),
        _buildMetaRow('Customer Code:', creditNote.customerCode),
        _buildMetaRow('Customer Name:', creditNote.customerName),
        _buildMetaRow('Refund Method:', creditNote.settlementType, isBold: true),
        if (creditNote.x3DocumentId != null && creditNote.x3DocumentId!.isNotEmpty)
          _buildMetaRow('Sage X3 Doc #:', creditNote.x3DocumentId!),
      ],
    );
  }

  pw.Widget _buildMetaRow(String label, String value, {bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey700,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Text(
              value,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildDivider() {
    return pw.Container(
      height: 1,
      color: PdfColors.grey400,
      margin: const pw.EdgeInsets.symmetric(vertical: 4),
    );
  }

  pw.Widget _buildLineItems(List<Map<String, dynamic>> lines) {
    return pw.Column(
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              flex: 4,
              child: pw.Text(
                'RETURNED ITEM',
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Expanded(
              flex: 1,
              child: pw.Text(
                'QTY',
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Expanded(
              flex: 2,
              child: pw.Text(
                'TOTAL',
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 3),
        _buildDivider(),
        pw.SizedBox(height: 3),
        ...lines.map((line) {
          final name = line['name']?.toString() ?? line['sku']?.toString() ?? 'Item';
          final qty = (line['quantity'] as num?)?.toDouble() ?? 0.0;
          final price = (line['basePrice'] as num?)?.toDouble() ?? 0.0;
          final lineTotal = qty * price;

          return pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 4,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        name,
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                      pw.Text(
                        '${qty.toStringAsFixed(0)} x ${currencyFormat.format(price)}',
                        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                      ),
                    ],
                  ),
                ),
                pw.Expanded(
                  flex: 1,
                  child: pw.Text(
                    qty.toStringAsFixed(0),
                    textAlign: pw.TextAlign.right,
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ),
                pw.Expanded(
                  flex: 2,
                  child: pw.Text(
                    currencyFormat.format(lineTotal),
                    textAlign: pw.TextAlign.right,
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  pw.Widget _buildTotals(CreditNoteModel creditNote) {
    return pw.Column(
      children: [
        _buildDivider(),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'TOTAL REFUND:',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              currencyFormat.format(creditNote.grandTotal),
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildFooter() {
    return pw.Center(
      child: pw.Column(
        children: [
          pw.Text(
            'Goods received and restocked.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 15),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              pw.Column(
                children: [
                  pw.Container(width: 80, height: 1, color: PdfColors.black),
                  pw.SizedBox(height: 2),
                  pw.Text('Customer Signature', style: const pw.TextStyle(fontSize: 7)),
                ],
              ),
              pw.Column(
                children: [
                  pw.Container(width: 80, height: 1, color: PdfColors.black),
                  pw.SizedBox(height: 2),
                  pw.Text('Rep Signature', style: const pw.TextStyle(fontSize: 7)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Thank you for your business.',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }
}
