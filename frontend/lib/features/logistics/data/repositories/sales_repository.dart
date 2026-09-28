import 'package:enterprise_auth_mobile/core/network_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/repositories/i_sales_repository.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/sales_invoice_product_repository.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/transaction_history_repository.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/si_sales_order_service.dart';
import '../models/sales_invoice_product_model.dart';
import '../../domain/services/credit_note_service.dart';
import '../models/credit_note_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_cart_cubit.dart';
import 'package:enterprise_auth_mobile/core/secure_storage_service.dart';

class SalesRepository implements ISalesRepository {
  final SalesInvoiceProductRepository _productRepository;
  final TransactionHistoryRepository _transactionRepository;
  final SISalesOrderService _salesOrderService;
  final CreditNoteService _creditNoteService;

  SalesRepository(NetworkService networkService)
      : _productRepository = SalesInvoiceProductRepository(networkService),
        _transactionRepository = TransactionHistoryRepository(),
        _salesOrderService = SISalesOrderService(),
        _creditNoteService = CreditNoteService();

  @override
  Future<List<Map<String, dynamic>>> getCustomers() async {
    // TODO: implement getCustomers in Phase 3
    throw UnimplementedError('getCustomers not implemented');
  }

  @override
  Future<List<Map<String, dynamic>>> getProducts({String? searchQuery, String? category}) async {
    // TODO: implement getProducts in Phase 3
    throw UnimplementedError('getProducts not implemented');
  }

  @override
  Future<List<String>> getDistinctWarehouses() async {
    return await _productRepository.getDistinctWarehouses();
  }

  @override
  Future<List<Map<String, dynamic>>> getLotsForProduct(String productCode, String warehouse) async {
    // TODO: implement getLotsForProduct in Phase 3
    throw UnimplementedError('getLotsForProduct not implemented');
  }

  @override
  Future<List<Map<String, dynamic>>> getSalesOrders() async {
    return await _salesOrderService.getSalesOrders();
  }

  @override
  Future<List<Map<String, dynamic>>> getSalesOrderDetails(int orderId) async {
    return await _salesOrderService.getSalesOrderDetails(orderId);
  }

  @override
  Future<void> saveSalesOrder({
    required Map<String, dynamic> customer,
    required List<CartItem> items,
    required double totalAmount,
    required String deliveryDate,
    String? orderNumber,
  }) async {
    // TODO: implement saveSalesOrder in Phase 3
    throw UnimplementedError('saveSalesOrder not implemented');
  }

  @override
  Future<void> markOrderAsConverted(int orderId) async {
    await _salesOrderService.markOrderAsConverted(orderId);
  }

  @override
  Future<void> saveInvoice({
    required Map<String, dynamic> customer,
    required List<CartItem> items,
    required double totalAmount,
    String? originalSalesOrderNumber,
    required String paymentMode,
  }) async {
    // TODO: implement saveInvoice in Phase 3
    throw UnimplementedError('saveInvoice not implemented');
  }

  @override
  Future<List<Map<String, dynamic>>> getTransactionHistory(String transactionType) async {
    // TODO: implement getTransactionHistory in Phase 3
    throw UnimplementedError('getTransactionHistory not implemented');
  }

  @override
  Future<List<Map<String, dynamic>>> getTransactionDetails(int transactionId) async {
    // TODO: implement getTransactionDetails in Phase 3
    throw UnimplementedError('getTransactionDetails not implemented');
  }

  @override
  Future<void> createStandaloneCreditNote({
    required Map<String, dynamic> customer,
    required List<CartItem> items,
    required double totalAmount,
    required String refundMethod,
  }) async {
    final userSite = await SecureStorageService().getSiteCode();
    final site = (userSite != null && userSite.isNotEmpty && userSite != 'ALL') ? userSite : 'IPL';

    await _creditNoteService.createStandaloneCreditNote(
      salesSite: site,
      customerCode: customer['id'] ?? '',
      customerName: customer['name'] ?? '',
      refundMethod: refundMethod,
      refundAmount: totalAmount,
      items: items.asMap().entries.map((entry) => CreditNoteLineModel(
        creditNoteId: "0", // Assigned by backend
        lineNo: (entry.key + 1) * 1000,
        standaloneSku: entry.value.product.sku,
        standaloneName: entry.value.product.name,
        quantity: entry.value.quantity.toDouble(),
        standalonePrice: entry.value.basePrice,
      )).toList(),
      createdBy: 'USER', // TODO: Get actual user
    );
  }

  @override
  Future<void> createAmountOnlyCreditNote({
    required Map<String, dynamic> customer,
    required List<Map<String, dynamic>> invoiceReferences,
    required double refundAmount,
    required String refundMethod,
  }) async {
    // TODO: implement createAmountOnlyCreditNote in Phase 3
    throw UnimplementedError('createAmountOnlyCreditNote not implemented');
  }

  @override
  Future<void> reverseInvoice({
    required int originalInvoiceId,
    required List<CartItem> itemsToReverse,
  }) async {
    // TODO: implement reverseInvoice in Phase 3
    throw UnimplementedError('reverseInvoice not implemented');
  }
}
