import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:enterprise_auth_mobile/core/services/printer_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/credit_note_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/sales_invoice_product_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/credit_note_pdf_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/sales_invoice_pdf_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_bloc.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_cart_cubit.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_event.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_state.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/repositories/i_sales_repository.dart';

class _StubSalesRepo implements ISalesRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final macaroni = SalesInvoiceProductModel(
    sku: '8101',
    name: 'Barilla Macaroni 500g',
    stockQty: 49,
    warehouse: 'N8',
    salesUnit: 'EA',
  );

  test('consolidateCartItemsForDisplay merges multi-lot paid lines, clears lot, keeps FOC & distinct status separate', () {
    final lot1 = CartItem(
      product: macaroni,
      quantity: 32,
      lotNumber: 'LOT26092038',
      warehouse: 'N8',
      location: 'N8',
      basePrice: 72.29,
      vatRatePercent: 15.0,
      taxRule: 'TC01',
      stockStatus: 'A',
    );
    final lot2 = CartItem(
      product: macaroni,
      quantity: 17,
      lotNumber: 'LOT26092039',
      warehouse: 'N8',
      location: 'N8',
      basePrice: 72.29,
      vatRatePercent: 15.0,
      taxRule: 'TC01',
      stockStatus: 'A',
    );
    final foc = CartItem(
      product: macaroni,
      quantity: 1,
      lotNumber: 'LOT26092039',
      warehouse: 'N8',
      location: 'N8',
      basePrice: 0.0,
      isFoc: true,
      mainItemSku: '8101',
      stockStatus: 'A',
    );
    final damagedReturn = CartItem(
      product: macaroni,
      quantity: 2,
      lotNumber: 'LOT26092038',
      warehouse: 'N8',
      location: 'N8',
      basePrice: 72.29,
      vatRatePercent: 15.0,
      taxRule: 'TC01',
      stockStatus: 'R',
    );

    final groups = consolidateCartItemsForDisplay([lot1, lot2, foc, damagedReturn]);
    expect(groups.length, 3);

    final paidGroup = groups[0];
    expect(paidGroup.sourceIndices, [0, 1]);
    expect(paidGroup.displayItem.quantity, 49.0);
    expect(paidGroup.displayItem.lotNumber, '');
    expect(paidGroup.totalVatAmount, closeTo(531.33, 0.01));
    expect(paidGroup.totalAmount, closeTo(4073.54, 0.01));

    expect(groups[1].displayItem.isFoc, isTrue);
    expect(groups[1].displayItem.quantity, 1.0);
    expect(groups[2].displayItem.stockStatus, 'R');
    expect(groups[2].displayItem.quantity, 2.0);
  });

  test('SalesInvoicePdfService & CreditNotePdfService render multi-lot same product as a single line without lot', () async {
    final lot1 = CartItem(
      product: macaroni,
      quantity: 32,
      lotNumber: 'LOT26092038',
      warehouse: 'N8',
      location: 'N8',
      basePrice: 72.29,
      vatRatePercent: 15.0,
      taxRule: 'TC01',
    );
    final lot2 = CartItem(
      product: macaroni,
      quantity: 17,
      lotNumber: 'LOT26092039',
      warehouse: 'N8',
      location: 'N8',
      basePrice: 72.29,
      vatRatePercent: 15.0,
      taxRule: 'TC01',
    );

    final invBytes = await SalesInvoicePdfService().generateInvoicePdf(
      pageFormat: PdfPageFormat.roll80,
      invoiceId: 'HICGD08112600026',
      customer: const {'code': 'SSM658', 'name': 'Test Buyer'},
      items: [lot1, lot2],
      subtotal: 3542.21,
      discountAmount: 0.0,
      vatAmount: 531.33,
      grandTotal: 4073.54,
      paymentMethod: 'CASH',
      paymentStatus: 'PAID',
    );
    final invText = (PrinterService.lookupPdfThermalLines(invBytes) ?? [])
        .map((l) => l.text)
        .join('\n');
    expect('ProdCode :  8101'.allMatches(invText).length, 1);
    expect(invText, contains('49(EA)'));
    expect(invText, contains('4,073.54'));
    expect(invText, isNot(contains('LOT26092038')));

    final cn = CreditNoteModel(
      creditNoteId: 'HRSCG08112600001',
      creditNoteType: 'RETURN',
      salesSite: 'SCG',
      customerCode: 'SSM658',
      customerName: 'Test Buyer',
      currency: 'MUR',
      grandTotal: 4073.54,
      settlementType: 'CASH',
      createdAt: '2026-11-23T09:00:00',
      createdBy: 'scg',
    );
    final cnBytes = await CreditNotePdfService().generateCreditNotePdf(
      pageFormat: PdfPageFormat.roll80,
      creditNote: cn,
      resolvedLines: [
        {
          'sku': '8101',
          'name': 'Barilla Macaroni 500g',
          'quantity': 32.0,
          'basePrice': 72.29,
          'discountAmount': 0.0,
          'vatAmount': 346.99,
          'salesUnit': 'EA',
          'stockStatus': 'A',
        },
        {
          'sku': '8101',
          'name': 'Barilla Macaroni 500g',
          'quantity': 17.0,
          'basePrice': 72.29,
          'discountAmount': 0.0,
          'vatAmount': 184.34,
          'salesUnit': 'EA',
          'stockStatus': 'A',
        },
      ],
    );
    final cnText = (PrinterService.lookupPdfThermalLines(cnBytes) ?? [])
        .map((l) => l.text)
        .join('\n');
    expect('ProdCode :  8101'.allMatches(cnText).length, 1);
    expect(cnText, contains('49(EA)'));
  });

  test('SalesInvoiceBloc RemoveCartItems removes all lot lines for consolidated group atomically and cascades linked FOC', () async {
    final bloc = SalesInvoiceBloc(repository: _StubSalesRepo());
    bloc.add(
      InitializeTransaction(
        transactionType: 'INVOICE',
        customer: const {'code': 'SSM658', 'name': 'Test Buyer'},
        cartItems: [
          CartItem(
            product: macaroni,
            quantity: 1,
            lotNumber: 'LOT26092039',
            basePrice: 0,
            isFoc: true,
            mainItemSku: '8101',
          ),
          CartItem(
            product: macaroni,
            quantity: 32,
            lotNumber: 'LOT26092038',
            basePrice: 72.29,
            vatRatePercent: 15.0,
          ),
          CartItem(
            product: macaroni,
            quantity: 17,
            lotNumber: 'LOT26092039',
            basePrice: 72.29,
            vatRatePercent: 15.0,
          ),
        ],
      ),
    );
    await Future<void>.delayed(Duration.zero);

    bloc.add(const RemoveCartItems([1, 2]));
    await Future<void>.delayed(Duration.zero);

    final state = bloc.state as SalesInvoiceLoaded;
    expect(state.cartItems, isEmpty);
    await bloc.close();
  });
}
