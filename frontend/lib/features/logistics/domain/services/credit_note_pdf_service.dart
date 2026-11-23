import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/credit_note_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/models/stock_status.dart';
import 'thermal_template.dart';

/// Credit note / cash sales refund renderer.
///
/// Layout follows `MS Templates/CashSalesRefund and CreditNote Template.txt`
/// on the 68 column, 4.5" (104 mm) Sewoo LK-P43II roll.
class CreditNotePdfService {
  ThermalDoc buildCreditNoteDoc({
    required CreditNoteModel creditNote,
    List<Map<String, dynamic>> resolvedLines = const [],
    Map<String, dynamic>? customer,
    String? salesman,
    String? storeCode,
  }) {
    final d = ThermalDoc();

    final settlement = creditNote.settlementType.toString().toUpperCase();
    final site = creditNote.salesSite.toString();
    final isCreditOnAccount = settlement == 'CREDIT';
    final isCashRefund = !isCreditOnAccount &&
        (creditNote.creditNoteType == CreditNoteType.cashOnly ||
            settlement.contains('REFUND') ||
            settlement == 'CASH');
    final docTitle = isCashRefund ? 'CASH SALES REFUND' : 'CREDIT NOTE';

    DateTime printed;
    try {
      printed = DateTime.parse(creditNote.createdAt);
    } catch (_) {
      printed = DateTime.now();
    }

    d.companyHeader();
    d.center(docTitle, bold: true);
    d.blank();

    final cust = customer ?? const <String, dynamic>{};
    d.meta('Voucher No', creditNote.creditNoteId, bold: true);
    d.meta('Account No', creditNote.customerCode);
    d.meta('Customer\'s Name', creditNote.customerName);
    d.meta('Customer\'s Address', thermalFirst(cust, ['address', 'customerAddress', 'address1']));
    d.meta('VAT Registration No', thermalFirst(cust, ['vatNo', 'vatRegNo', 'vatNumber', 'taxNumber']));
    d.meta('BRN', thermalFirst(cust, ['brn', 'businessRegNo']));
    if (creditNote.originalInvoiceId != null && creditNote.originalInvoiceId!.isNotEmpty) {
      d.meta('Original Invoice', creditNote.originalInvoiceId!);
    }
    if (creditNote.linkedInvoiceIds.isNotEmpty) {
      d.meta('Linked Invoices', creditNote.linkedInvoiceIds.join(', '));
    }
    d.meta('Reason', _formatReason(creditNote.reason ?? ''));
    d.meta('Refund Type', isCreditOnAccount ? 'Credit on Account (MRCRE)' : 'Cash Refund (MRCAS)');
    d.meta('Print Date Time', ThermalDoc.printStamp());
    d.meta('Document Date', DateFormat('dd/MM/yyyy HH:mm').format(printed));
    thermalItemHeader(d);

    // Resolve line figures. Lines may or may not carry VAT; when they don't,
    // VAT is derived from the credit note grand total so columns reconcile.
    final effectiveLines = resolvedLines.isNotEmpty
        ? resolvedLines
        : creditNote.lines
            .map((l) => {
                  'sku': l.sku,
                  'name': l.name.isNotEmpty ? l.name : l.sku,
                  'quantity': l.quantity,
                  'basePrice': l.price,
                  'salesUnit': l.salesUnit,
                  'stockStatus': l.stockStatus,
                })
            .toList();

    final rawRows = effectiveLines.map((l) {
      final qty = (l['quantity'] as num?)?.toDouble() ?? 0.0;
      final price = (l['basePrice'] as num?)?.toDouble() ?? (l['price'] as num?)?.toDouble() ?? 0.0;
      final disc = (l['discountAmount'] as num?)?.toDouble() ?? 0.0;
      final vat = (l['vatAmount'] as num?)?.toDouble();
      final status = StockStatus.fromCode(l['stockStatus']?.toString()).code;
      return _Row(
        code: l['sku']?.toString() ?? '',
        name: l['name']?.toString() ?? l['sku']?.toString() ?? 'Item',
        qty: qty,
        uom: l['salesUnit']?.toString() ?? l['unit']?.toString() ?? 'EA',
        price: price,
        discount: disc,
        vat: vat,
        status: status,
      );
    }).toList();

    final rows = _consolidateRows(rawRows);

    final net = _rowsNet(rows);
    final knownVat = rows.fold<double>(0.0, (s, r) => s + (r.vat ?? 0));
    final derivedVat = rows.any((r) => r.vat == null)
        ? (creditNote.grandTotal - net).clamp(0.0, double.infinity)
        : knownVat;

    double totalDiscount = 0;
    for (final r in rows) {
      final lineNet = r.qty * r.price - r.discount;
      final lineVat = r.vat ??
          (net > 0 ? derivedVat * (lineNet / net) : 0.0);
      totalDiscount += r.discount;
      thermalItemRow(
        d,
        code: r.code,
        description: r.name,
        qty: r.qty,
        uom: r.uom,
        unitPrice: r.price,
        discount: r.discount,
        vat: lineVat,
        total: lineNet + lineVat,
      );
      if (r.status == StockStatus.codeQuarantine) {
        d.line('   [STA: Q - QUARANTINE / EXPIRED]');
      } else if (r.status == StockStatus.codeRejected) {
        d.line('   [STA: R - REJECTED / DAMAGED]');
      }
    }
    d.rule();

    final gross = creditNote.grandTotal + totalDiscount;
    d.total('TOTAL GROSS AMOUNT  :', ThermalDoc.money(gross));
    d.total('TOTAL LINE DISCOUNT :', ThermalDoc.money(totalDiscount));
    d.total('VAT                 :', ThermalDoc.money(derivedVat));
    d.total('NET AMT             :', ThermalDoc.money(creditNote.grandTotal), bold: true);
    d.blank();
    d.line(' SALESMAN : ${salesman ?? creditNote.salesRep ?? ThermalSession.username}');
    d.blank();
    d.line(' Sig:.........................');
    d.blank();
    d.line(' CUSTOMER Sig:..........................');
    d.blank();
    d.line(' STORE : ${storeCode ?? (site.isNotEmpty ? site : ThermalSession.siteCode)}');
    d.blank();
    thermalTerms(d);
    d.blank();
    d.line(' 1 of 1');
    d.blank(2);

    return d;
  }

