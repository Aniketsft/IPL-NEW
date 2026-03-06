import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class LocalDatabaseHelper {
  static const _databaseName = "InnodisApp.db";
  static const _databaseVersion = 1;

  static const tableScans = 'tbl_scans';

  static const columnId = 'id';
  static const columnSoNumber = 'soNumber';
  static const columnProductCode = 'productCode';
  static const columnQuantity = 'quantity';
  static const columnTimestamp = 'timestamp';
  static const columnIsSynced = 'isSynced';

  // Make this a singleton class
  LocalDatabaseHelper._privateConstructor();
  static final LocalDatabaseHelper instance =
      LocalDatabaseHelper._privateConstructor();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  _initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, _databaseName);
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
    );
  }

  Future _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableScans (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnSoNumber TEXT NOT NULL,
        $columnProductCode TEXT NOT NULL,
        $columnQuantity REAL NOT NULL,
        $columnTimestamp TEXT NOT NULL,
        $columnIsSynced INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  // Insert a scan record
  Future<int> insertScan(Map<String, dynamic> row) async {
    Database db = await instance.database;
    return await db.insert(tableScans, row);
  }

  // Retrieve all unsynced scans
  Future<List<Map<String, dynamic>>> getUnsyncedScans() async {
    Database db = await instance.database;
    return await db.query(
      tableScans,
      where: '$columnIsSynced = ?',
      whereArgs: [0],
    );
  }

  // Mark scans as synced
  Future<int> markAsSynced(List<int> ids) async {
    if (ids.isEmpty) return 0;
    Database db = await instance.database;

    // SQLite doesn't have a direct WHERE IN array binder that takes a List easily without mapping,
    // so we build the placeholders string: ?, ?, ?
    String placeholders = List.generate(ids.length, (index) => '?').join(', ');

    return await db.update(
      tableScans,
      {columnIsSynced: 1},
      where: '$columnId IN ($placeholders)',
      whereArgs: ids,
    );
  }

  // Optional: clear synced records to save space
  Future<int> clearSyncedScans() async {
    Database db = await instance.database;
    return await db.delete(
      tableScans,
      where: '$columnIsSynced = ?',
      whereArgs: [1],
    );
  }
}
