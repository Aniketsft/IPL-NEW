import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/pricing_engine_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    
    // Mock path_provider so LocalDatabaseHelper doesn't crash on desktop
    const MethodChannel channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return 'd:/enterprise_auth_system'; // The folder where your InnodisApp.db lives
        }
        return null;
      },
    );

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Pricing Engine properly resolves FOC promotion', () async {
    final dbHelper = LocalDatabaseHelper.instance;
    print("Connecting to DB...");
    final db = await dbHelper.database;
    
    print("--- REAL DATA TEST CASES FROM YOUR DATABASE ---");
    
    // Find up to 5 real FOC rules
    final rules = await db.rawQuery("SELECT * FROM tbl_price_lists WHERE focType IN (2, 3) LIMIT 5");
    
    for (var rule in rules) {
      String matchKey1 = rule['matchKey1']?.toString() ?? '';
      String sku = rule['matchKey2']?.toString() ?? '';
      String fld0 = rule['fld0']?.toString() ?? '';
      
      String customerCode = '';
      String customerName = '';
      
      if (fld0 == 'BPCNUM') {
        final custs = await db.rawQuery("SELECT * FROM tbl_si_customers WHERE code = ? LIMIT 1", [matchKey1]);
        if (custs.isNotEmpty) {
           customerCode = custs.first['code']?.toString() ?? '';
           customerName = custs.first['name']?.toString() ?? '';
        }
      } else if (fld0 == 'TSCCOD') {
        final custs = await db.rawQuery("SELECT * FROM tbl_si_customers WHERE tsccod = ? LIMIT 1", [matchKey1]);
        if (custs.isNotEmpty) {
           customerCode = custs.first['code']?.toString() ?? '';
           customerName = custs.first['name']?.toString() ?? '';
        }
      } else if (fld0 == 'BCGCOD') {
        final custs = await db.rawQuery("SELECT * FROM tbl_si_customers WHERE bcgcod = ? LIMIT 1", [matchKey1]);
        if (custs.isNotEmpty) {
           customerCode = custs.first['code']?.toString() ?? '';
           customerName = custs.first['name']?.toString() ?? '';
        }
      }
      
      if (customerCode.isEmpty) {
        if (fld0 == 'TSCCOD') customerName = "Any customer in Target Group (TSCCOD): $matchKey1";
        else if (fld0 == 'BCGCOD') customerName = "Any customer in Category (BCGCOD): $matchKey1";
        else customerName = "Customer ID: $matchKey1";
        
        customerCode = "(Needs matching group)";
      }
      
      print("Test Case (Rule: ${rule['pliCode']}):");
      print(" - Customer: $customerCode -> $customerName");
      print(" - Add Item SKU: $sku");
      print(" - Minimum Qty Needed: ${rule['focQtyMin']} (Bucket Size: ${rule['focQtyBkt']})");
      print(" - Free Item Earned: ${rule['focItmRef']} (Qty: ${rule['focQty']} per bucket)");
      print("--------------------------------------------------");
    }
  });
}
