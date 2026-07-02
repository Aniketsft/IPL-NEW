import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';

void main() async {
  sqfliteFfiInit();
  var databaseFactory = databaseFactoryFfi;
  var db = await databaseFactory.openDatabase('d:/enterprise_auth_system/InnodisApp.db');

  print('--- Finding VAT + FOC Scenarios ---');

  // Scenario 1: Same Item FOC + 15% VAT
  // Needs customer in DREAM with VATR
  var dreamCustomers = await db.rawQuery("SELECT bpcNum, bpcNam, vacBpr FROM tbl_customers WHERE tsccod = 'DREAM' AND vacBpr = 'VATR' LIMIT 1");
  var dreamCustomerNonVat = await db.rawQuery("SELECT bpcNum, bpcNam, vacBpr FROM tbl_customers WHERE tsccod = 'DREAM' AND vacBpr = 'SNVTR' LIMIT 1");

  // Needs item with VAT15
  var vat15Item = await db.rawQuery("SELECT itmRef, itmDes1, vacItm FROM tbl_items WHERE itmRef = '651419' LIMIT 1");
  
  if (vat15Item.isNotEmpty && vat15Item.first['vacItm'] == 'VAT15') {
     print('Item 651419 has VAT15!');
  } else {
     print('Item 651419 VAT Code: \${vat15Item.first['vacItm']}');
     // Find another item in the rules that has VAT15
     var focItems = await db.rawQuery('''
       SELECT r.matchKey2, i.itmDes1, i.vacItm 
       FROM tbl_price_lists r 
       JOIN tbl_items i ON i.itmRef = r.matchKey2 
       WHERE r.fld0 = 'TSCCOD' AND r.matchKey1 = 'DREAM' AND i.vacItm = 'VAT15' LIMIT 1
     ''');
     if (focItems.isNotEmpty) {
       print('Alternative FOC Item with VAT15: \${focItems.first}');
     }
  }

  print('\\nCustomer with DREAM + VATR: \${dreamCustomers.isNotEmpty ? dreamCustomers.first : 'None'}');
  print('Customer with DREAM + SNVTR: \${dreamCustomerNonVat.isNotEmpty ? dreamCustomerNonVat.first : 'None'}');

  // Scenario 3: Cross Item FOC
  // Item 6433
  var item6433 = await db.rawQuery("SELECT itmRef, vacItm FROM tbl_items WHERE itmRef = '6433' LIMIT 1");
  var item6438 = await db.rawQuery("SELECT itmRef, vacItm FROM tbl_items WHERE itmRef = '6438' LIMIT 1");
  print('\\nCross FOC Item 6433 VAT Code: \${item6433.first['vacItm']}');
  print('Cross FOC Free Item 6438 VAT Code: \${item6438.first['vacItm']}');

  exit(0);
}
