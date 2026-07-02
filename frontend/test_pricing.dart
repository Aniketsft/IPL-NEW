import 'package:flutter/widgets.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/pricing_engine_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  
  final dbHelper = LocalDatabaseHelper.instance;
  
  print("Starting DB...");
  final db = await dbHelper.database;
  print("DB Started.");

  print("\n--- FOC Rules in DB ---");
  final focRules = await db.rawQuery("SELECT * FROM tbl_price_lists WHERE focType IN (2, 3) LIMIT 1");
  if (focRules.isEmpty) {
    print("No FOC rules found in DB!");
    return;
  }
  
  final rule = focRules.first;
  print("Found FOC Rule: \n$rule");

  final String customerMatchKey = rule['matchKey1'] as String;
  final String sku = rule['matchKey2'] as String;
  final double minQty = (rule['minQty'] as num?)?.toDouble() ?? 1.0;
  final double focQtyMin = (rule['focQtyMin'] as num?)?.toDouble() ?? 1.0;

  // Since we don't know the exact customer for matchKey1, we'll just pull a random customer that might fit
  // Let's just use ALD777 and see if it hits, or pull from tbl_si_customers where tsccod or customerCode matches matchKey1
  final custs = await db.rawQuery("SELECT * FROM tbl_si_customers WHERE customerCode = ? OR tsccod = ? LIMIT 1", [customerMatchKey, customerMatchKey]);
  
  String testCustomer = 'ALD777';
  String testTsccod = '';
  if (custs.isNotEmpty) {
    testCustomer = custs.first['customerCode'] as String;
    testTsccod = custs.first['tsccod'] as String;
  }
  
  print("\n--- Testing FOC Pricing Engine ---");
  final service = PricingEngineService();
  double testQty = focQtyMin > 0 ? focQtyMin * 2.5 : 10.0;
  print("Resolving price for customer $testCustomer, sku $sku, qty $testQty...");
  
  try {
    final result = await service.resolvePrice(
      customerCode: testCustomer,
      bcgcod: '', 
      tsccod: testTsccod,
      sku: sku,
      qty: testQty,
    );
    print("Resolved: basePrice = ${result.basePrice}, discountPct = ${result.discountPct}, source = ${result.source}");
    print("hasFoc = ${result.hasFoc}");
    if (result.hasFoc) {
      print("focQuantity = ${result.focQuantity}");
      print("focItemSku = ${result.focItemSku}");
    }
  } catch (e) {
    print("Error: $e");
  }
}
