import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';

class LocalDatabaseHelper {
  static const _databaseName = "InnodisApp.db";
  static const _databaseVersion = 10;

  static const tableScans = 'tbl_scans';
  static const tableOrders = 'tbl_sales_orders';
  static const tableDetails = 'tbl_sales_order_details';
  static const tableCustomers = 'tbl_customers';
  static const tableReps = 'tbl_sales_reps';
  static const tableLocations = 'tbl_locations';
  static const tableCachedUsers = 'tbl_cached_users';
  static const tableSyncHistory = 'tbl_sync_history';

  // tbl_scans columns
  static const columnId = 'id';
  static const columnSoNumber = 'soNumber';
  static const columnProductCode = 'productCode';
  static const columnQuantity = 'quantity';
  static const columnTimestamp = 'timestamp';
  static const columnItemStatus = 'itemStatus';
  static const columnLocationCode = 'location';
  static const columnIsSynced = 'isSynced';
  static const columnIsReflected = 'isReflected';

  // tbl_sales_orders columns
  static const colOrderNum = 'sohNum';
  static const colPoNum = 'poNo';
  static const colOrderDate = 'orderDate';
  static const colDeliveryDate = 'deliveryDate';
  static const colCustomerCode = 'customerCode';
  static const colCustomerName = 'customerName';
  static const colRep0 = 'rep0';
  static const colRep1 = 'rep1';
  static const colSite = 'site';
  static const colStatus = 'status';
  static const colSource = 'source';
  static const colStatusLabel = 'statusLabel';

  // tbl_sales_order_details columns
  static const colDetSoNum = 'soNumber';
  static const colDetItemCode = 'itemCode';
  static const colDetDescription = 'description';
  static const colDetBarcodeType = 'barcodeType';
  static const colDetQuantity = 'quantity';

  // Common Code/Name columns
  static const colCode = 'code';
  static const colName = 'name';

  // tbl_locations columns
  static const colLocSite = 'site';
  static const colLocCode = 'location';
  static const colLocWrh = 'warehouse';
  static const colLocWrhName = 'warehouseName';
  static const colLocType = 'locationType';
  static const colLocTypeName = 'locationTypeName';

  // tbl_cached_users columns
  static const colUserUsername = 'username';
  static const colUserPassHash = 'passwordHash';
  static const colUserPermissions = 'permissionsJson';
  static const colUserEmail = 'email';
  static const colUserId = 'userId';

