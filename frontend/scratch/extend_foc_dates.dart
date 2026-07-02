import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('Extend FOC Dates', () async {
    sqfliteFfiInit();
    var factory = databaseFactoryFfi;
    var db = await factory.openDatabase('d:/enterprise_auth_system/InnodisApp.db');
    
    int count = await db.rawUpdate('''
      UPDATE tbl_price_lists 
      SET validTo = '2099-12-31' 
      WHERE focType IN (2, 3) OR pliCode LIKE 'T150%'
    ''');
    
    print('Successfully extended the validTo date to 2099 for $count FOC rules!');
    await db.close();
  });
}
