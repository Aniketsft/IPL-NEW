import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class CashCollectionPdfService {
  final numberFormat = NumberFormat('#,##0.00', 'en_US');

  /// Generates a comprehensive 80mm thermal receipt slip for cash collections
  Future<Uint8List> generateCollectionReceiptPdf({
    required PdfPageFormat pageFormat,
    required String receiptRef,
    required String customerCode,
    required String customerName,
    required DateTime dateTime,
    required String salesRep,
    required String siteCode,
    String company = 'INNODIS LTD',
    required List<Map<String, dynamic>> settledDocuments,
    required List<Map<String, dynamic>> paymentTenders,
    required double totalCollected,
    bool isZeroOffset = false,
  }) async {
    final pdf = pw.Document();

    final format = pageFormat.copyWith(
      height: double.infinity,
      marginTop: 8,
      marginBottom: 8,
      marginLeft: 8,
      marginRight: 8,
    );

    final formattedDate = DateFormat('dd MMM yyyy, HH:mm').format(dateTime);

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        build: (pw.Context context) {
          return pw.Container(
            width: 288, // Standard 80mm roll printable area
            alignment: pw.Alignment.topLeft,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header
                pw.Center(
                  child: pw.Column(
                    children: [
                      pw.Text(
                        company.isNotEmpty ? company : 'INNODIS LTD',
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'OFFICIAL COLLECTION RECEIPT',
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 1),
                      pw.Text(
                        'CASH & RECEIVABLE SETTLEMENT',
                        style: const pw.TextStyle(
                          fontSize: 8,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 8),
                _buildDivider(),

                // Metadata Rows
                _buildMetaRow('Receipt No:', receiptRef, isBold: true),
                _buildMetaRow('Date & Time:', formattedDate),
                if (siteCode.isNotEmpty) _buildMetaRow('Sales Site:', siteCode),
                if (salesRep.isNotEmpty) _buildMetaRow('Collected By:', salesRep),
                _buildMetaRow('Customer Code:', customerCode),
                if (customerName.isNotEmpty)
                  _buildMetaRow('Customer Name:', customerName),

                pw.SizedBox(height: 6),
                _buildDivider(),

                // Section: Settled Documents
                pw.Text(
                  'SETTLED DOCUMENTS',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),

                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      flex: 4,
                      child: pw.Text(
                        'DOCUMENT #',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Text(
                        'DUE (Rs)',
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    pw.Expanded(
                      flex: 3,
                      child: pw.Text(
                        'SETTLED (Rs)',
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 2),
                pw.Container(height: 0.5, color: PdfColors.grey400),
                pw.SizedBox(height: 3),

                ...settledDocuments.map((doc) {
                  final docNo = (doc['documentNo'] ?? '').toString();
                  final docType = (doc['docType'] ?? 'INV').toString();
                  final double due = (doc['originalDue'] as num?)?.toDouble() ?? 0.0;
                  final double settled = (doc['settledAmount'] as num?)?.toDouble() ?? 0.0;

                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          flex: 4,
                          child: pw.Text(
                            '$docNo (${docType.toUpperCase()})',
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                        ),
                        pw.Expanded(
                          flex: 2,
                          child: pw.Text(
                            numberFormat.format(due),
                            textAlign: pw.TextAlign.right,
                            style: const pw.TextStyle(
                              fontSize: 8,
                              color: PdfColors.grey700,
                            ),
                          ),
                        ),
                        pw.Expanded(
                          flex: 3,
                          child: pw.Text(
                            numberFormat.format(settled),
                            textAlign: pw.TextAlign.right,
                            style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                pw.SizedBox(height: 6),
                _buildDivider(),

                // Section: Payment Breakdown (Tenders)
                pw.Text(
                  'PAYMENT TENDERS',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),

                if (isZeroOffset || paymentTenders.isEmpty) ...[
                  _buildMetaRow(
                    'BALANCE OFFSET:',
                    'RS ${numberFormat.format(totalCollected.abs())}',
                    isBold: true,
                  ),
                  pw.Text(
                    'Balance cleared via Credit Note offset.',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                  ),
                ] else ...[
                  ...paymentTenders.map((tender) {
                    final method = (tender['method'] ?? 'CASH').toString().toUpperCase();
                    final double amount = (tender['amount'] as num?)?.toDouble() ?? 0.0;
                    final chequeNo = (tender['chequeNumber'] ?? '').toString();
                    final bankName = (tender['bankName'] ?? '').toString();
                    final chequeDate = (tender['chequeDate'] ?? '').toString();
                    final ref = (tender['reference'] ?? tender['qrTransactionRef'] ?? '').toString();

                    return pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _buildMetaRow(
                          method,
                          'RS ${numberFormat.format(amount)}',
                          isBold: true,
                        ),
                        if (chequeNo.isNotEmpty || bankName.isNotEmpty)
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(left: 6, bottom: 2),
                            child: pw.Text(
                              'Cheque: $chequeNo • Bank: $bankName ${chequeDate.isNotEmpty ? "• Date: $chequeDate" : ""}',
                              style: const pw.TextStyle(
                                fontSize: 7.5,
                                color: PdfColors.grey700,
                              ),
                            ),
                          ),
                        if (ref.isNotEmpty)
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(left: 6, bottom: 2),
                            child: pw.Text(
                              'Ref: $ref',
                              style: const pw.TextStyle(
                                fontSize: 7.5,
                                color: PdfColors.grey700,
                              ),
                            ),
                          ),
                      ],
                    );
                  }),
                ],

                pw.SizedBox(height: 6),
                _buildDivider(),

                // Total Summary
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 4),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'TOTAL SETTLED:',
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        'RS ${numberFormat.format(totalCollected.abs())}',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                _buildDivider(),
                pw.SizedBox(height: 10),

                // Signatures
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Container(
                          width: 100,
                          height: 0.5,
                          color: PdfColors.grey600,
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Customer Signature',
                          style: const pw.TextStyle(fontSize: 7.5),
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Container(
                          width: 100,
                          height: 0.5,
                          color: PdfColors.grey600,
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Sales Rep Signature',
                          style: const pw.TextStyle(fontSize: 7.5),
                        ),
                      ],
                    ),
                  ],
                ),

                pw.SizedBox(height: 12),
                pw.Center(
                  child: pw.Column(
                    children: [
                      pw.Text(
                        'THANK YOU FOR YOUR PAYMENT!',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'OFFLINE SETTLEMENT • PENDING CLOUD SYNC',
                        style: const pw.TextStyle(
                          fontSize: 7,
                          color: PdfColors.grey600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Convenience method to generate a receipt for a single historical payment row
  Future<Uint8List> generateSingleReceiptPdf({
    required PdfPageFormat pageFormat,
    required Map<String, dynamic> item,
  }) async {
    final docNo = item['documentNo']?.toString() ?? '';
    final custNo = item['customerNo']?.toString() ?? '';
    final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
    final method = (item['paymentMethod'] ?? 'CASH').toString().toUpperCase();
    final createdAt = item['createdAt']?.toString() ?? '';
    final userName = item['userName']?.toString() ?? '';
    final chequeNo = item['chequeNumber']?.toString() ?? '';
    final bankName = item['bankName']?.toString() ?? '';
    final chequeDate = item['chequeDate']?.toString() ?? '';
    final qrRef = item['qrTransactionRef']?.toString() ?? '';
    final paymentId = item['paymentId']?.toString() ?? '';
    final siteCode = item['siteCode']?.toString() ?? '';
    final company = item['company']?.toString() ?? 'INNODIS LTD';

    DateTime parsedDate;
    try {
      parsedDate = DateTime.parse(createdAt);
    } catch (_) {
      parsedDate = DateTime.now();
    }

    final receiptRef = paymentId.length > 12
        ? 'REC-${paymentId.substring(0, 10).toUpperCase()}'
        : (paymentId.isNotEmpty ? paymentId : 'REC-${DateTime.now().millisecondsSinceEpoch}');

    return generateCollectionReceiptPdf(
      pageFormat: pageFormat,
      receiptRef: receiptRef,
      customerCode: custNo,
      customerName: '',
      dateTime: parsedDate,
      salesRep: userName,
      siteCode: siteCode,
      company: company,
      settledDocuments: [
        {
          'documentNo': docNo,
          'docType': 'INV',
          'originalDue': amount,
          'settledAmount': amount,
        }
      ],
      paymentTenders: [
        {
          'method': method,
          'amount': amount,
          'chequeNumber': chequeNo,
          'bankName': bankName,
          'chequeDate': chequeDate,
          'reference': qrRef,
        }
      ],
      totalCollected: amount,
      isZeroOffset: method == 'CN_OFFSET',
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
              fontSize: 8.5,
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
                fontSize: 8.5,
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
}