  // tbl_sync_history columns
  static const colSyncTimestamp = 'timestamp';
  static const colSyncStatus = 'status'; // 'Success', 'Failed'
  static const colSyncMessage = 'message';
  static const colSyncCounts = 'recordCounts'; // JSON string of counts

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
      onUpgrade: _onUpgrade,
    );
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    print("DB Upgrade: $oldVersion to $newVersion");

    // Version 6: Add Sync History table
    if (oldVersion < 6) {
      print("DB Upgrade: Creating Sync History table (Version 6)");
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableSyncHistory (
          $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
          $colSyncTimestamp TEXT NOT NULL,
          $colSyncStatus TEXT NOT NULL,
          $colSyncMessage TEXT,
          $colSyncCounts TEXT
        )
      ''');
    }

    // Version 7: Add isSynced column to Orders (for Internal Cut/Bulk)
    if (oldVersion < 7) {
      print('DB Upgrade: Adding isSynced to tbl_sales_orders (v7)');
      await db.execute(
        'ALTER TABLE $tableOrders ADD COLUMN $columnIsSynced INTEGER NOT NULL DEFAULT 0',
      );
    }

    if (oldVersion < 8) {
      print(
        'DB Upgrade: Adding persistent metrics to tbl_sales_order_details (v8)',
      );
      // Add manufactured and remaining columns to details table
      // In SQLite, we add columns one by one
      await db.execute(
        'ALTER TABLE $tableDetails ADD COLUMN manufactured REAL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE $tableDetails ADD COLUMN remaining REAL DEFAULT 0',
      );
    }

    if (oldVersion < 9) {
      print('DB Upgrade: Adding isReflected to tbl_scans (v9)');
      await db.execute(
        'ALTER TABLE $tableScans ADD COLUMN isReflected INTEGER NOT NULL DEFAULT 0',
      );
    }

    if (oldVersion < 10) {
      print('DB Upgrade: Creating Enterprise Performance Indexes (v10)');
      // Composite index for reconciliation query optimization
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_scans_reconciliation ON $tableScans($columnSoNumber, $columnProductCode, $columnIsReflected)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_details_reconciliation ON $tableDetails($colDetSoNum, $colDetItemCode)',
      );
    }
  }

  Future _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableScans (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnSoNumber TEXT NOT NULL,
        $columnProductCode TEXT NOT NULL,
        $columnQuantity REAL NOT NULL,
        $columnTimestamp TEXT NOT NULL,
        $columnItemStatus TEXT,
        $columnLocationCode TEXT,
        $columnIsSynced INTEGER NOT NULL DEFAULT 0,
        $columnIsReflected INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableOrders (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $colOrderNum TEXT,
        $colPoNum TEXT,
        $colOrderDate TEXT,
        $colDeliveryDate TEXT,
        $colCustomerCode TEXT,
        $colCustomerName TEXT,
        $colRep0 TEXT,
        $colRep1 TEXT,
        $colSite TEXT,
        $colStatus INTEGER,
        $colSource TEXT,
        $colStatusLabel TEXT,
        $columnIsSynced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableDetails (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $colDetSoNum TEXT,
        $colDetItemCode TEXT,
        $colDetDescription TEXT,
        $colDetBarcodeType TEXT,
        $colDetQuantity REAL,
        manufactured REAL DEFAULT 0,
        remaining REAL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableCustomers (
        $colCode TEXT PRIMARY KEY,
        $colName TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableReps (
        $colCode TEXT PRIMARY KEY,
        $colName TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableLocations (
        $colLocCode TEXT PRIMARY KEY,
        $colLocWrh TEXT,
        $colLocWrhName TEXT,
        $colLocType TEXT,
        $colLocTypeName TEXT,
        $colLocSite TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableCachedUsers (
        $colUserUsername TEXT PRIMARY KEY,
        $colUserPassHash TEXT,
        $colUserPermissions TEXT,
        $colUserEmail TEXT,
        $colUserId TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableSyncHistory (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $colSyncTimestamp TEXT NOT NULL,
        $colSyncStatus TEXT NOT NULL,
        $colSyncMessage TEXT,
        $colSyncCounts TEXT
      )
    ''');

    // Optimization: Add indexes for faster lookups
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_details_so ON $tableDetails($colDetSoNum)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_orders_date ON $tableOrders($colOrderDate)',
    );

    // PERFORMANCE: Optimized indexes for Enterprise Reconciliation
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_scans_reconciliation ON $tableScans($columnSoNumber, $columnProductCode, $columnIsReflected)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_details_reconciliation ON $tableDetails($colDetSoNum, $colDetItemCode)',
    );
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

  // Get scans that haven't been swallowed by a refresh yet
  Future<List<Map<String, dynamic>>> getUnreflectedScans() async {
    Database db = await instance.database;
    return await db.query(
      tableScans,
      where: '$columnIsReflected = ?',
      whereArgs: [0],
    );
  }

  // Mark scans as synced
  Future<int> markAsSynced(List<int> ids) async {
    if (ids.isEmpty) return 0;
    Database db = await instance.database;
    String placeholders = List.generate(ids.length, (index) => '?').join(', ');
    return await db.update(
      tableScans,
      {columnIsSynced: 1},
      where: '$columnId IN ($placeholders)',
      whereArgs: ids,
    );
  }

  // Mark scans as swallowed by a master refresh
  Future<int> marksReflected(List<int> ids) async {
    if (ids.isEmpty) return 0;
    Database db = await instance.database;
    String placeholders = List.generate(ids.length, (index) => '?').join(', ');
    return await db.update(
      tableScans,
      {columnIsReflected: 1},
      where: '$columnId IN ($placeholders)',
      whereArgs: ids,
    );
  }

  // RECONCILIATION QUERY (Performance v11)
  // Reconciles server mirror totals with local unreflected scans via SQL JOIN
  Future<List<Map<String, dynamic>>> getReconciledDetails(
    String soNumber,
  ) async {
    Database db = await instance.database;
    return await db.rawQuery(
      '''
      SELECT 
        det.*,
        (COALESCE(det.manufactured, 0) + COALESCE(SUM(scn.$columnQuantity), 0)) as reconciledProduced,
        (COALESCE(det.quantity, 0) - (COALESCE(det.manufactured, 0) + COALESCE(SUM(scn.$columnQuantity), 0))) as reconciledRemaining
      FROM $tableDetails det
      LEFT JOIN $tableScans scn 
        ON det.$colDetSoNum = scn.$columnSoNumber 
        AND det.$colDetItemCode = scn.$columnProductCode
        AND scn.$columnIsReflected = 0
      WHERE det.$colDetSoNum = ?
      GROUP BY det.$colDetSoNum, det.$colDetItemCode
    ''',
      [soNumber],
    );
  }

  Future<List<Map<String, dynamic>>> getSalesOrderDetails(
    String soNumber,
  ) async {
    Database db = await instance.database;
    return await db.query(
      tableDetails,
      where: '$colDetSoNum = ?',
      whereArgs: [soNumber],
    );
  }

  // --- INTERNAL ORDER SYNC HELPERS (Cut & Bulk) ---

  Future<List<Map<String, dynamic>>> getUnsyncedInternalOrders() async {
    Database db = await instance.database;
    return await db.query(
      tableOrders,
      where: '$colSource = ? AND $columnIsSynced = ?',
      whereArgs: ['Internal', 0],
    );
  }

  Future<int> markOrdersAsSynced(List<String> soNumbers) async {
    if (soNumbers.isEmpty) return 0;
    Database db = await instance.database;
    String placeholders = List.generate(
      soNumbers.length,
      (index) => '?',
    ).join(', ');
    return await db.update(
      tableOrders,
      {columnIsSynced: 1},
      where: '$colOrderNum IN ($placeholders)',
      whereArgs: soNumbers,
    );
  }

  // Clear specific table
  Future<void> clearTable(String tableName) async {
    Database db = await instance.database;
    await db.delete(tableName);
  }

  // Sync History Methods
  Future<void> insertSyncHistory({
    required String status,
    required String message,
    Map<String, int>? counts,
  }) async {
    final db = await instance.database;
    await db.insert(tableSyncHistory, {
      colSyncTimestamp: DateTime.now().toIso8601String(),
      colSyncStatus: status,
      colSyncMessage: message,
      colSyncCounts: counts != null ? jsonEncode(counts) : null,
    });
  }

  Future<List<Map<String, dynamic>>> getSyncHistory() async {
    final db = await instance.database;
    return await db.query(tableSyncHistory, orderBy: '$colSyncTimestamp DESC');
  }

  // Perform bulk refresh of logistics data
  Future<void> refreshLogisticsData({
    required List<Map<String, dynamic>> orders,
    required List<Map<String, dynamic>> details,
    required List<Map<String, dynamic>> customers,
    required List<Map<String, dynamic>> reps,
    required List<Map<String, dynamic>> locations,
  }) async {
    Database db = await instance.database;

    await db.transaction((txn) async {
      // 1. SELECTIVE CLEANUP
      // Note: Delete details FIRST while we can still join with the Orders table to find "External" ones
      await txn.rawDelete('''
        DELETE FROM $tableDetails 
        WHERE $colDetSoNum IN (
          SELECT $colOrderNum FROM $tableOrders WHERE $colSource = 'External'
        )
      ''');

      // Now delete "External" (Sage) header/denormalized rows. Preserve "Internal" local entries.
      await txn.delete(
        tableOrders,
        where: '$colSource = ?',
        whereArgs: ['External'],
      );

      // Clear lookup mirrors (these are always full refreshed from API)
      await txn.delete(tableCustomers);
      await txn.delete(tableReps);
      await txn.delete(tableLocations);

      // 2. Batch Insert new data
      Batch batch = txn.batch();

      try {
        for (var order in orders) {
          batch.insert(
            tableOrders,
            order,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        for (var detail in details) {
          batch.insert(
            tableDetails,
            detail,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        for (var customer in customers) {
          batch.insert(
            tableCustomers,
            customer,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        for (var rep in reps) {
          batch.insert(
            tableReps,
            rep,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        for (var location in locations) {
          batch.insert(
            tableLocations,
            location,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        await batch.commit(noResult: true);
        print(
          "Data Sync Storage: Selective refresh complete. Inserted ${orders.length} orders and ${details.length} details.",
        );
      } catch (e) {
        print("CRITICAL: Error during selective batch insertion: $e");
        rethrow;
      }
    });
  }
}
