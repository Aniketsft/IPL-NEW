
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

void main() async {
  sqfliteFfiInit();
  var databaseFactory = databaseFactoryFfi;
  
  // Update path based on your typical sqflite location
  // On Windows, it's usually in LocalAppData, but we might have a custom one
  final dbPath = 'C:/Users/Aniket/AppData/Roaming/enterprise_auth/enterprise_auth.db';
  
  if (!File(dbPath).existsSync()) {
    print('Database not found at $dbPath');
    return;
  }

  final db = await databaseFactory.openDatabase(dbPath);
  
  print('--- Sales Order Rep Data ---');
  final results = await db.rawQuery('SELECT rep0, rep1, COUNT(*) as count FROM tbl_sales_orders GROUP BY rep0, rep1 LIMIT 20');
  
  for (var row in results) {
    print('Rep0: ${row['rep0']}, Rep1: ${row['rep1']}, Count: ${row['count']}');
  }
  
  await db.close();
}
