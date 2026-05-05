import 'package:flutter/foundation.dart';
import '../../../logistics/data/local/local_database_helper.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/lot.dart';

class SalesRepository {
  final LocalDatabaseHelper _dbHelper = LocalDatabaseHelper.instance;

  Future<List<Customer>> getCustomers() async {
    try {
      if (kIsWeb) return []; // Web fallback
      final db = await _dbHelper.database;
      final List<Map<String, dynamic>> maps = await db.query(LocalDatabaseHelper.tableCustomers);
      
      return maps.map((map) => Customer(
        id: map['code'] as String, // Using code as ID since tableCustomers only has code & name
        name: map['name'] as String,
        code: map['code'] as String,
        type: 'Credit', // Default mock
        location: 'Local Region', // Default mock
        status: 'Active', // Default mock
        creditLimit: 10000.00, // Default mock
        outstanding: 0.00, // Default mock
        currency: 'Rs.',
      )).toList();
    } catch (e) {
      debugPrint('SalesRepo: Error fetching customers: $e');
      return [];
    }
  }

  Future<List<Product>> getProducts() async {
    try {
      if (kIsWeb) return [];
      final db = await _dbHelper.database;
      final List<Map<String, dynamic>> maps = await db.query(LocalDatabaseHelper.tableProducts);
      
      return maps.map((map) => Product(
        code: map['productCode'] as String,
        name: map['productDescription'] as String,
        unit: map['stockUnit'] as String? ?? 'EA',
        price: 1500.00, // Default mock price
        stock: 100,     // Default mock stock
        category: 'General', // Default mock category
      )).toList();
    } catch (e) {
      debugPrint('SalesRepo: Error fetching products: $e');
      return [];
    }
  }

  Future<List<Lot>> getLotsForProduct(String productCode) async {
    try {
      if (kIsWeb) return [];
      final db = await _dbHelper.database;
      final List<Map<String, dynamic>> maps = await db.query(
        LocalDatabaseHelper.tableLots,
        where: 'itemCode = ?',
        whereArgs: [productCode],
      );
      
      return maps.map((map) => Lot(
        lotNumber: map['lot'] as String,
        warehouse: map['siteCode'] as String,
        location: 'Default Location', // Mock
        type: 'General', // Mock
      )).toList();
    } catch (e) {
      debugPrint('SalesRepo: Error fetching lots: $e');
      return [];
    }
  }

  Future<void> saveSalesTransaction({
    required Customer customer,
    required List<Map<String, dynamic>> items,
    required double totalAmount,
    required String paymentMethod,
  }) async {
    try {
      if (kIsWeb) return;
      final db = await _dbHelper.database;
      
      debugPrint('SalesRepo: Saving transaction for ${customer.name}, Amount: $totalAmount');
      
      // Simulating inserting into tbl_scans for local offline sync
      final timestamp = DateTime.now().toIso8601String();
      for (var item in items) {
        await db.insert(LocalDatabaseHelper.tableScans, {
          LocalDatabaseHelper.columnSoNumber: 'SALES-${DateTime.now().millisecondsSinceEpoch}',
          LocalDatabaseHelper.columnProductCode: item['code'],
          LocalDatabaseHelper.columnQuantity: item['qty'],
          LocalDatabaseHelper.columnTimestamp: timestamp,
          LocalDatabaseHelper.columnItemStatus: 'S', // Sold
          LocalDatabaseHelper.columnIsSynced: 0,
        });
      }
    } catch (e) {
      debugPrint('SalesRepo: Error saving transaction: $e');
      throw 'Failed to save sales transaction locally.';
    }
  }
}
