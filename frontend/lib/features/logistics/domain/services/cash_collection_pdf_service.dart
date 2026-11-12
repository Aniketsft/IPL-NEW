import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'thermal_template.dart';

/// Cash receipt from debtors renderer.
///
/// Layout follows `MS Templates/Receipt From Debtors Template.txt`
/// on the 68 column, 4.5" (104 mm) Sewoo LK-P43II roll.
class CashCollectionPdfService {
  Future<Uint8List> generateCollectionReceiptPdf({
    PdfPageFormat? pageFormat, // kept for call-site compatibility (layout is fixed 104 mm)
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
    String customerAddress = '',
    String customerVatNo = '',
    String customerBrn = '',
  }) async {
    final d = ThermalDoc();

    d.center(company.isNotEmpty ? company : ThermalCompany.name, bold: true);
    d.blank();
    d.line('    Vat Registratrion No      : ${ThermalCompany.vatNo}');
    d.line('    Business Registration No. : ${ThermalCompany.brn}');
    d.blank();
    d.center('CASH RECEIPTS', bold: true);
    d.blank();

    d.meta('Salesman', salesRep.isNotEmpty ? salesRep : ThermalSession.username);
    d.meta('Truck', siteCode.isNotEmpty ? siteCode : ThermalSession.siteCode);
    d.meta('Pay No', receiptRef, bold: true);
    d.meta('Print Date Time', ThermalDoc.printStamp(dateTime));
    d.meta('Customer\'s Code', customerCode);
    d.meta('Customer\'s Name', customerName);
    d.meta('Customer\'s Address', customerAddress);
    d.meta('VAT Registration No', customerVatNo);
    d.meta('BRN', customerBrn);

    d.rule();
    d.line(' ${ThermalDoc.l('Invoice No', 40)}${ThermalDoc.r('Amount', 26)}');
    d.rule();
    for (final doc in settledDocuments) {
      final docNo = (doc['documentNo'] ?? '').toString();
      final docType = (doc['docType'] ?? '').toString().toUpperCase();
      final settled = (doc['settledAmount'] as num?)?.toDouble() ?? 0.0;
      final label = docType.isNotEmpty && docType != 'INV' ? '$docNo ($docType)' : docNo;
      d.line(' ${ThermalDoc.l(label, 40)}${ThermalDoc.r(ThermalDoc.money(settled), 26)}');
    }
    d.rule();
    d.blank();

    final sum = totalCollected.abs();
    d.line(' Received the sum of Rs = ${ThermalDoc.money(sum)}', bold: true);

    // Tender detail (cash / cheque / digital reference) for audit.
    if (isZeroOffset || paymentTenders.isEmpty) {
      d.line(' Settled via Credit Note offset (balance cleared).');
    } else {
      for (final t in paymentTenders) {
        final method = (t['method'] ?? 'CASH').toString().toUpperCase();
        final amount = (t['amount'] as num?)?.toDouble() ?? 0.0;
        d.line(' Paid by ${ThermalDoc.l(method, 14)}${ThermalDoc.r(ThermalDoc.money(amount), 12)}');
        final chequeNo = (t['chequeNumber'] ?? '').toString();
        final bank = (t['bankName'] ?? '').toString();
        final chequeDate = (t['chequeDate'] ?? '').toString();
        final ref = (t['reference'] ?? t['qrTransactionRef'] ?? '').toString();
        if (chequeNo.isNotEmpty || bank.isNotEmpty) {
          d.paragraph('Cheque: $chequeNo Bank: $bank ${chequeDate.isNotEmpty ? 'Date: $chequeDate' : ''}',
              indent: 3);
        }
        if (ref.isNotEmpty) d.paragraph('Ref: $ref', indent: 3);
      }
    }

    d.blank(2);
    d.line(' -------------------------          --------------------------');
    d.line(' SALESMAN\'S SIGNATURE                CUSTOMER\'S SIGNATURE');
    d.blank(2);
    d.line('                 -----------------------------------');
    d.line('                 Name of Signatory in Block Letters');
    d.blank();
    d.rule();
    d.center('Computer Generated Copy');
    d.center('---Thank You/Merci---');
    d.blank(2);

    return d.build();
  }

  /// Receipt for a single historical payment row (reprint).
  Future<Uint8List> generateSingleReceiptPdf({
    PdfPageFormat? pageFormat,
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
      receiptRef: receiptRef,
      customerCode: custNo,
      customerName: thermalFirst(item, ['customerName', 'customerNm', 'name']),
      dateTime: parsedDate,
      salesRep: userName,
      siteCode: siteCode,
      company: company,
      customerAddress: thermalFirst(item, ['customerAddress', 'address']),
      customerVatNo: thermalFirst(item, ['customerVatNo', 'vatNo']),
      customerBrn: thermalFirst(item, ['customerBrn', 'brn']),
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
}
