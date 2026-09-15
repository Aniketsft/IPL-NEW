import 'package:flutter/foundation.dart';
import '../../data/local/local_database_helper.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_cart_cubit.dart';
import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';

class SISalesOrderService {
  final LocalDatabaseHelper _dbHelper = LocalDatabaseHelper.instance;

  Future<void> saveSalesOrder({
    required Map<String, dynamic> customer,
    required List<CartItem> items,
    required double totalAmount,
  }) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      // Insert Order
      final orderId = await txn.insert(
        LocalDatabaseHelper.tableSiSalesOrders,
        {
          'customerCode': customer['code'] ?? '',
          'customerName': customer['name'] ?? '',
          'totalAmount': totalAmount,
          'status': 'Open',
          'createdAt': DateTime.now().toIso8601String(),
        },
      );

      // Insert Details
      for (final item in items) {
        await txn.insert(
          LocalDatabaseHelper.tableSiSalesOrderDetails,
          {
            'orderId': orderId,
            'productCode': item.product.sku,
            'productName': item.product.name,
            'quantity': item.quantity,
            'basePrice': item.basePrice,
            'discountAmount': item.discountAmount,
            'vatAmount': item.vatAmount,
            'total': item.total,
            'salesUnit': item.product.salesUnit,
            'lotNumber': item.lotNumber,
            'warehouse': item.warehouse,
            'location': item.location,
            'cce0': item.product.cce0,
            'taxRule': item.taxRule,
          },
        );
      }
    });
  }

  Future<List<Map<String, dynamic>>> getSalesOrders() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      LocalDatabaseHelper.tableSiSalesOrders,
      orderBy: 'createdAt DESC',
    );
    return maps;
  }

  Future<List<Map<String, dynamic>>> getSalesOrderDetails(int orderId) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      LocalDatabaseHelper.tableSiSalesOrderDetails,
      where: 'orderId = ?',
      whereArgs: [orderId],
    );
    return maps;
  }

  Future<void> markOrderAsConverted(int orderId) async {
    final db = await _dbHelper.database;
    await db.update(
      LocalDatabaseHelper.tableSiSalesOrders,
      {'status': 'Converted'},
      where: 'id = ?',
      whereArgs: [orderId],
    );
  }
}
