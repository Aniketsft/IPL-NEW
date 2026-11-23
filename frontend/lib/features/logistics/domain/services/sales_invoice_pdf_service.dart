import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_cart_cubit.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/credit_note_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/models/stock_status.dart';
import 'thermal_template.dart';

/// Tax invoice (cash / credit) renderer.
///
/// Layout follows `MS Templates/Invoice  Credit and CashTemplate.txt`
/// on the 68 column, 4.5" (104 mm) Sewoo LK-P43II roll.
class SalesInvoicePdfService {
  /// `true` when the payment method / status denotes sale on credit terms.
  static bool isCreditSale(String paymentMethod, String paymentStatus) {
    final m = paymentMethod.trim().toUpperCase();
    final s = paymentStatus.trim().toUpperCase();
    if (m.contains('CREDIT') || m.contains('TERM') || m.contains('ACCOUNT')) return true;
    if (RegExp(r'^(CH)?\d{1,3}D?$').hasMatch(m) && m.isNotEmpty) return true;
    if (s.contains('UNPAID') || s.contains('PENDING') || s.contains('CREDIT')) return true;
    return false;
  }

  ThermalDoc buildInvoiceDoc({
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
    String? salesman,
    String? storeCode,
    DateTime? printedAt,
  }) {
    final d = ThermalDoc();
    final credit = isCreditSale(paymentMethod, paymentStatus);

    d.companyHeader();
    d.center('${credit ? 'CREDIT' : 'CASH'} SALES', bold: true);
    d.center('VAT INVOICE', bold: true);
    if (isPartiallyReversed) d.center('*** PARTIALLY REVERSED ***', bold: true);
    d.blank();

    d.meta('Voucher No', invoiceId, bold: true);
    d.meta('Account No', thermalFirst(customer, ['code', 'customerCode', 'customerNo']));
    d.meta('Customer\'s Name', thermalFirst(customer, ['name', 'customerName'], 'Unknown'));
    d.meta('Customer\'s Address',
        thermalFirst(customer, ['address', 'customerAddress', 'address1', 'addr']));
    d.meta('VAT Registration No',
        thermalFirst(customer, ['vatNo', 'vatRegNo', 'vatNumber', 'taxNumber', 'vat']));
    d.meta('BRN', thermalFirst(customer, ['brn', 'businessRegNo', 'businessRegistrationNo']));
    d.meta('Print Date Time', ThermalDoc.printStamp(printedAt));
    thermalItemHeader(d);

    for (final group in consolidateCartItemsForDisplay(items)) {
      final item = group.displayItem;
      thermalItemRow(
        d,
        code: item.product.sku,
        description: item.product.name,
        qty: item.quantity,
        uom: item.product.salesUnit,
        unitPrice: item.basePrice,
        discount: group.totalDiscountAmount,
        vat: group.totalVatAmount,
        total: group.totalAmount,
      );
    }
    d.rule();

    // GROSS = amount incl. VAT before line discount, so GROSS - DISCOUNT = NET.
    final gross = grandTotal + discountAmount;
    d.total('TOTAL GROSS AMOUNT  :', ThermalDoc.money(gross));
    d.total('TOTAL LINE DISCOUNT :', ThermalDoc.money(discountAmount));
    d.total('VAT                 :', ThermalDoc.money(vatAmount));
    d.total('NET AMT             :', ThermalDoc.money(grandTotal), bold: true);
    if (isPartiallyReversed) {
      d.total('LESS CREDITED       :', ThermalDoc.money(creditedAmount));
      d.total('NET BALANCE DUE     :', ThermalDoc.money(netBalanceDue), bold: true);
    }
    d.blank();

    d.line(' SALESMAN : ${salesman ?? thermalFirst(customer, ['salesRep', 'salesman'], ThermalSession.username)}');
    d.blank();
    d.line(' STORE : ${storeCode ?? thermalFirst(customer, ['storeCode', 'siteCode'], ThermalSession.siteCode)}');
    d.blank();
    d.line(' Sig:.........................');
    d.blank();
    d.line(' CUSTOMER Sig:..........................');
    d.blank();
    thermalTerms(d);
    d.blank(2);

    return d;
  }

  Future<Uint8List> generateInvoicePdf({
    PdfPageFormat? pageFormat, // kept for call-site compatibility (layout is fixed 104 mm)
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
    String? qrCodeBase64, // legacy, not printed on the template
    String? salesman,
    String? storeCode,
    DateTime? printedAt,
  }) =>
      buildInvoiceDoc(
        invoiceId: invoiceId,
        customer: customer,
        items: items,
        subtotal: subtotal,
        discountAmount: discountAmount,
        vatAmount: vatAmount,
        grandTotal: grandTotal,
        paymentMethod: paymentMethod,
        paymentStatus: paymentStatus,
        isPartiallyReversed: isPartiallyReversed,
        creditedAmount: creditedAmount,
        netBalanceDue: netBalanceDue,
        salesman: salesman,
        storeCode: storeCode,
        printedAt: printedAt,
      ).build();

