import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'barcode_mapping_model.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('barcode_scanner.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const numType = 'REAL NOT NULL';

    await db.execute('''
CREATE TABLE barcode_mappings (
  id $idType,
  itemCode $textType,
  barcode $textType,
  description $textType,
  barcodeType $textType,
  expectedPrefix $textType,
  unit $textType,
  unitFactor $numType
)
''');

    await db.execute('CREATE INDEX IF NOT EXISTS idx_barcode ON barcode_mappings (barcode)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_item_code ON barcode_mappings (itemCode)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_prefix_type ON barcode_mappings (expectedPrefix, barcodeType)');
  }

  Future<void> clearMappings() async {
    final db = await instance.database;
    await db.delete('barcode_mappings');
  }

  Future<void> insertMappings(List<BarcodeMapping> mappings) async {
    final db = await instance.database;
    
    // Batch insert for performance
    try {
      final batch = db.batch();
      for (var mapping in mappings) {
        batch.insert('barcode_mappings', mapping.toMap());
      }
      await batch.commit(noResult: true);
    } catch (e) {
      print('Error inserting mappings: $e');
      throw e;
    }
  }

  Future<BarcodeMapping?> getMappingByBarcode(String barcode) async {
    final db = await instance.database;
    final maps = await db.query(
      'barcode_mappings',
      where: 'barcode = ?',
      whereArgs: [barcode],
    );

    if (maps.isNotEmpty) {
      return BarcodeMapping.fromMap(maps.first);
    } else {
      return null;
    }
  }

  Future<BarcodeMapping?> getMappingByVariablePrefix(String prefix) async {
    final db = await instance.database;
    final maps = await db.query(
      'barcode_mappings',
      where: 'expectedPrefix = ? AND barcodeType = ?',
      whereArgs: [prefix, 'Variable Weight'],
    );

    if (maps.isNotEmpty) {
      return BarcodeMapping.fromMap(maps.first);
    } else {
      return null;
    }
  }

  Future<BarcodeMapping?> getMappingByItemCode(String itemCode) async {
    final db = await instance.database;
    final maps = await db.query(
      'barcode_mappings',
      where: 'itemCode = ?',
      whereArgs: [itemCode],
    );

    if (maps.isNotEmpty) {
      return BarcodeMapping.fromMap(maps.first);
    } else {
      return null;
    }
  }
}
