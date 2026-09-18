import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_cart_cubit.dart';

/// Centralized repository interface for the Mobile Sales Module.
/// This abstract class decouples the data layer (SQLite/API) from the UI and State layers.
abstract class ISalesRepository {
  /// Customers
  Future<List<Map<String, dynamic>>> getCustomers();

  /// Products & Inventory
  Future<List<Map<String, dynamic>>> getProducts({String? searchQuery, String? category});
  Future<List<String>> getDistinctWarehouses();
  Future<List<Map<String, dynamic>>> getLotsForProduct(String productCode, String warehouse);

  /// Sales Orders
  Future<List<Map<String, dynamic>>> getSalesOrders();
  Future<List<Map<String, dynamic>>> getSalesOrderDetails(int orderId);
  Future<void> saveSalesOrder({
    required Map<String, dynamic> customer,
    required List<CartItem> items,
    required double totalAmount,
    required String deliveryDate,
    String? orderNumber,
  });
  Future<void> markOrderAsConverted(int orderId);

  /// Invoices
  Future<void> saveInvoice({
    required Map<String, dynamic> customer,
    required List<CartItem> items,
    required double totalAmount,
    String? originalSalesOrderNumber,
    required String paymentMode,
  });
  Future<List<Map<String, dynamic>>> getTransactionHistory(String transactionType);
  Future<List<Map<String, dynamic>>> getTransactionDetails(int transactionId);

  /// Credit Notes
  Future<void> createStandaloneCreditNote({
    required Map<String, dynamic> customer,
    required List<CartItem> items,
    required double totalAmount,
    required String refundMethod,
  });
  Future<void> createAmountOnlyCreditNote({
    required Map<String, dynamic> customer,
    required List<Map<String, dynamic>> invoiceReferences,
    required double refundAmount,
    required String refundMethod,
  });
  Future<void> reverseInvoice({
    required int originalInvoiceId,
    required List<CartItem> itemsToReverse,
  });
}