  /// Customer goods return voucher (A / R / Q status receipt).
  Future<Uint8List> generateCustomerReturnPdf({
    PdfPageFormat? pageFormat,
    required CreditNoteModel returnModel,
  }) async {
    final d = ThermalDoc();

    final active = returnModel.lines
        .where((l) => StockStatus.fromCode(l.stockStatus) == StockStatus.approved)
        .toList();
    final damaged = returnModel.lines
        .where((l) => StockStatus.fromCode(l.stockStatus) == StockStatus.rejected)
        .toList();
    final quarantine = returnModel.lines
        .where((l) => StockStatus.fromCode(l.stockStatus) == StockStatus.quarantine)
        .toList();
    final totalUnits = returnModel.lines.fold(0.0, (s, i) => s + i.quantity);

    d.companyHeader();
    d.center('CUSTOMER GOODS RETURN VOUCHER', bold: true);
    d.center('STATUS BREAKDOWN (A / R / Q)');
    d.blank();
    d.meta('Return No', returnModel.creditNoteId, bold: true);
    d.meta('Account No', returnModel.customerCode);
    d.meta('Customer\'s Name', returnModel.customerName);
    d.meta('Print Date Time', ThermalDoc.printStamp());
    d.meta('Site', returnModel.salesSite);
    d.meta('Salesman', returnModel.salesRep ?? ThermalSession.username);
    if (returnModel.originalInvoiceId != null && returnModel.originalInvoiceId!.isNotEmpty) {
      d.meta('Original Invoice', returnModel.originalInvoiceId!);
    }
    d.meta('Settlement', returnModel.settlementType, bold: true);

    void section(String title, String statusCode, List<CreditNoteLineModel> lines) {
      if (lines.isEmpty) return;
      final showReason = statusCode != StockStatus.codeApproved;
      d.rule();
      d.line(' $title', bold: true);
      thermalItemHeader(d);

      final Map<String, CreditNoteLineModel> grouped = {};
      final List<String> order = [];
      for (final line in lines) {
        final key = [
          line.sku.trim().toUpperCase(),
          line.price.toStringAsFixed(4),
          line.salesUnit.trim().toUpperCase(),
          (line.returnCondition ?? '').trim().toUpperCase(),
        ].join('|');
        final existing = grouped[key];
        if (existing == null) {
          order.add(key);
          grouped[key] = line;
        } else {
          grouped[key] = CreditNoteLineModel(
            creditNoteId: existing.creditNoteId,
            lineNo: existing.lineNo,
            quantity: existing.quantity + line.quantity,
            standaloneSku: existing.sku,
            standaloneName: existing.name.isNotEmpty ? existing.name : line.name,
            standaloneSalesUnit: existing.salesUnit,
            standalonePrice: existing.price,
            stockStatus: existing.stockStatus,
            returnCondition: existing.returnCondition,
          );
        }
      }

      double sum = 0;
      for (final key in order) {
        final i = grouped[key]!;
        final total = i.quantity * i.price;
        sum += total;
        thermalItemRow(
          d,
          code: i.sku,
          description: i.name.isNotEmpty ? i.name : i.sku,
          qty: i.quantity,
          uom: i.salesUnit,
          unitPrice: i.price,
          discount: 0,
          vat: 0,
          total: total,
        );
        if (showReason && i.returnCondition != null && i.returnCondition!.isNotEmpty) {
          d.line('   >> Reason: ${i.returnCondition}');
        }
      }
      d.total('SUBTOTAL ($statusCode)      :', ThermalDoc.money(sum), bold: true);
    }

    section('SECTION 1: SALABLE / GOOD STOCK (STATUS A)', StockStatus.codeApproved, active);
    section('SECTION 2: DAMAGED / REJECTED STOCK (STATUS R)', StockStatus.codeRejected, damaged);
    section('SECTION 3: QUARANTINE / EXPIRED (STATUS Q)', StockStatus.codeQuarantine, quarantine);

    d.rule();
    d.total('TOTAL RETURNED QTY  :', ThermalDoc.qty(totalUnits));
    d.total('TOTAL REFUND VALUE  :', ThermalDoc.money(returnModel.grandTotal), bold: true);
    d.blank();
    d.line(' Sage X3 Audit:');
    d.line('  Credit Note (ZSCRWEB)  : ${returnModel.x3DocumentId ?? 'Pending Sync'}');
    d.line('  Stock Receipt (ZSMRWEBA): ${returnModel.x3StockReceiptId ?? 'Pending Sync'}');
    if (returnModel.x3RefundPaymentId != null && returnModel.x3RefundPaymentId!.isNotEmpty) {
      d.line('  Refund Voucher (ZPAYWEBA): ${returnModel.x3RefundPaymentId}');
    }
    d.blank();
    d.line(' Sig:.........................');
    d.blank();
    d.line(' CUSTOMER Sig:..........................');
    d.blank(2);

    return d.build();
  }
}
