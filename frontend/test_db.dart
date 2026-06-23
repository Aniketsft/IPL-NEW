import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

void main() async {
  sqfliteFfiInit();
  var databaseFactory = databaseFactoryFfi;
  var dbPath = p.join('d:\\enterprise_auth_system', 'InnodisApp.db');
  
  var db = await databaseFactory.openDatabase(dbPath);
  
  var sites = await db.rawQuery('SELECT DISTINCT code FROM tbl_sites ORDER BY code');
  print('SITES: \$sites');

  var whs = await db.rawQuery('SELECT DISTINCT warehouse FROM tbl_sales_invoice_item_stock_details WHERE warehouse IS NOT NULL AND warehouse != "" ORDER BY warehouse');
  print('WAREHOUSES: \$whs');
  
  await db.close();
}
