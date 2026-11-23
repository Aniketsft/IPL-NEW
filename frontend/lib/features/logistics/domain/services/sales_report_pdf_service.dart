import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/transaction_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/sales_invoice_product_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/eod_report_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/models/stock_status.dart';
import 'thermal_template.dart';

/// Management reports for the 4.5" (104 mm) Sewoo LK-P43II roll.
///
/// * Sales Summary   -> `MS Templates/Sales Summary Template.txt`
/// * Stock Preview   -> `MS Templates/Inventory Template.txt`
/// * End of Day      -> `MS Templates/Daily Cash collection Template.txt`
class SalesReportPdfService {
  // ═══════════════════════════════════════════════════════════════════════
  // SALES SUMMARY
  // ═══════════════════════════════════════════════════════════════════════

  /// [productRows] come from `TransactionHistoryRepository.getSalesSummaryRows`
  /// (`sku`, `name`, `uom`, `salesQty`, `returnQty`, `salesValue`, `returnValue`).
  Future<Uint8List> generateInvoiceSummaryPdf({
    required List<TransactionModel> invoices,
    required String reportDate,
    List<Map<String, dynamic>> productRows = const [],
    String? salesman,
    String? storeCode,
  }) async {
    final d = ThermalDoc();

    d.companyHeader();
    d.line(' Salesman  : ${salesman ?? ThermalSession.username}');
    d.line(' Store     : ${storeCode ?? ThermalSession.siteCode}');
    d.blank();
    d.center('SALES SUMMARY', bold: true);
    d.blank();
    d.meta('Report Date', reportDate);
    d.meta('Print Date Time', ThermalDoc.printStamp());
    d.rule();
    d.line(' ${ThermalDoc.l('Description', 29)}${ThermalDoc.r('Sales', 12)}'
        '${ThermalDoc.r('Returns', 13)}${ThermalDoc.r('Net_Qty', 12)}');
    d.rule();

    double totalValue = 0;
    double retA = 0.0;
    double retR = 0.0;
    double retQ = 0.0;
    double valA = 0.0;
    double valR = 0.0;
    double valQ = 0.0;
    if (productRows.isNotEmpty) {
      for (final r in productRows) {
        final sales = (r['salesQty'] as num?)?.toDouble() ?? 0.0;
        final ret = (r['returnQty'] as num?)?.toDouble() ?? 0.0;
        final rowRetA = (r['returnQtyA'] as num?)?.toDouble() ?? 0.0;
        final rowRetR = (r['returnQtyR'] as num?)?.toDouble() ?? 0.0;
        final rowRetQ = (r['returnQtyQ'] as num?)?.toDouble() ?? 0.0;
        retA += rowRetA;
        retR += rowRetR;
        retQ += rowRetQ;
        valA += (r['returnValueA'] as num?)?.toDouble() ?? 0.0;
        valR += (r['returnValueR'] as num?)?.toDouble() ?? 0.0;
        valQ += (r['returnValueQ'] as num?)?.toDouble() ?? 0.0;
        final uom = (r['uom'] ?? '').toString();
        final name = (r['name'] ?? '').toString();
        totalValue += ((r['salesValue'] as num?)?.toDouble() ?? 0.0) -
            ((r['returnValue'] as num?)?.toDouble() ?? 0.0);
        d.line(' ProdCode :  ${ThermalDoc.clean(r['sku']?.toString())}');
        final nameLines = ThermalDoc.wrap(name, 29);
        d.line(' ${ThermalDoc.l(nameLines.first, 29)}'
            '${ThermalDoc.r('${ThermalDoc.qty(sales)}${uom.isEmpty ? '' : '($uom)'}', 12)}'
            '${ThermalDoc.r(ThermalDoc.qty(ret), 13)}'
            '${ThermalDoc.r(ThermalDoc.qty(sales - ret), 12)}');
        for (final extra in nameLines.skip(1)) {
          d.line(' $extra');
        }
        if (ret > 0.0001 && (rowRetA > 0 || rowRetR > 0 || rowRetQ > 0)) {
          final parts = <String>[
            if (rowRetA > 0) 'A:${ThermalDoc.qty(rowRetA)}',
            if (rowRetR > 0) 'R:${ThermalDoc.qty(rowRetR)}',
            if (rowRetQ > 0) 'Q:${ThermalDoc.qty(rowRetQ)}',
          ];
          d.line('   Return Sta: ${parts.join('  ')}');
        }
      }
    } else {
      d.line(' No product movement recorded for this date.');
      totalValue = invoices
          .where((i) => i.type == 'INVOICE' && i.isReversed == 0)
          .fold(0.0, (s, i) => s + i.grandTotal);
    }

    d.rule();
    d.line(' ${ThermalDoc.l('TOTAL PRICE', 40)}${ThermalDoc.r(ThermalDoc.money(totalValue), 26)}',
        bold: true);
    d.blank();
    if (retA > 0 || retR > 0 || retQ > 0) {
      d.line(' Return Breakdown by Status:', bold: true);
      d.line('   ${ThermalDoc.l('[A] Normal / Sellable', 36)}${ThermalDoc.r('${ThermalDoc.qty(retA)} (${ThermalDoc.money(valA)})', 28)}');
      d.line('   ${ThermalDoc.l('[R] Damaged', 36)}${ThermalDoc.r('${ThermalDoc.qty(retR)} (${ThermalDoc.money(valR)})', 28)}');
      d.line('   ${ThermalDoc.l('[Q] Expired / Quarantine', 36)}${ThermalDoc.r('${ThermalDoc.qty(retQ)} (${ThermalDoc.money(valQ)})', 28)}');
      d.blank();
    }
    final invCount = invoices.where((i) => i.type == 'INVOICE').length;
    final retCount = invoices.where((i) => i.type == 'RETURN').length;
    final cnCount = invoices.where((i) => i.type == 'CREDIT_NOTE').length;
    d.line(' Invoices: $invCount   Returns: $retCount   Credit Notes: $cnCount');
    d.blank(2);

    return d.build();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // STOCK PREVIEW (INVENTORY)
  // ═══════════════════════════════════════════════════════════════════════

  Future<Uint8List> generateStockPreviewPdf({
    required List<SalesInvoiceProductModel> items,
    required String warehouseLabel,
    String? salesman,
    String? reportDate,
    bool isHistoricalDate = false,
  }) async {
    final d = ThermalDoc();
    final stamp = DateFormat('yyyyMMddHHmm').format(DateTime.now());
    final effectiveReportDate = (reportDate != null && reportDate.isNotEmpty)
        ? reportDate
        : DateFormat('dd MMM yyyy').format(DateTime.now());

    d.center(ThermalCompany.name, bold: true);
    d.blank();
    d.line(' VAT : ${ThermalCompany.vatNo}');
    d.line(' BRN : ${ThermalCompany.brn}');
    d.center(ThermalCompany.division, bold: true);
    for (final a in ThermalCompany.addressLines) {
      d.center(a);
    }
    d.blank();
    d.center('VAN STOCK PREVIEW', bold: true);
    d.blank();
    d.meta('Voucher No', 'STK-$stamp', labelWidth: 17);
    d.meta('Store', warehouseLabel, labelWidth: 17);
    d.meta('Salesman', salesman ?? ThermalSession.username, labelWidth: 17);
    d.meta('Report Date', effectiveReportDate, labelWidth: 17);
    d.meta('Print Date Time', ThermalDoc.printStamp(), labelWidth: 17);
    if (isHistoricalDate) {
      d.line(' Note: Van stock reflects live synced device inventory.');
    }

    void section(String title, String status) {
      final list = items
          .where((i) => StockStatus.fromCode(i.stockStatus).code == status)
          .toList();
      d.rule();
      d.line(' $title', bold: true);
      d.rule();
      d.line(' ${ThermalDoc.l('CODE', 14)}${ThermalDoc.l('DESCRIPTION', 38)}${ThermalDoc.r('QTY', 14)}');
      d.rule();
      if (list.isEmpty) {
        d.line(' (none)');
        return;
      }
      double units = 0;
      for (final i in list) {
        units += i.stockQty;
        final descLines = ThermalDoc.wrap(i.name, 38);
        d.line(' ${ThermalDoc.l(i.sku, 14)}${ThermalDoc.l(descLines.first, 38)}'
            '${ThermalDoc.r('${ThermalDoc.qty(i.stockQty)}(${i.salesUnit})', 14)}');
        for (final extra in descLines.skip(1)) {
          d.line(' ${' ' * 14}$extra');
        }
      }
      d.line(' ${ThermalDoc.l('SUBTOTAL', 52)}${ThermalDoc.r(ThermalDoc.qty(units), 14)}', bold: true);
    }

    section('[A] APPROVED / SELLABLE STOCK', 'A');
    section('[R] DAMAGED / REJECTED STOCK', 'R');
    section('[Q] QUARANTINE / EXPIRED STOCK', 'Q');

    final totalUnits = items.fold(0.0, (s, i) => s + i.stockQty);
    d.rule();
    d.line(' ${ThermalDoc.l('TOTAL PHYSICAL STOCK (${items.map((i) => i.sku).toSet().length} SKUs)', 52)}'
        '${ThermalDoc.r(ThermalDoc.qty(totalUnits), 14)}',
        bold: true);
    d.rule();
    d.line(' Salesman: ${salesman ?? ThermalSession.username}');
    d.blank();
    d.line(' Signature: ........................');
    d.blank();
    d.line(' Stock Controller Name     : .........................');
    d.blank();
    d.line(' Stock Controller Signature: .........................');
    d.blank(2);

    return d.build();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // END OF DAY - DAILY CASH COLLECTION REPORT
  // ═══════════════════════════════════════════════════════════════════════

  static String _receiptNo(String paymentId) => paymentId.length > 12
      ? 'REC-${paymentId.substring(0, 10).toUpperCase()}'
      : paymentId;

  String _sectionRange(String from, String to) {
    if (from.isEmpty && to.isEmpty) return ' FROM: -  TO: -';
    return ' FROM: $from  TO: $to';
  }

  void _slipBlock(ThermalDoc d, String title, String range, double amount) {
    d.center(title, bold: true);
    d.paragraph(range.trim(), indent: 1);
    d.line(ThermalDoc.r(ThermalDoc.money(amount), ThermalDoc.cols - 2));
    d.blank();
  }

  Future<Uint8List> generateEodReportPdf(EodReportModel data) async {
    final d = ThermalDoc();

    d.center(ThermalCompany.name, bold: true);
    d.blank();
    d.line('    DAILY CASH COLLECTION REPORT @ ${data.reportDate}', bold: true);
    d.rule();
    d.line(' ${ThermalDoc.l('Please receive the following slips', 48)}${ThermalDoc.r('Amount', 18)}');
    d.rule();

    // Cash from debtors (receipts)
    final collections = [...data.openInvoiceCollections]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    _slipBlock(
      d,
      'CASH FROM DEBTORS',
      collections.isEmpty
          ? _sectionRange('', '')
          : _sectionRange(_receiptNo(collections.first.paymentId), _receiptNo(collections.last.paymentId)),
      data.totalOpenCollectionsAmount,
    );

    // Cash sales invoices
    final cash = [...data.cashInvoices]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    _slipBlock(
      d,
      'CASH SALES INVOICES',
      cash.isEmpty ? _sectionRange('', '') : _sectionRange(cash.first.invoiceId, cash.last.invoiceId),
      data.totalCashInvoicesAmount,
    );

    // Cash sales refunds (credit notes settled in cash)
    final cashRefund = data.cashRefundedOnReturns;
    _slipBlock(
      d,
      'CASH SALES REFUND',
      ' ${data.returnsCount} return document(s) today',
      cashRefund,
    );

    final netInvoiceCash = data.totalCashInvoicesAmount - cashRefund;
    d.rule();
    d.line(' ${ThermalDoc.l('TOTAL', 48)}${ThermalDoc.r(ThermalDoc.money(netInvoiceCash), 18)}', bold: true);
    d.rule();

    // Credit sales invoices
    final credit = [...data.creditInvoices]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    _slipBlock(
      d,
      'CREDIT SALES INVOICES',
      credit.isEmpty ? _sectionRange('', '') : _sectionRange(credit.first.invoiceId, credit.last.invoiceId),
      data.totalCreditInvoicesAmount,
    );

    // Credit notes on account
    final creditNoteTotal = (data.returnsGross - cashRefund).clamp(0.0, double.infinity);
    _slipBlock(
      d,
      'CREDIT NOTE INVOICES',
      ' ${data.returnsCount} return document(s) today',
      creditNoteTotal,
    );

    if (data.returnStatusBreakdowns.isNotEmpty) {
      d.line(' RETURNS BY STOCK STATUS:', bold: true);
      for (final b in data.returnStatusBreakdowns) {
        final st = StockStatus.fromCode(b.stockStatus);
        final statusLabel = switch (st) {
          StockStatus.approved => 'Normal / Sellable',
          StockStatus.rejected => 'Damaged / Rejected',
          StockStatus.quarantine => 'Expired / Quarantine',
        };
        final left = '   [${st.code}] $statusLabel (${ThermalDoc.qty(b.totalQty)})';
        d.line(' ${ThermalDoc.l(left, 48)}${ThermalDoc.r(ThermalDoc.money(b.totalAmount), 18)}');
      }
      d.blank();
    }

    // Cash hand-over
    final cashReceived = data.totalPhysicalCashReceived;
    final netCash = data.netPhysicalCashInHand;
    final cashToHandOver = data.physicalCashToHandOver;
    d.rule();
    d.line(' ${ThermalDoc.l('PLEASE RECEIVE THE FOLLOWING CASH', 48)}${ThermalDoc.r('Amount', 18)}');
    d.line(' ${ThermalDoc.l('CASH RECEIVED', 48)}${ThermalDoc.r(ThermalDoc.money(cashReceived), 18)}');
    d.line(' ${ThermalDoc.l('CASH SALES REFUNDS', 48)}${ThermalDoc.r(ThermalDoc.money(cashRefund), 18)}');
    d.line(' ${' ' * 48}${'-' * 18}');
    d.line(' ${ThermalDoc.l('NET CASH IN HAND', 48)}${ThermalDoc.r(ThermalDoc.money(netCash), 18)}', bold: true);
    if (netCash < -0.005) {
      d.line(' ${ThermalDoc.l('CASH SHORTFALL (OWED TO SALESMAN)', 48)}${ThermalDoc.r(ThermalDoc.money(netCash.abs()), 18)}', bold: true);
    }
    d.blank();
    d.line(' NOTES .................');
    d.blank();
    d.line(' COINS .................');
    d.blank();
    d.line(' ${ThermalDoc.l('CHEQUES ...............', 48)}${ThermalDoc.r(ThermalDoc.money(data.totalChequesAmount), 18)}');
    if (data.chequeList.isNotEmpty) {
      for (final c in data.chequeList) {
        final bank = c.bankName.isNotEmpty ? c.bankName : 'BANK';
        d.line(
            '   #${ThermalDoc.l(c.chequeNumber.isEmpty ? 'N/A' : c.chequeNumber, 12)}'
            '${ThermalDoc.l(bank, 22)}${ThermalDoc.r(ThermalDoc.money(c.amount), 18)}');
      }
    }
    d.rule();
    d.line(' ${ThermalDoc.l('TOTAL HANDOVER (CASH + CHEQUES)', 48)}${ThermalDoc.r(ThermalDoc.money(cashToHandOver + data.totalChequesAmount), 18)}', bold: true);
    if (netCash < -0.005) {
      d.line(' Note: Negative cash shortfall not deducted from cheques.');
    }
    d.rule();
    if (data.cashShortfallRefunds.isNotEmpty) {
      d.line(' CASH REFUNDS ISSUED WITH INSUFFICIENT CASH:', bold: true);
      for (final s in data.cashShortfallRefunds) {
        final label = '${s.creditNoteId} (Ref: ${ThermalDoc.money(s.refundAmount)})';
        d.line('   ${ThermalDoc.l(label, 46)}${ThermalDoc.r('-${ThermalDoc.money(s.shortfallAmount)}', 18)}');
      }
      d.rule();
    }
    if (data.totalDigitalAmount > 0) {
      d.line(' ${ThermalDoc.l('Digital receipts (not handed over)', 48)}${ThermalDoc.r(ThermalDoc.money(data.totalDigitalAmount), 18)}');
      d.rule();
    }
    d.blank();
    d.line(' SALEMAN:.....${data.operatorName}.............');
    d.blank();
    d.line(' STORE : ...${data.registerId.isNotEmpty ? data.registerId : ThermalSession.siteCode}.......');
    d.blank();
    d.line(' RECEIVED BY.....................            Sig:.............');
    d.blank(2);

    return d.build();
  }
}