  Future<Uint8List> generateCreditNotePdf({
    PdfPageFormat? pageFormat, // kept for call-site compatibility (layout is fixed 104 mm)
    required CreditNoteModel creditNote,
    List<Map<String, dynamic>> resolvedLines = const [],
    Map<String, dynamic>? customer,
    String? salesman,
    String? storeCode,
  }) =>
      buildCreditNoteDoc(
        creditNote: creditNote,
        resolvedLines: resolvedLines,
        customer: customer,
        salesman: salesman,
        storeCode: storeCode,
      ).build();

  List<_Row> _consolidateRows(List<_Row> rows) {
    if (rows.length <= 1) return rows;
    final Map<String, List<_Row>> buckets = {};
    final List<String> order = [];
    for (final r in rows) {
      final key = [
        r.code.trim().toUpperCase(),
        r.price.toStringAsFixed(4),
        r.uom.trim().toUpperCase(),
        r.status.trim().toUpperCase(),
      ].join('|');
      final list = buckets[key];
      if (list == null) {
        order.add(key);
        buckets[key] = [r];
      } else {
        list.add(r);
      }
    }
    return order.map((key) {
      final list = buckets[key]!;
      if (list.length == 1) return list.first;
      final first = list.first;
      final sumQty = list.fold<double>(0.0, (s, r) => s + r.qty);
      final sumDisc = list.fold<double>(0.0, (s, r) => s + r.discount);
      final double? sumVat = list.every((r) => r.vat != null)
          ? list.fold<double>(0.0, (s, r) => s + r.vat!)
          : null;
      return _Row(
        code: first.code,
        name: first.name,
        qty: sumQty,
        uom: first.uom,
        price: first.price,
        discount: sumDisc,
        vat: sumVat,
        status: first.status,
      );
    }).toList();
  }

  double _rowsNet(List<_Row> rows) =>
      rows.fold<double>(0.0, (s, r) => s + (r.qty * r.price - r.discount));

  String _formatReason(String reason) {
    const defaultDescriptions = {
      'RET': 'Delivery return',
      'DEF': 'Faulty equipment',
      'MIS': 'Miscellaneous',
      'DNC': 'Not Compliant with shipment',
      'PRI': 'Incorrect price',
      'QTY': 'Quantity error',
      'LTE': 'Late delivery',
      'NOD': 'Not ordered',
      'DSC': 'Discount',
    };
    final trimmed = reason.trim();
    if (defaultDescriptions.containsKey(trimmed.toUpperCase())) {
      return '${defaultDescriptions[trimmed.toUpperCase()]} ($trimmed)';
    }
    return trimmed;
  }
}

class _Row {
  final String code;
  final String name;
  final double qty;
  final String uom;
  final double price;
  final double discount;
  final double? vat;
  final String status;
  _Row({
    required this.code,
    required this.name,
    required this.qty,
    required this.uom,
    required this.price,
    required this.discount,
    required this.vat,
    required this.status,
  });
}
