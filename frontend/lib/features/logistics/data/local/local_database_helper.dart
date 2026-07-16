import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:enterprise_auth_mobile/core/secure_storage_service.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:enterprise_auth_mobile/core/services/device_info_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';


class LocalDatabaseHelper {
  static const _databaseName = "InnodisApp.db";
  static const _databaseVersion = 54;


  static const tableScans = 'tbl_scans';
  static const tableOrders = 'tbl_sales_orders';
  static const tableDetails = 'tbl_sales_order_details';
  static const tableCustomers = 'tbl_customers';
  static const tableReps = 'tbl_sales_reps';
  static const tableLocations = 'tbl_locations';
  static const tableCachedUsers = 'tbl_cached_users';
  static const tableSyncHistory = 'tbl_sync_history';
  static const tableProducts = 'tbl_products';
  static const tableSites = 'tbl_sites';
  static const tableLots = 'tbl_lots';
  static const tableLabelAudits = 'tbl_label_audits';
  static const tableGlobalSettings = 'tbl_global_settings';
  static const tableDeliveryScans = 'tbl_delivery_scans';
  static const tableWorkOrders = 'tbl_work_orders';
  static const tableStagingEod = 'tbl_staging_eod';
  static const tableEodStatus = 'tbl_eod_status';
  static const tableOfflineAuditLogs = 'tbl_offline_audit_logs';
  static const tableX3SoapAudits = 'tbl_x3_soap_audits';
  static const tableEodProcessAudits = 'tbl_eod_process_audits';
  static const tableOrderRollovers = 'tbl_order_rollovers';

  // tbl_work_orders columns
  static const colWoWorkOrder   = 'workOrder';
  static const colWoProduct     = 'product';
  static const colWoReleasedQty = 'releasedQty';
  static const colWoUnit        = 'unit';
  static const colWoTrackingNum = 'trackingNum';
  static const colWoDate        = 'date';
  static const colWoCachedAt    = 'cachedAt';

  // tbl_scans columns
  static const columnId = 'id';
  static const columnSoNumber = 'soNumber';
  static const columnProductCode = 'productCode';
  static const columnQuantity = 'quantity';
  static const columnTimestamp = 'timestamp';
  static const columnItemStatus = 'itemStatus';
  static const columnLocationCode = 'location';
  static const columnIsSynced = 'isSynced';
  static const columnIsReflected = 'is_reflected';
  static const columnSyncId = 'sync_id';
  static const columnSite = 'site';
  static const columnManufacturedQuantity = 'manufactured_quantity';
  static const columnLot = 'lot';
  static const columnEaQuantity = 'ea_quantity';
  static const columnBarcode = 'barcode';
  static const columnExcludeFromEod = 'colExcludeFromEod';

  // tbl_sales_orders columns
  static const colOrderNum = 'sohNum';
  static const colPoNum = 'poNo';
  static const colOrderDate = 'orderDate';
  static const colDeliveryDate = 'deliveryDate';
  static const colCustomerCode = 'customerCode';
  static const colCustomerName = 'customerName';
  static const colRep0 = 'rep0';
  static const colRep1 = 'rep1';
  static const colSalesman = 'salesman';
  static const colSite = 'site';
  static const colStatus = 'status';
  static const colSource = 'source';
  static const colStatusLabel = 'statusLabel';
  static const colIsPreparedForShipment = 'is_prepared_for_shipment';
  static const colIsProcessed = 'is_processed';
  static const colTargetLorry = 'targetLorry';
  static const colExcludeFromEod = 'colExcludeFromEod';
  static const colIsRolledOver = 'isRolledOver';

  // tbl_order_rollovers columns
  static const colRolloverSoNum = 'soNumber';
  static const colRolloverNewDate = 'newDeliveryDate';
  static const colRolloverInitialDate = 'initialDeliveryDate';
  static const colRolloverTimestamp = 'timestamp';
  static const colRolloverIsSynced = 'isSynced';

  // tbl_sales_order_details columns

  // tbl_sales_order_details columns
  static const colDetSoNum = 'soNumber';
  static const colDetItemCode = 'itemCode';
  static const colDetDescription = 'description';
  static const colDetBarcodeType = 'barcodeType';
  static const colDetQuantity = 'quantity';
  static const colDetSite = 'site';
  static const colDetLocation = 'location';
  static const colDetLot = 'lot';
  static const colDetWarehouse = 'warehouse';
  static const colDetWarehouseName = 'warehouseName';
  static const colDetLocationType = 'locationType';
  static const colDetLocationTypeName = 'locationTypeName';
  static const colDetIsPrepared = 'is_prepared';
  static const colDetIsValidated = 'is_validated';
  static const colDetUnit = 'unit';
  static const colDetScanned = 'scanned';
  static const colDetCustomerCode = 'customerCode';
  static const colDetCustomerName = 'customerName';
  static const colDetEaScanned = 'ea_scanned';
  static const colDetCreatedAt = 'createdAt';

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

  // tbl_products columns
  static const colProdCode = 'productCode';
  static const colProdDesc = 'productDescription';
  static const colProdStu = 'stockUnit';
  static const colProdSau = 'salesUnit';
  static const colProdStandardWeight = 'standardWeight';
  static const colProdBarcode = 'barcode';

  // tbl_lots columns
  static const colLotItemCode = 'itemCode';
  static const colLotSiteCode = 'siteCode';
  static const colLotNumber = 'lot';

  // tbl_cached_users columns
  static const colUserUsername = 'username';
  static const colUserPassHash = 'passwordHash';
  static const colUserPermissions = 'permissionsJson';
  static const colUserEmail = 'email';
  static const colUserId = 'userId';
  static const colLastSyncTime = 'last_sync_time';

  // tbl_sync_history columns
  static const colSyncTimestamp = 'timestamp';
  static const colSyncStatus = 'status'; // 'Success', 'Failed'
  static const colSyncMessage = 'message';
  static const colSyncCounts = 'recordCounts'; // JSON string of counts
  static const colSyncSite = 'site';

  static const colLabelId = 'labelId';
  static const colReferenceNumber = 'referenceNumber';
  static const colLabelType = 'labelType';
  static const colProductCode = 'productCode';
  static const colManifestJson = 'manifestJson';
  static const colPrintedBy = 'printedBy';
  static const colCreatedAt = 'createdAt';
  static const colDeviceId = 'deviceId';

  
  // tbl_global_settings columns
  static const colSettingKey = 'key';
  static const colSettingValue = 'value';
  static const colSettingIsSynced = 'isSynced';
  static const colSettingLastUpdated = 'lastUpdated';
  static const colSettingUpdatedBy = 'updatedBy';
  static const colSettingAction = 'action';

  // tbl_delivery_scans columns
  static const colDelScanPayload = 'qrPayload';
  static const colDelScanSoNumber = 'soNumber';
  static const colDelScanTimestamp = 'timestamp';

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
    if (oldVersion < 30) {
      debugPrint('DB Upgrade: Creating Delivery Scans table (v30)');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableDeliveryScans (
          $colDelScanPayload TEXT,
          $colDelScanSoNumber TEXT,
          $colDelScanTimestamp TEXT,
          PRIMARY KEY ($colDelScanPayload, $colDelScanSoNumber)
        )
      ''');
    }
    if (oldVersion < 31) {
      debugPrint('DB Upgrade: Adding lot column to scans (v31)');
      await db.execute('ALTER TABLE $tableScans ADD COLUMN $columnLot TEXT');
    }
    if (oldVersion < 32) {
      debugPrint('DB Upgrade: Adding is_processed to tbl_sales_orders (v32)');
      try {
        await db.execute('ALTER TABLE $tableOrders ADD COLUMN $colIsProcessed INTEGER DEFAULT 0');
      } catch (e) {
        debugPrint("Migration error v32: $e");
      }
    }
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE $tableScans ADD COLUMN $columnIsReflected INTEGER DEFAULT 0');
      } catch (e) {
        debugPrint("Migration error v2: $e");
      }
    }
    if (oldVersion < 3) {
      // Adding sync_id to scans and is_prepared to details
      try {
        await db.execute('ALTER TABLE $tableScans ADD COLUMN $columnSyncId TEXT');
        await db.execute('ALTER TABLE $tableDetails ADD COLUMN $colDetIsPrepared INTEGER DEFAULT 0');
      } catch (e) {
        debugPrint("Migration error: $e");
      }
    }

    // Version 6: Add Sync History table
    if (oldVersion < 6) {
      debugPrint("DB Upgrade: Creating Sync History table (Version 6)");
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
      debugPrint('DB Upgrade: Checking for isSynced in tbl_sales_orders (v7)');
      var tableInfo = await db.rawQuery('PRAGMA table_info($tableOrders)');
      bool columnExists = tableInfo.any((col) => col['name'] == columnIsSynced);
      if (!columnExists) {
        await db.execute(
          'ALTER TABLE $tableOrders ADD COLUMN $columnIsSynced INTEGER NOT NULL DEFAULT 0',
        );
      }
    }

    if (oldVersion < 8) {
      debugPrint('DB Upgrade: Adding persistent metrics to tbl_sales_order_details (v8)');
      var tableInfo = await db.rawQuery('PRAGMA table_info($tableDetails)');
      
      if (!tableInfo.any((col) => col['name'] == colDetScanned)) {
        await db.execute('ALTER TABLE $tableDetails ADD COLUMN $colDetScanned REAL DEFAULT 0');
      }
      if (!tableInfo.any((col) => col['name'] == 'remaining')) {
        await db.execute('ALTER TABLE $tableDetails ADD COLUMN remaining REAL DEFAULT 0');
      }
    }

    if (oldVersion < 9) {
      debugPrint('DB Upgrade: Adding isReflected to tbl_scans (v9)');
      var tableInfo = await db.rawQuery('PRAGMA table_info($tableScans)');
      if (!tableInfo.any((col) => col['name'] == 'isReflected')) {
        await db.execute('ALTER TABLE $tableScans ADD COLUMN isReflected INTEGER NOT NULL DEFAULT 0');
      }
    }

    if (oldVersion < 10) {
      debugPrint('DB Upgrade: Creating Enterprise Performance Indexes (v10)');
      // Composite index for reconciliation query optimization
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_scans_reconciliation ON $tableScans($columnSoNumber, $columnProductCode, $columnIsReflected)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_details_reconciliation ON $tableDetails($colDetSoNum, $colDetItemCode)',
      );
    }

    if (oldVersion < 11) {
      debugPrint('DB Upgrade: Creating Product Master table (v11)');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableProducts (
          $colProdCode TEXT PRIMARY KEY,
          $colProdDesc TEXT,
          $colProdStu TEXT,
          $colProdSau TEXT
        )
      ''');
    }

    if (oldVersion < 12) {
      debugPrint('DB Upgrade: Adding UNIQUE constraints for incremental sync (v12)');
      // SQLite doesn't support directly adding constraints to existing tables easily
      // We will create temporary tables or just ensure indexes exist if they are enough,
      // but for proper UPSERT (ConflictAlgorithm.replace), we need UNIQUE constraints.

      // For Orders
      await db.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_orders_unq_num ON $tableOrders($colOrderNum)');

      // For Details
      await db.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_details_unq_composite ON $tableDetails($colDetSoNum, $colDetItemCode)');
    }

    if (oldVersion < 13) {
      debugPrint('DB Upgrade: Adding site tracking to Sync History (v13)');
      try {
        await db.execute(
          'ALTER TABLE $tableSyncHistory ADD COLUMN $colSyncSite TEXT',
        );
      } catch (e) {
        debugPrint("Migration error v13 (site): $e");
      }
      // PERFORMANCE: Index on isSynced for faster batching
      try {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_scans_is_synced ON $tableScans($columnIsSynced)',
        );
      } catch (e) {
        debugPrint("Migration error v13 (index): $e");
      }
    }

    if (oldVersion < 14) {
      try {
        await db.execute(
          'ALTER TABLE $tableScans ADD COLUMN $columnSite TEXT',
        );
      } catch (e) {
        debugPrint("Migration error v14: $e");
      }
    }

    if (oldVersion < 15) {
      debugPrint('DB Upgrade: Adding extended detail tracking to tbl_sales_order_details (v15)');
      final columns = [
        colDetSite,
        colDetLocation,
        colDetLot,
        colDetWarehouse,
        colDetWarehouseName,
        colDetLocationType,
        colDetLocationTypeName
      ];
      for (var column in columns) {
        try {
          await db.execute('ALTER TABLE $tableDetails ADD COLUMN $column TEXT');
        } catch (e) {
          debugPrint("Migration error v15 ($column): $e");
        }
      }
    }

    if (oldVersion < 16) {
      debugPrint('DB Upgrade: Ensuring columns exist in tbl_sales_order_details (v16)');
      // Re-run the same columns in case v15 was skipped or failed on some devices
      // Wrapped in try-catch to avoid crashing if they already exist from a partially failed v15
      final columnsToAdd = [
        colDetSite,
        colDetLocation,
        colDetLot,
        colDetWarehouse,
        colDetWarehouseName,
        colDetLocationType,
        colDetLocationTypeName,
      ];

      for (var column in columnsToAdd) {
        try {
          await db.execute('ALTER TABLE $tableDetails ADD COLUMN $column TEXT');
        } catch (e) {
          debugPrint('Column $column might already exist: $e');
        }
      }
    }
    
    if (oldVersion < 17) {
      debugPrint('DB Upgrade: Creating Sites table (v17)');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableSites (
          $colCode TEXT PRIMARY KEY,
          $colName TEXT
        )
      ''');
    }

    if (oldVersion < 18) {
      debugPrint('DB Upgrade: Adding isPrepared column to details table (v18)');
      try {
        await db.execute(
            'ALTER TABLE $tableDetails ADD COLUMN $colDetIsPrepared INTEGER DEFAULT 0');
      } catch (e) {
        debugPrint('Column $colDetIsPrepared might already exist: $e');
      }
    }

    if (oldVersion < 19) {
      debugPrint('DB Upgrade: Creating Lots table (v19)');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableLots (
          $colLotItemCode TEXT,
          $colLotSiteCode TEXT,
          $colLotNumber TEXT,
          PRIMARY KEY ($colLotItemCode, $colLotSiteCode, $colLotNumber)
        )
      ''');
    }
    if (oldVersion < 20) {
      debugPrint('DB Upgrade: Creating locations site index (v20)');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_locations_site ON $tableLocations($colLocSite)',
      );
    }

    if (oldVersion < 21) {
      debugPrint('DB Upgrade: Adding isSynced to tbl_sales_order_details (v21)');
      try {
        await db.execute(
          'ALTER TABLE $tableDetails ADD COLUMN $columnIsSynced INTEGER NOT NULL DEFAULT 1',
        );
      } catch (e) {
        debugPrint("Migration error v21: $e");
      }
    }

    if (oldVersion < 22) {
      debugPrint('DB Upgrade: Adding unit column to details table (v22)');
      try {
        await db.execute(
            'ALTER TABLE $tableDetails ADD COLUMN $colDetUnit TEXT DEFAULT "KG"');
      } catch (e) {
        debugPrint("Migration error v22: $e");
      }
    }
    if (oldVersion < 23) {
      debugPrint('DB Upgrade: Adding barcode and quantity extensions (v23)');
      // For scans
      var scansInfo = await db.rawQuery('PRAGMA table_info($tableScans)');
      if (!scansInfo.any((col) => col['name'] == columnManufacturedQuantity)) {
        await db.execute('ALTER TABLE $tableScans ADD COLUMN $columnManufacturedQuantity REAL DEFAULT 0');
      }

      // For products
      var productsInfo = await db.rawQuery('PRAGMA table_info($tableProducts)');
      if (!productsInfo.any((col) => col['name'] == colProdStandardWeight)) {
        await db.execute('ALTER TABLE $tableProducts ADD COLUMN $colProdStandardWeight REAL DEFAULT 0');
      }
      if (!productsInfo.any((col) => col['name'] == colProdBarcode)) {
        await db.execute('ALTER TABLE $tableProducts ADD COLUMN $colProdBarcode TEXT');
      }
    }
    if (oldVersion < 24) {
      debugPrint('DB Upgrade: Adding is_prepared_for_shipment to tbl_sales_orders (v24)');
      try {
        await db.execute(
            'ALTER TABLE $tableOrders ADD COLUMN $colIsPreparedForShipment INTEGER DEFAULT 0');
      } catch (e) {
        debugPrint("Migration error v24: $e");
      }
    }

    if (oldVersion < 25) {
      debugPrint('DB Upgrade: Adding is_validated to tbl_sales_order_details (v25)');
      try {
        await db.execute(
            'ALTER TABLE $tableDetails ADD COLUMN $colDetIsValidated INTEGER DEFAULT 0');
      } catch (e) {
        debugPrint("Migration error v25: $e");
      }
    }

    if (oldVersion < 26) {
      debugPrint('DB Upgrade: Creating Label Audits table (v26)');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableLabelAudits (
          $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
          $colLabelId TEXT UNIQUE,
          $colReferenceNumber TEXT,
          $colLabelType TEXT,
          $colProductCode TEXT,
          $colCustomerName TEXT,
          $columnQuantity REAL,
          $colManifestJson TEXT,
          $colPrintedBy TEXT,
          $colCreatedAt TEXT,
          $columnIsSynced INTEGER NOT NULL DEFAULT 0
        )
      ''');
    }

    if (oldVersion < 27) {
      debugPrint('DB Upgrade: Creating Global Settings table (v27)');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableGlobalSettings (
          $colSettingKey TEXT PRIMARY KEY,
          $colSettingValue TEXT,
          $colSettingIsSynced INTEGER NOT NULL DEFAULT 0,
          $colSettingLastUpdated TEXT,
          $colSettingUpdatedBy TEXT
        )
      ''');
    }

    if (oldVersion < 28) {
      debugPrint('DB Upgrade: Adding UpdatedBy to Global Settings (v28)');
      try {
        await db.execute('ALTER TABLE $tableGlobalSettings ADD COLUMN $colSettingUpdatedBy TEXT');
      } catch (e) {
        debugPrint(e.toString());
      }
    }

    if (oldVersion < 29) {
      debugPrint('DB Upgrade: Converting Global Settings to append-only ledger (v29)');
      await db.execute('ALTER TABLE $tableGlobalSettings RENAME TO ${tableGlobalSettings}_old');
      await db.execute('''
        CREATE TABLE $tableGlobalSettings (
          $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
          $colSettingKey TEXT,
          $colSettingValue TEXT,
          $colSettingIsSynced INTEGER NOT NULL DEFAULT 0,
          $colSettingLastUpdated TEXT,
          $colSettingUpdatedBy TEXT,
          $colSettingAction TEXT
        )
      ''');
      await db.execute('''
        INSERT INTO $tableGlobalSettings ($colSettingKey, $colSettingValue, $colSettingIsSynced, $colSettingLastUpdated, $colSettingUpdatedBy, $colSettingAction)
        SELECT $colSettingKey, $colSettingValue, $colSettingIsSynced, $colSettingLastUpdated, $colSettingUpdatedBy, 'INSERT'
        FROM ${tableGlobalSettings}_old
      ''');
      await db.execute('DROP TABLE ${tableGlobalSettings}_old');
    }
    if (oldVersion < 33) {
      debugPrint('DB Upgrade: Creating Work Orders cache table (v33)');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableWorkOrders (
          $colWoWorkOrder   TEXT PRIMARY KEY,
          $colWoProduct     TEXT,
          $colWoReleasedQty REAL,
          $colWoUnit        TEXT,
          $colWoTrackingNum TEXT,
          $colWoDate        TEXT,
          $colWoCachedAt    TEXT
        )
      ''');
    }

    if (oldVersion < 34) {
      debugPrint('DB Upgrade: Creating Staging EOD table (v34)');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableStagingEod (
          $columnId TEXT PRIMARY KEY,
          $columnSoNumber TEXT,
          $columnProductCode TEXT,
          $columnManufacturedQuantity REAL,
          $columnTimestamp TEXT,
          $colDetUnit TEXT,
          $columnLocationCode TEXT,
          $columnItemStatus TEXT,
          expiryDate TEXT,
          location2 TEXT,
          location3 TEXT,
          createdAt TEXT,
          $columnIsSynced INTEGER DEFAULT 0
        )
      ''');
    }

    if (oldVersion < 35) {
      debugPrint('DB Upgrade: Creating EOD Status and Offline Audit tables (v35)');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableEodStatus (
          productionDate TEXT PRIMARY KEY,
          workOrder TEXT,
          completedAt TEXT,
          completedBy TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableOfflineAuditLogs (
          $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
          entity TEXT,
          action TEXT,
          payload TEXT,
          timestamp TEXT,
          $columnIsSynced INTEGER DEFAULT 0
        )
      ''');
    }

    if (oldVersion < 36) {
      debugPrint('DB Upgrade: Adding customer info to details table (v36)');
      try {
        await db.execute('ALTER TABLE $tableDetails ADD COLUMN $colDetCustomerCode TEXT');
        await db.execute('ALTER TABLE $tableDetails ADD COLUMN $colDetCustomerName TEXT');
      } catch (e) {
      }
    }
    if (oldVersion < 37) {
      debugPrint('DB Upgrade: Adding salesman column to tbl_sales_orders (v37)');
      try {
        await db.execute('ALTER TABLE $tableOrders ADD COLUMN $colSalesman TEXT');
      } catch (e) {
        debugPrint("Migration error v37: $e");
      }
    }

    if (oldVersion < 38) {
      debugPrint('DB Upgrade: Adding rep0/rep1 columns to tbl_sales_orders (v38)');
      try {
        await db.execute('ALTER TABLE $tableOrders ADD COLUMN $colRep0 TEXT');
        await db.execute('ALTER TABLE $tableOrders ADD COLUMN $colRep1 TEXT');
      } catch (e) {
        debugPrint("Migration error v38: $e");
      }
    }

    if (oldVersion < 39) {
      debugPrint('DB Upgrade: Adding EA quantity tracking (v39)');
      try {
        await db.execute('ALTER TABLE $tableScans ADD COLUMN $columnEaQuantity REAL DEFAULT 0');
        await db.execute('ALTER TABLE $tableDetails ADD COLUMN $colDetEaScanned REAL DEFAULT 0');
      } catch (e) {
        debugPrint("Migration error v39: $e");
      }
    }
    if (oldVersion < 41) {
      debugPrint('DB Upgrade: Ensuring ea_quantity exists in tbl_staging_eod (v41)');
      try {
        var columns = await db.rawQuery('PRAGMA table_info($tableStagingEod)');
        if (!columns.any((c) => c['name'] == columnEaQuantity)) {
          await db.execute('ALTER TABLE $tableStagingEod ADD COLUMN $columnEaQuantity REAL DEFAULT 0');
        }
      } catch (e) {
        debugPrint("Migration error v41: $e");
      }
    }
    if (oldVersion < 42) {
      debugPrint('DB Upgrade: Adding barcode column to tbl_scans (v42)');
      try {
        await db.execute('ALTER TABLE $tableScans ADD COLUMN $columnBarcode TEXT');
      } catch (e) {
        debugPrint("Migration error v42: $e");
      }
    }
    if (oldVersion < 43) {
      debugPrint('DB Upgrade: Adding createdAt to tbl_sales_order_details (v43)');
      try {
        await db.execute('ALTER TABLE $tableDetails ADD COLUMN $colDetCreatedAt TEXT');
      } catch (e) {
        debugPrint("Migration error v43: $e");
      }
    }
    if (oldVersion < 44) {
      debugPrint('DB Upgrade: Adding deviceId column to Label Audits and Offline Audit Logs (v44)');
      try {
        var labelColumns = await db.rawQuery('PRAGMA table_info($tableLabelAudits)');
        if (!labelColumns.any((c) => c['name'] == 'deviceId')) {
          await db.execute('ALTER TABLE $tableLabelAudits ADD COLUMN deviceId TEXT');
        }
      } catch (e) {
        debugPrint("Migration error v44 label audits: $e");
      }
      try {
        var auditColumns = await db.rawQuery('PRAGMA table_info($tableOfflineAuditLogs)');
        if (!auditColumns.any((c) => c['name'] == 'deviceId')) {
          await db.execute('ALTER TABLE $tableOfflineAuditLogs ADD COLUMN deviceId TEXT');
        }
      } catch (e) {
        debugPrint("Migration error v44 offline audits: $e");
      }
    }
    if (oldVersion < 45) {
      debugPrint('DB Upgrade: Adding lot column to tbl_staging_eod (v45)');
      try {
        var columns = await db.rawQuery('PRAGMA table_info($tableStagingEod)');
        if (!columns.any((c) => c['name'] == columnLot)) {
          await db.execute('ALTER TABLE $tableStagingEod ADD COLUMN $columnLot TEXT');
        }
      } catch (e) {
        debugPrint("Migration error v45: $e");
      }
    }
    if (oldVersion < 46) {
      debugPrint('DB Upgrade: Adding colDeviceId column to tbl_label_audits (v46)');
      try {
        var labelColumns = await db.rawQuery('PRAGMA table_info($tableLabelAudits)');
        if (!labelColumns.any((c) => c['name'] == colDeviceId)) {
          await db.execute('ALTER TABLE $tableLabelAudits ADD COLUMN $colDeviceId TEXT');
        }
      } catch (e) {
        debugPrint("Migration error v46 label audits: $e");
      }
    }
    if (oldVersion < 47) {
      debugPrint('DB Upgrade: Adding colDeviceId to transaction tables (v47)');
      try {
        final tables = [tableScans, tableOrders, tableDetails, tableStagingEod];
        for (final table in tables) {
          var columns = await db.rawQuery('PRAGMA table_info($table)');
          if (!columns.any((c) => c['name'] == colDeviceId)) {
            await db.execute('ALTER TABLE $table ADD COLUMN $colDeviceId TEXT');
          }
        }
      } catch (e) {
        debugPrint("Migration error v47: $e");
      }
    }
    if (oldVersion < 48) {
      debugPrint('DB Upgrade: Creating tableX3SoapAudits (v48)');
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS $tableX3SoapAudits (
            $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
            $columnTimestamp TEXT NOT NULL,
            endpoint TEXT,
            status TEXT,
            message TEXT,
            $colDeviceId TEXT,
            username TEXT
          )
        ''');
      } catch (e) {
        debugPrint("Migration error v48: $e");
      }
    }
    if (oldVersion < 49) {
      debugPrint('DB Upgrade: Creating tableEodProcessAudits (v49)');
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS $tableEodProcessAudits (
            id TEXT PRIMARY KEY,
            eodDate TEXT NOT NULL UNIQUE,
            workOrderNumber TEXT NOT NULL,
            triggeredBy TEXT NOT NULL,
            deviceId TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            isSynced INTEGER NOT NULL DEFAULT 0
          )
        ''');
      } catch (e) {
        debugPrint("Migration error v49: $e");
      }
    }
    if (oldVersion < 50) {
      debugPrint('DB Upgrade: Adding isDeactivated to tableEodProcessAudits (v50)');
      try {
        await db.execute('ALTER TABLE $tableEodProcessAudits ADD COLUMN isDeactivated INTEGER NOT NULL DEFAULT 0');
      } catch (e) {
        debugPrint("Migration error v50: $e");
      }
    }
    if (oldVersion < 51) {
      debugPrint('DB Upgrade: Adding last_sync_time to tableCachedUsers (v51)');
      try {
        await db.execute('ALTER TABLE $tableCachedUsers ADD COLUMN $colLastSyncTime TEXT');
      } catch (e) {
        debugPrint("Migration error v51: $e");
      }
    }
    if (oldVersion < 52) {
      debugPrint('DB Upgrade: Adding targetLorry to tbl_sales_orders (v52)');
      try {
        await db.execute('ALTER TABLE $tableOrders ADD COLUMN $colTargetLorry TEXT');
      } catch (e) {
        debugPrint("Migration error v52: $e");
      }
    }
    if (oldVersion < 53) {
      debugPrint('DB Upgrade: Adding FPP Rollover logic (v53)');
      try {
        await db.execute('ALTER TABLE $tableOrders ADD COLUMN $colExcludeFromEod INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE $tableScans ADD COLUMN $columnExcludeFromEod INTEGER DEFAULT 0');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS $tableOrderRollovers (
            $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
            $colRolloverSoNum TEXT NOT NULL,
            $colRolloverInitialDate TEXT NOT NULL,
            $colRolloverNewDate TEXT NOT NULL,
            $colRolloverTimestamp TEXT NOT NULL,
            $colRolloverIsSynced INTEGER NOT NULL DEFAULT 0,
            $colDeviceId TEXT
          )
        ''');
        await db.execute('ALTER TABLE $tableOrders ADD COLUMN $colIsRolledOver INTEGER DEFAULT 0');
      } catch (e) {
        debugPrint("Migration error v53: $e");
      }
    }
    if (oldVersion < 54) {
      debugPrint('DB Upgrade: Ensuring isRolledOver exists (v54)');
      try {
        var columns = await db.rawQuery('PRAGMA table_info($tableOrders)');
        if (!columns.any((c) => c['name'] == colIsRolledOver)) {
          await db.execute('ALTER TABLE $tableOrders ADD COLUMN $colIsRolledOver INTEGER DEFAULT 0');
        }
        if (!columns.any((c) => c['name'] == colExcludeFromEod)) {
          await db.execute('ALTER TABLE $tableOrders ADD COLUMN $colExcludeFromEod INTEGER DEFAULT 0');
        }
        var scanCols = await db.rawQuery('PRAGMA table_info($tableScans)');
        if (!scanCols.any((c) => c['name'] == columnExcludeFromEod)) {
          await db.execute('ALTER TABLE $tableScans ADD COLUMN $columnExcludeFromEod INTEGER DEFAULT 0');
        }
      } catch (e) {
        debugPrint("Migration error v54: $e");
      }
    }
  }

  Future _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableX3SoapAudits (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnTimestamp TEXT NOT NULL,
        endpoint TEXT,
        status TEXT,
        message TEXT,
        $colDeviceId TEXT,
        username TEXT
      )
    ''');

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
        $columnIsReflected INTEGER NOT NULL DEFAULT 0,
        $columnSyncId TEXT,
        $columnSite TEXT,
        $columnManufacturedQuantity REAL DEFAULT 0,
        $columnLot TEXT,
        $columnEaQuantity REAL DEFAULT 0,
        $columnBarcode TEXT,
        $colDeviceId TEXT,
        $columnExcludeFromEod INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableOrders (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $colOrderNum TEXT UNIQUE,
        $colPoNum TEXT,
        $colOrderDate TEXT,
        $colDeliveryDate TEXT,
        $colCustomerCode TEXT,
        $colCustomerName TEXT,
        $colRep0 TEXT,
        $colRep1 TEXT,
        $colSalesman TEXT,
        $colSite TEXT,
        $colStatus INTEGER,
        $colSource TEXT,
        $colStatusLabel TEXT,
        $columnIsSynced INTEGER NOT NULL DEFAULT 0,
        $colIsPreparedForShipment INTEGER DEFAULT 0,
        $colIsProcessed INTEGER DEFAULT 0,
        $colTargetLorry TEXT,
        $colDeviceId TEXT,
        $colExcludeFromEod INTEGER DEFAULT 0,
        $colIsRolledOver INTEGER DEFAULT 0
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
        $colDetScanned REAL DEFAULT 0,
        remaining REAL DEFAULT 0,
        $colDetSite TEXT,
        $colDetLocation TEXT,
        $colDetLot TEXT,
        $colDetWarehouse TEXT,
        $colDetWarehouseName TEXT,
        $colDetLocationType TEXT,
        $colDetLocationTypeName TEXT,
        $colDetIsPrepared INTEGER DEFAULT 0,
        $colDetIsValidated INTEGER DEFAULT 0,
        $colDetUnit TEXT DEFAULT "KG",
        $colDetCustomerCode TEXT,
        $colDetCustomerName TEXT,
        $colDetEaScanned REAL DEFAULT 0,
        $colDetCreatedAt TEXT,
        $columnIsSynced INTEGER NOT NULL DEFAULT 1,
        $colDeviceId TEXT,
        UNIQUE($colDetSoNum, $colDetItemCode)
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
        $colUserId TEXT,
        $colLastSyncTime TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableSyncHistory (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $colSyncTimestamp TEXT NOT NULL,
        $colSyncStatus TEXT NOT NULL,
        $colSyncMessage TEXT,
        $colSyncCounts TEXT,
        $colSyncSite TEXT
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

    // PERFORMANCE: Index for location lookups by site
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_locations_site ON $tableLocations($colLocSite)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableProducts (
        $colProdCode TEXT PRIMARY KEY,
        $colProdDesc TEXT,
        $colProdStu TEXT,
        $colProdSau TEXT,
        $colProdStandardWeight REAL DEFAULT 0,
        $colProdBarcode TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableSites (
        $colCode TEXT PRIMARY KEY,
        $colName TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableLots (
        $colLotItemCode TEXT,
        $colLotSiteCode TEXT,
        $colLotNumber TEXT,
        PRIMARY KEY ($colLotItemCode, $colLotSiteCode, $colLotNumber)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableLabelAudits (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $colLabelId TEXT UNIQUE,
        $colReferenceNumber TEXT,
        $colLabelType TEXT,
        $colProductCode TEXT,
        $colCustomerName TEXT,
        $columnQuantity REAL,
        $colManifestJson TEXT,
        $colPrintedBy TEXT,
        $colCreatedAt TEXT,
        $colDeviceId TEXT,
        $columnIsSynced INTEGER NOT NULL DEFAULT 0

      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableGlobalSettings (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $colSettingKey TEXT,
        $colSettingValue TEXT,
        $colSettingIsSynced INTEGER NOT NULL DEFAULT 0,
        $colSettingLastUpdated TEXT,
        $colSettingUpdatedBy TEXT,
        $colSettingAction TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableDeliveryScans (
        $colDelScanPayload TEXT,
        $colDelScanSoNumber TEXT,
        $colDelScanTimestamp TEXT,
        PRIMARY KEY ($colDelScanPayload, $colDelScanSoNumber)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableWorkOrders (
        $colWoWorkOrder   TEXT PRIMARY KEY,
        $colWoProduct     TEXT,
        $colWoReleasedQty REAL,
        $colWoUnit        TEXT,
        $colWoTrackingNum TEXT,
        $colWoDate        TEXT,
        $colWoCachedAt    TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableStagingEod (
        $columnId TEXT PRIMARY KEY,
        $columnSoNumber TEXT,
        $columnProductCode TEXT,
        $columnManufacturedQuantity REAL,
        $columnTimestamp TEXT,
        $colDetUnit TEXT,
        $columnLocationCode TEXT,
        $columnItemStatus TEXT,
        expiryDate TEXT,
        location2 TEXT,
        location3 TEXT,
        createdAt TEXT,
        $columnEaQuantity REAL DEFAULT 0,
        $columnLot TEXT,
        $columnIsSynced INTEGER DEFAULT 0,
        $colDeviceId TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableEodStatus (
        productionDate TEXT PRIMARY KEY,
        workOrder TEXT,
        completedAt TEXT,
        completedBy TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableOfflineAuditLogs (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        entity TEXT,
        action TEXT,
        payload TEXT,
        timestamp TEXT,
        deviceId TEXT,
        $columnIsSynced INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableEodProcessAudits (
        id TEXT PRIMARY KEY,
        eodDate TEXT NOT NULL UNIQUE,
        workOrderNumber TEXT NOT NULL,
        triggeredBy TEXT NOT NULL,
        deviceId TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        isSynced INTEGER NOT NULL DEFAULT 0,
        isDeactivated INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  // Insert a scan record
  Future<int> insertScan(Map<String, dynamic> row) async {
    Database db = await instance.database;
    final id = await db.insert(tableScans, row);
    
    try {
      await insertOfflineAuditLog(
        entity: 'ProductionScan',
        action: 'INSERT',
        payload: jsonEncode({
          'barcode': row[columnBarcode],
          'manufacturedQty': row[columnManufacturedQuantity] ?? row[columnQuantity],
          'eaQuantity': row[columnEaQuantity] ?? 0.0,
          'syncId': row[columnSyncId],
          'soNumber': row[columnSoNumber],
          'productCode': row[columnProductCode],
          'timestamp': row[columnTimestamp] ?? DateTime.now().toIso8601String(),
        }),
      );
    } catch (e) {
      debugPrint("Failed to automatically audit scan insertion: $e");
    }
    
    return id;
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

  // Staging EOD methods
  Future<int> insertStagingEod(Map<String, dynamic> row) async {
    Database db = await instance.database;
    return await db.insert(tableStagingEod, row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getUnsyncedStagingEod() async {
    Database db = await instance.database;
    return await db.query(
      tableStagingEod,
      where: '$columnIsSynced = ?',
      whereArgs: [0],
    );
  }

  Future<int> markStagingEodAsSynced(List<String> ids) async {
    if (ids.isEmpty) return 0;
    Database db = await instance.database;
    String placeholders = List.generate(ids.length, (index) => '?').join(', ');
    return await db.update(
      tableStagingEod,
      {columnIsSynced: 1},
      where: '$columnId IN ($placeholders)',
      whereArgs: ids,
    );
  }

  /// Deletes all unsynced staging EOD rows for a given Work Order.
  /// Called before re-confirming EOD to avoid duplicate snapshots accumulating locally.
  Future<int> deleteUnsyncedStagingEodByWorkOrder(String workOrder) async {
    Database db = await instance.database;
    return await db.delete(
      tableStagingEod,
      where: 'soNumber = ? AND $columnIsSynced = ?',
      whereArgs: [workOrder, 0],
    );
  }

  // Work Order methods
  Future<int> insertWorkOrder(Map<String, dynamic> row) async {
    Database db = await instance.database;
    return await db.insert(tableWorkOrders, row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getAllWorkOrders() async {
    Database db = await instance.database;
    return await db.query(tableWorkOrders, orderBy: '$colWoDate DESC');
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
        det.$colDetIsPrepared,
        det.$colDetIsValidated,
        prod.$colProdSau as masterUnit,
        ord.$colStatus as headerStatus,
        ord.$colStatusLabel as headerStatusLabel,
        ord.$colIsPreparedForShipment as headerIsPreparedForShipment,
        COALESCE(det.$colDetCustomerName, ord.$colCustomerName) as customerName,
        COALESCE(det.$colDetCustomerCode, ord.$colCustomerCode) as customerCode,
        ord.$colRep1 as rep1,
        ord.$colRep0 as rep0,
        ord.$colSalesman as salesmanName,
        (COALESCE(det.$colDetScanned, 0) + COALESCE(SUM(CASE WHEN scn.$columnItemStatus IN ('A', 'DELETED_ORIGINAL', 'REVERSED') THEN scn.$columnQuantity ELSE 0 END), 0)) as reconciledProduced,
        (COALESCE(det.$colDetScanned, 0) + COALESCE(SUM(CASE WHEN scn.$columnItemStatus IN ('A', 'DELETED_ORIGINAL', 'REVERSED') THEN scn.$columnManufacturedQuantity ELSE 0 END), 0)) as reconciledManufactured,
        (COALESCE(det.$colDetEaScanned, 0) + COALESCE(SUM(CASE WHEN scn.$columnItemStatus IN ('A', 'DELETED_ORIGINAL', 'REVERSED') THEN scn.$columnEaQuantity ELSE 0 END), 0)) as reconciledEaQuantity,
        (COALESCE(det.$colDetQuantity, 0) - (COALESCE(det.$colDetScanned, 0) + COALESCE(SUM(CASE WHEN scn.$columnItemStatus IN ('A', 'DELETED_ORIGINAL', 'REVERSED') THEN scn.$columnManufacturedQuantity ELSE 0 END), 0))) as reconciledRemaining,
        (
          SELECT scn2.$columnLot 
          FROM $tableScans scn2 
          WHERE scn2.$columnSoNumber = det.$colDetSoNum 
            AND scn2.$columnProductCode = det.$colDetItemCode 
            AND scn2.$columnLot IS NOT NULL 
            AND scn2.$columnLot != ''
          ORDER BY scn2.$columnTimestamp DESC 
          LIMIT 1
        ) as latestLot
      FROM $tableDetails det
      LEFT JOIN $tableOrders ord ON det.$colDetSoNum = ord.$colOrderNum
      LEFT JOIN $tableProducts prod ON det.$colDetItemCode = prod.$colProdCode
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

  Future<int> updateOrderStatus(String soNumber, int status) async {
    final db = await instance.database;
    return await db.update(
      tableOrders,
      {
        colStatus: status,
        columnIsSynced: 0,
      },
      where: '$colOrderNum = ?',
      whereArgs: [soNumber],
    );
  }

  Future<List<Map<String, dynamic>>> getUnsyncedOrderClosures() async {
    final db = await instance.database;
    // status = 2 is "Closed"
    return await db.query(
      tableOrders,
      columns: [colOrderNum, colStatus, colExcludeFromEod],
      where: '$columnIsSynced = 0 AND ($colStatus = 2 OR $colExcludeFromEod = 1)',
    );
  }

  Future<void> updateExcludeFromEod(String soNumber, bool exclude) async {
    final db = await instance.database;
    await db.update(
      tableOrders,
      {
        colExcludeFromEod: exclude ? 1 : 0,
        columnIsSynced: 0,
      },
      where: '$colOrderNum = ?',
      whereArgs: [soNumber],
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
    String? site,
    Map<String, int>? counts,
  }) async {
    final db = await instance.database;
    await db.insert(tableSyncHistory, {
      colSyncTimestamp: DateTime.now().toIso8601String(),
      colSyncStatus: status,
      colSyncMessage: message,
      colSyncCounts: counts != null ? jsonEncode(counts) : null,
      colSyncSite: site,
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
    required List<Map<String, dynamic>> products,
    required List<Map<String, dynamic>> sites,
    required List<Map<String, dynamic>> lots,
    List<Map<String, dynamic>>? eodProcessAudits,
    bool incremental = true,
  }) async {
    Database db = await instance.database;

    await db.transaction((txn) async {
      // 0. FETCH DIRTY RECORDS to preserve local state
      // We must not overwrite isPrepared=1 if it hasn't been synced yet, 
      // even if the server refresh (which is eventually consistent) says isPrepared=0.
      final dirtyDetails = await txn.query(
        tableDetails,
        where: '$columnIsSynced = 0',
      );
      final Map<String, Map<String, dynamic>> dirtyDetailsMap = {
        for (var d in dirtyDetails)
          '${d[colDetSoNum]}_${d[colDetItemCode]}': d,
      };

      final dirtyOrders = await txn.query(
        tableOrders,
        where: '$columnIsSynced = 0 AND $colIsPreparedForShipment = 1',
      );
      final Map<String, Map<String, dynamic>> dirtyOrdersMap = {
        for (var o in dirtyOrders)
          o[colOrderNum] as String: o,
      };

      // 1. SELECTIVE CLEANUP (or full wipe if not incremental)
      if (!incremental) {
        // Full wipe if requested
        await txn.delete(tableOrders);
        await txn.delete(tableDetails);
        await txn.delete(tableCustomers);
        await txn.delete(tableReps);
        await txn.delete(tableLocations);
        await txn.delete(tableProducts);
        await txn.delete(tableSites);
        await txn.delete(tableLots);
        await txn.delete(tableEodProcessAudits);
      }

      // 2. Batch Insert new data (UPSERT via ConflictAlgorithm.replace)
      Batch batch = txn.batch();

      try {
        for (var order in orders) {
          final record = Map<String, dynamic>.from(order);
          final soNum = record[colOrderNum];

          if (dirtyOrdersMap.containsKey(soNum)) {
            // MERGE: Preserve local dirty isPreparedForShipment, status and isSynced status
            final local = dirtyOrdersMap[soNum]!;
            record[colIsPreparedForShipment] = local[colIsPreparedForShipment];
            record[colStatus] = local[colStatus];
            record[columnIsSynced] = 0;
          }

          batch.insert(
            tableOrders,
            record,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        for (var detail in details) {
          // CLONE to avoid mutating the original processedData list if used elsewhere
          final record = Map<String, dynamic>.from(detail);
          
          final key = '${record[colDetSoNum]}_${record[colDetItemCode]}';
          if (dirtyDetailsMap.containsKey(key)) {
            // MERGE: Preserve local dirty isPrepared, isValidated and isSynced status
            final local = dirtyDetailsMap[key]!;
            record[colDetIsPrepared] = local[colDetIsPrepared];
            record[colDetIsValidated] = local[colDetIsValidated];
            record[columnIsSynced] = 0; 
          } else {
            // New or clean record: ensure it's marked as synced
            record[columnIsSynced] = 1;
          }

          batch.insert(
            tableDetails,
            record,
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
        for (var product in products) {
          batch.insert(
            tableProducts,
            product,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        for (var site in sites) {
          batch.insert(
            tableSites,
            site,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        for (var lot in lots) {
          batch.insert(
            tableLots,
            lot,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        if (eodProcessAudits != null) {
          for (var audit in eodProcessAudits) {
            batch.insert(
              tableEodProcessAudits,
              {
                'id': audit['id'],
                'eodDate': audit['eodDate'],
                'workOrderNumber': audit['workOrderNumber'],
                'triggeredBy': audit['triggeredBy'],
                'deviceId': audit['deviceId'],
                'timestamp': audit['createdAt'] ?? audit['timestamp'] ?? DateTime.now().toIso8601String(),
                'isSynced': 1,
                'isDeactivated': audit['isDeactivated'] ?? 0,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }

        await batch.commit(noResult: true);
        debugPrint(
          "Data Sync Storage: ${incremental ? 'Incremental' : 'Full'} refresh complete. Inserted ${orders.length} orders, ${details.length} details, ${products.length} products, ${sites.length} sites and ${lots.length} lots.",
        );
      } catch (e) {
        debugPrint("CRITICAL: Error during batch insertion: $e");
        rethrow;
      }
    });
  }

  Future<bool> isValidProduct(String code) async {
    final db = await instance.database;
    final results = await db.query(
      tableProducts,
      where: '$colProdCode = ?',
      whereArgs: [code],
    );
    return results.isNotEmpty || code == 'BLK' || code == 'CUT';
  }
  Future<Map<String, dynamic>?> getProductByCode(String code) async {
    final db = await instance.database;
    final results = await db.query(
      tableProducts,
      where: '$colProdCode = ?',
      whereArgs: [code],
    );
    if (results.isEmpty) return null;
    return results.first;
  }

  Future<List<Map<String, dynamic>>> getSites() async {
    Database db = await instance.database;
    return await db.query(tableSites);
  }

  Future<List<String>> getLotsForItemAndSite(String itemCode, String siteCode) async {
    Database db = await instance.database;
    final results = await db.query(
      tableLots,
      columns: [colLotNumber],
      where: '$colLotItemCode = ? AND $colLotSiteCode = ?',
      whereArgs: [itemCode, siteCode],
    );
    return results.map((row) => row[colLotNumber] as String).toList();
  }

  // Preparation Status Sync Methods
  Future<List<Map<String, dynamic>>> getUnsyncedPreparationStatuses() async {
    final db = await instance.database;
    return await db.query(
      tableDetails,
      columns: [colDetSoNum, colDetItemCode, colDetIsPrepared, colDetIsValidated],
      where: '$columnIsSynced = 0',
    );
  }

  Future<List<Map<String, dynamic>>> getUnsyncedShipmentPreparation() async {
    final db = await instance.database;
    return await db.query(
      tableOrders,
      columns: [colOrderNum, colIsPreparedForShipment],
      where: '$columnIsSynced = 0 AND $colIsPreparedForShipment = 1',
    );
  }

  Future<void> markDetailsAsSynced(List<Map<String, dynamic>> updates) async {
    final db = await instance.database;
    Batch batch = db.batch();
    for (var update in updates) {
      batch.update(
        tableDetails,
        {columnIsSynced: 1},
        where: '$colDetSoNum = ? AND $colDetItemCode = ?',
        whereArgs: [update['soNumber'], update['itemCode']],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> markOrderPreparationAsSynced(List<Map<String, dynamic>> updates) async {
    final db = await instance.database;
    Batch batch = db.batch();
    for (var update in updates) {
      batch.update(
        tableOrders,
        {columnIsSynced: 1},
        where: '$colOrderNum = ?',
        whereArgs: [update['soNumber']],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> bulkUpdateItemStatus({
    required String soNumber,
    required List<String> itemCodes,
    required bool status,
    bool isValidation = false,
  }) async {
    final db = await instance.database;
    final column = isValidation ? colDetIsValidated : colDetIsPrepared;
    final value = status ? 1 : 0;

    await db.transaction((txn) async {
      Batch batch = txn.batch();
      for (var itemCode in itemCodes) {
        batch.update(
          tableDetails,
          {
            column: value,
            columnIsSynced: 0,
          },
          where: '$colDetSoNum = ? AND $colDetItemCode = ?',
          whereArgs: [soNumber, itemCode],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  // --- INTERLINKED FILTER LOOKUPS ---

  Future<List<Map<String, dynamic>>> getFilteredSites(String dateStr) async {
    final db = await instance.database;
    // We join with tableSites to get the site name
    return await db.rawQuery('''
      SELECT DISTINCT s.$colCode, s.$colName
      FROM $tableOrders o
      INNER JOIN $tableSites s ON o.$colSite = s.$colCode
      WHERE o.$colDeliveryDate LIKE ?
      ORDER BY s.$colName
    ''', ['$dateStr%']);
  }

  Future<List<Map<String, dynamic>>> getFilteredSalesReps(String dateStr, String? siteCode, String? poType) async {
    final db = await instance.database;
    String whereClause = 'o.$colDeliveryDate LIKE ?';
    List<dynamic> args = ['$dateStr%'];

    if (siteCode != null && siteCode.isNotEmpty) {
      whereClause += ' AND o.$colSite = ?';
      args.add(siteCode);
    }

    if (poType != null && poType != 'ALL') {
      if (poType == 'POD') {
        whereClause += ' AND o.$colPoNum LIKE ?';
        args.add('%POD%');
      } else if (poType == 'PTT') {
        whereClause += ' AND o.$colPoNum LIKE ?';
        args.add('%PTT%');
      } else if (poType == 'EXCESS') {
        whereClause += ' AND (o.$colOrderNum LIKE ? OR o.$colOrderNum LIKE ? OR LOWER(o.$colSource) = ?)';
        args.add('CUTS-%');
        args.add('BLK-%');
        args.add('internal');
      }
    }

    // Try to get distinct values from the unified colSalesman first
    final List<Map<String, dynamic>> fromOrders = await db.rawQuery('''
      SELECT DISTINCT o.$colSalesman AS code, o.$colSalesman AS name
      FROM $tableOrders o
      WHERE $whereClause AND o.$colSalesman IS NOT NULL AND o.$colSalesman != ''
      ORDER BY o.$colSalesman
    ''', args);

    if (fromOrders.isNotEmpty) {
      return fromOrders;
    }

    // Fallback to tableReps join for legacy data or when unified salesman is not populated
    return await db.rawQuery('''
      SELECT DISTINCT r.$colCode AS code, r.$colName AS name
      FROM $tableOrders o
      INNER JOIN $tableReps r ON (o.$colRep1 = r.$colCode OR o.$colRep0 = r.$colCode)
      WHERE $whereClause
      ORDER BY r.$colName
    ''', args);
  }

  Future<List<Map<String, dynamic>>> getFilteredCustomers(
    String dateStr,
    String? siteCode,
    String? salesmanCode,
    String? poType,
  ) async {
    final db = await instance.database;
    String whereClause = 'o.$colDeliveryDate LIKE ?';
    List<dynamic> args = ['$dateStr%'];

    if (siteCode != null && siteCode.isNotEmpty) {
      whereClause += ' AND o.$colSite = ?';
      args.add(siteCode);
    }

    if (poType != null && poType != 'ALL') {
      if (poType == 'POD') {
        whereClause += ' AND o.$colPoNum LIKE ?';
        args.add('%POD%');
      } else if (poType == 'PTT') {
        whereClause += ' AND o.$colPoNum LIKE ?';
        args.add('%PTT%');
      } else if (poType == 'EXCESS') {
        whereClause += ' AND (o.$colOrderNum LIKE ? OR o.$colOrderNum LIKE ? OR LOWER(o.$colSource) = ?)';
        args.add('CUTS-%');
        args.add('BLK-%');
        args.add('internal');
      }
    }

    if (salesmanCode != null && salesmanCode.isNotEmpty) {
      whereClause += ' AND (o.$colRep1 = ? OR o.$colRep0 = ? OR o.$colSalesman = ?)';
      args.add(salesmanCode);
      args.add(salesmanCode);
      args.add(salesmanCode);
    }

    // Customer name is already in the orders table
    return await db.rawQuery('''
      SELECT DISTINCT o.$colCustomerCode AS $colCode, o.$colCustomerName AS $colName
      FROM $tableOrders o
      WHERE $whereClause
      ORDER BY o.$colCustomerName
    ''', args);
  }

  /// Calculates available excess from virtual orders (BLK, CUTS) matching the delivery date.
  Future<List<Map<String, dynamic>>> getExcessPools({
    required String dateStr,
    required String itemCode,
  }) async {
    final db = await instance.database;
    // We look for orders starting with BLK, or CUTS matching the same delivery date.
    // poolQty: Total quantity scanned into the bulk order.
    // allocatedQty: Total quantity already "drawn" from this bulk order into real orders.
    return await db.rawQuery('''
      SELECT 
        o.$colOrderNum AS soNumber,
        (SELECT MAX(
            COALESCE(SUM(d.$colDetScanned), 0),
            (SELECT COALESCE(SUM(s2.$columnQuantity), 0)
             FROM $tableScans s2
             WHERE s2.$columnSoNumber = o.$colOrderNum
               AND s2.$columnProductCode = ?
               AND (s2.$columnBarcode IS NULL OR s2.$columnBarcode NOT LIKE 'ALLOC-OUT-%')
               AND s2.$columnItemStatus NOT IN ('DELETED_ORIGINAL', 'REVERSED'))
         )
         FROM $tableDetails d 
         WHERE d.$colDetSoNum = o.$colOrderNum 
           AND d.$colDetItemCode = ?) AS poolQty,
        (SELECT COALESCE(SUM(-s.$columnQuantity), 0) 
         FROM $tableScans s 
         WHERE s.$columnSoNumber = o.$colOrderNum
           AND s.$columnItemStatus NOT IN ('DELETED_ORIGINAL', 'REVERSED')
           AND s.$columnBarcode LIKE 'ALLOC-OUT-%'
           AND s.$columnProductCode = ?) AS allocatedQty
      FROM $tableOrders o
      WHERE (o.$colOrderNum LIKE 'BLK-%' 
          OR o.$colOrderNum LIKE 'CUTS-%')
        AND o.$colDeliveryDate LIKE ?
    ''', [itemCode, itemCode, itemCode, '$dateStr%']);
  }
  /// Calculates aggregated availability (Produced - Allocated) for all bulk products on a date.
  Future<Map<String, double>> getExcessPoolSummaries(String dateStr) async {
    final db = await instance.database;
    final List<Map<String, dynamic>> results = await db.rawQuery('''
      SELECT 
        d.$colDetItemCode AS productCode,
        SUM(
          MAX(
            d.$colDetScanned,
            (SELECT COALESCE(SUM(s.$columnQuantity), 0)
             FROM $tableScans s
             WHERE s.$columnSoNumber = o.$colOrderNum 
               AND s.$columnProductCode = d.$colDetItemCode 
               AND (s.$columnBarcode IS NULL OR s.$columnBarcode NOT LIKE 'ALLOC-OUT-%') 
               AND s.$columnItemStatus NOT IN ('DELETED_ORIGINAL', 'REVERSED'))
          )
        ) AS poolQty,
        COALESCE(alloc.allocatedQty, 0) AS allocatedQty
      FROM $tableDetails d
      INNER JOIN $tableOrders o ON d.$colDetSoNum = o.$colOrderNum
      LEFT JOIN (
        SELECT 
          s.$columnProductCode,
          SUM(-s.$columnQuantity) AS allocatedQty
        FROM $tableScans s
        INNER JOIN $tableOrders o2 ON s.$columnSoNumber = o2.$colOrderNum
        WHERE (o2.$colOrderNum LIKE 'BLK-%' OR o2.$colOrderNum LIKE 'CUTS-%')
          AND o2.$colDeliveryDate LIKE ?
          AND s.$columnBarcode LIKE 'ALLOC-OUT-%'
          AND s.$columnItemStatus NOT IN ('DELETED_ORIGINAL', 'REVERSED')
        GROUP BY s.$columnProductCode
      ) alloc ON alloc.$columnProductCode = d.$colDetItemCode
      WHERE (o.$colOrderNum LIKE 'BLK-%' OR o.$colOrderNum LIKE 'CUTS-%')
        AND o.$colDeliveryDate LIKE ?
      GROUP BY d.$colDetItemCode
    ''', ['$dateStr%', '$dateStr%']);

    final Map<String, double> summaries = {};
    for (var row in results) {
      final double pool = (row['poolQty'] as num).toDouble();
      final double allocated = (row['allocatedQty'] as num).toDouble();
      final double available = pool - allocated;
      if (available > 0.001) {
        summaries[row['productCode'] as String] = available;
      }
    }
    return summaries;
  }

  /// Finds all normal orders (not BLK/CUTS) that have items matching an available excess pool on their delivery date.
  Future<Set<String>> getOrdersWithExcessAvailable() async {
    final db = await instance.database;
    final List<Map<String, dynamic>> results = await db.rawQuery('''
      SELECT DISTINCT det.$colDetSoNum AS soNumber
      FROM $tableDetails det
      INNER JOIN $tableOrders ord ON det.$colDetSoNum = ord.$colOrderNum
      INNER JOIN (
        SELECT 
          d.$colDetItemCode AS productCode,
          o.$colDeliveryDate AS deliveryDate,
          SUM(
            MAX(
              d.$colDetScanned,
              (SELECT COALESCE(SUM(s.$columnQuantity), 0)
               FROM $tableScans s
               WHERE s.$columnSoNumber = o.$colOrderNum 
                 AND s.$columnProductCode = d.$colDetItemCode 
                 AND (s.$columnBarcode IS NULL OR s.$columnBarcode NOT LIKE 'ALLOC-OUT-%') 
                 AND s.$columnItemStatus NOT IN ('DELETED_ORIGINAL', 'REVERSED'))
            )
          ) AS poolQty,
          COALESCE(alloc.allocatedQty, 0) AS allocatedQty
        FROM $tableDetails d
        INNER JOIN $tableOrders o ON d.$colDetSoNum = o.$colOrderNum
        LEFT JOIN (
          SELECT 
            s.$columnProductCode,
            o2.$colDeliveryDate,
            SUM(-s.$columnQuantity) AS allocatedQty
          FROM $tableScans s
          INNER JOIN $tableOrders o2 ON s.$columnSoNumber = o2.$colOrderNum
          WHERE (o2.$colOrderNum LIKE 'BLK-%' OR o2.$colOrderNum LIKE 'CUTS-%')
            AND s.$columnBarcode LIKE 'ALLOC-OUT-%'
            AND s.$columnItemStatus NOT IN ('DELETED_ORIGINAL', 'REVERSED')
          GROUP BY s.$columnProductCode, o2.$colDeliveryDate
        ) alloc ON alloc.$columnProductCode = d.$colDetItemCode AND alloc.$colDeliveryDate = o.$colDeliveryDate
        WHERE (o.$colOrderNum LIKE 'BLK-%' OR o.$colOrderNum LIKE 'CUTS-%')
        GROUP BY d.$colDetItemCode, o.$colDeliveryDate
      ) pools ON det.$colDetItemCode = pools.productCode AND ord.$colDeliveryDate = pools.deliveryDate
      WHERE (pools.poolQty - pools.allocatedQty) > 0.001
        AND ord.$colOrderNum NOT LIKE 'BLK-%'
        AND ord.$colOrderNum NOT LIKE 'CUTS-%'
    ''');
    
    return results.map((r) => r['soNumber'] as String).toSet();
  }

  // --- LABEL AUDIT METHODS ---

  Future<int> insertLabelAudit(Map<String, dynamic> audit) async {
    final db = await instance.database;
    final row = Map<String, dynamic>.from(audit);
    
    // Retrieve username and device ID
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username') ?? 'unknown';
    final deviceId = DeviceInfoService.instance.deviceInfo;
    
    row[colDeviceId] = deviceId;
    row[colPrintedBy] = '$username on $deviceId';
    
    return await db.insert(
      tableLabelAudits,
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }


  Future<List<Map<String, dynamic>>> getUnsyncedLabelAudits() async {
    final db = await instance.database;
    return await db.query(
      tableLabelAudits,
      where: '$columnIsSynced = ?',
      whereArgs: [0],
    );
  }

  Future<int> markLabelAuditsSynced(List<String> labelIds) async {
    if (labelIds.isEmpty) return 0;
    final db = await instance.database;
    final placeholders = List.generate(labelIds.length, (index) => '?').join(', ');
    return await db.update(
      tableLabelAudits,
      {columnIsSynced: 1},
      where: '$colLabelId IN ($placeholders)',
      whereArgs: labelIds,
    );
  }

  // --- GLOBAL SETTINGS HELPERS ---

  Future<List<Map<String, dynamic>>> getAllGlobalSettings() async {
    final db = await instance.database;
    // Returns the most recent record for each setting key
    return await db.rawQuery('''
      SELECT * FROM (
        SELECT * FROM $tableGlobalSettings ORDER BY $colSettingLastUpdated DESC
      ) GROUP BY $colSettingKey
    ''');
  }

  Future<void> updateGlobalSetting(String key, String value, {bool isSynced = false, String? updatedBy}) async {
    final db = await instance.database;
    await db.insert(
      tableGlobalSettings,
      {
        colSettingKey: key,
        colSettingValue: value,
        colSettingIsSynced: isSynced ? 1 : 0,
        colSettingLastUpdated: DateTime.now().toIso8601String(),
        colSettingUpdatedBy: updatedBy,
        colSettingAction: 'INSERT',
      },
      // Removed conflict algorithm to ensure it always inserts a new row (ledger)
    );
  }

  Future<int> getGlobalSettingsUnsyncedCount() async {
    final db = await instance.database;
    try {
      final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $tableGlobalSettings WHERE $colSettingIsSynced = 0')
      );
      return count ?? 0;
    } catch (e) {
      debugPrint("Error getting settings unsynced count: $e");
      return 0;
    }
  }

  // ==========================================
  // DELIVERY SCAN METHODS
  // ==========================================

  Future<bool> insertDeliveryScan(String qrPayload, List<String> soNumbers) async {
    final db = await instance.database;
    bool anyInserted = false;
    final timestamp = DateTime.now().toIso8601String();
    
    await db.transaction((txn) async {
      for (var so in soNumbers) {
        final id = await txn.insert(
          tableDeliveryScans,
          {
            colDelScanPayload: qrPayload,
            colDelScanSoNumber: so,
            colDelScanTimestamp: timestamp,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        if (id != 0) anyInserted = true;
      }
    });
    return anyInserted; // returns true if it was a new scan, false if it was completely a duplicate
  }

  Future<List<String>> getScannedDeliveryOrders() async {
    final db = await instance.database;
    final result = await db.query(tableDeliveryScans, columns: [colDelScanSoNumber]);
    return result.map((r) => r[colDelScanSoNumber] as String).toSet().toList(); // Unique SO numbers
  }

  Future<void> clearDeliveryScans() async {
    final db = await instance.database;
    await db.delete(tableDeliveryScans);
  }

  Future<List<Map<String, dynamic>>> getUnsyncedGlobalSettings() async {
    final db = await instance.database;
    return await db.query(
      tableGlobalSettings,
      where: '$colSettingIsSynced = 0',
    );
  }

  Future<void> markSettingsAsSynced(List<String> keys) async {
    if (keys.isEmpty) return;
    final db = await instance.database;
    final placeholders = List.generate(keys.length, (i) => '?').join(', ');
    await db.update(
      tableGlobalSettings,
      {colSettingIsSynced: 1},
      where: '$colSettingKey IN ($placeholders)',
      whereArgs: keys,
    );
  }

  Future<List<Map<String, dynamic>>> getProductionSummaryByDate(String dateStr, {String? site}) async {
    final db = await instance.database;
    
    String whereClause = 'ord.$colDeliveryDate LIKE ?';
    List<dynamic> whereArgs = ['$dateStr%'];

    if (site != null && site.isNotEmpty) {
      whereClause += ' AND ord.$colSite = ?';
      whereArgs.add(site);
    }

    final query = '''
      SELECT 
        det.*,
        ord.$colCustomerName as customerName,
        ord.$colCustomerCode as customerCode,
        (COALESCE(det.$colDetScanned, 0) + COALESCE(scn.totalManufacturedQty, 0)) as reconciledManufactured,
        (COALESCE(det.$colDetEaScanned, 0) + COALESCE(scn.totalEaQty, 0)) as reconciledEaQuantity,
        COALESCE(scn.lot, det.$colDetLot) as lot,
        COALESCE(scn.location, det.$colDetLocation) as location,
        COALESCE(scn.timestamp, det.$colDetCreatedAt) as timestamp
      FROM $tableDetails det
      INNER JOIN $tableOrders ord ON det.$colDetSoNum = ord.$colOrderNum
      LEFT JOIN (
        SELECT 
          $columnSoNumber, 
          $columnProductCode, 
          SUM(CASE WHEN $columnIsReflected = 0 THEN $columnManufacturedQuantity ELSE 0 END) as totalManufacturedQty,
          SUM(CASE WHEN $columnIsReflected = 0 THEN $columnEaQuantity ELSE 0 END) as totalEaQty,
          MAX($columnLot) as lot,
          MAX($columnLocationCode) as location,
          MAX($columnTimestamp) as timestamp
        FROM $tableScans
        GROUP BY $columnSoNumber, $columnProductCode
      ) scn ON det.$colDetSoNum = scn.$columnSoNumber 
        AND det.$colDetItemCode = scn.$columnProductCode
      WHERE $whereClause
    ''';

    return await db.rawQuery(query, whereArgs);
  }

  Future<bool> isEodCompleted(String dateStr) async {
    return await isEodProcessAudited(dateStr);
  }

  Future<void> markEodCompleted(String dateStr, String workOrder, {String? completedBy}) async {
    final db = await instance.database;
    await db.insert(
      tableEodStatus,
      {
        'productionDate': dateStr,
        'workOrder': workOrder,
        'completedAt': DateTime.now().toIso8601String(),
        'completedBy': completedBy ?? 'User',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertOfflineAuditLog({
    required String entity,
    required String action,
    required String payload,
  }) async {
    final db = await instance.database;
    await db.insert(tableOfflineAuditLogs, {
      'entity': entity,
      'action': action,
      'payload': payload,
      'timestamp': DateTime.now().toIso8601String(),
      'deviceId': DeviceInfoService.instance.deviceInfo,
      'isSynced': 0,
    });
  }

  Future<List<Map<String, dynamic>>> getUnsyncedOfflineAudits() async {
    final db = await instance.database;
    return await db.query(tableOfflineAuditLogs, where: 'isSynced = 0');
  }

  Future<void> deductFromDetailSummary({
    required String soNumber,
    required String itemCode,
    required double weight,
    required double eaQuantity,
  }) async {
    final db = await instance.database;
    final rows = await db.rawUpdate('''
      UPDATE $tableDetails 
      SET $colDetScanned = COALESCE($colDetScanned, 0) - ?,
          $colDetEaScanned = COALESCE($colDetEaScanned, 0) - ?,
          $columnIsSynced = 0
      WHERE UPPER($colDetSoNum) = UPPER(?) AND UPPER($colDetItemCode) = UPPER(?)
    ''', [weight, eaQuantity, soNumber, itemCode]);
    debugPrint("deductFromDetailSummary: $rows rows updated for $itemCode in $soNumber (marked as unsynced)");
  }

  Future<void> markOfflineAuditsAsSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await instance.database;
    await db.update(
      tableOfflineAuditLogs,
      {'isSynced': 1},
      where: 'id IN (${ids.join(", ")})',
    );
  }

  Future<void> deleteScan(String barcode) async {
    final db = await instance.database;
    await db.delete(
      tableScans,
      where: '$columnBarcode = ?',
      whereArgs: [barcode],
    );
  }

  Future<void> deleteScanBySyncId(String syncId) async {
    final db = await instance.database;
    await db.delete(
      tableScans,
      where: '$columnSyncId = ?',
      whereArgs: [syncId],
    );
  }

  Future<void> updateScanStatusBySyncId(String syncId, String status) async {
    final db = await instance.database;
    await db.update(
      tableScans,
      {columnItemStatus: status, columnIsSynced: 0},
      where: '$columnSyncId = ?',
      whereArgs: [syncId],
    );
  }

  Future<void> insertX3SoapAudit({
    required String endpoint,
    required String status,
    required String message,
  }) async {
    final db = await instance.database;
    final username = await SecureStorageService().getUsername() ?? 'UnknownUser';

    await db.insert(tableX3SoapAudits, {
      columnTimestamp: DateTime.now().toIso8601String(),
      'endpoint': endpoint,
      'status': status,
      'message': message,
      colDeviceId: DeviceInfoService.instance.deviceInfo,
      'username': username,
    });
  }

  Future<List<Map<String, dynamic>>> getLocalProductionScans(String soNumber, String productCode) async {
    final db = await instance.database;
    return await db.query(
      tableScans,
      where: '$columnSoNumber = ? AND $columnProductCode = ?',
      whereArgs: [soNumber, productCode],
      orderBy: '$columnTimestamp DESC',
    );
  }

  Future<void> insertEodProcessAudit({
    required String eodDate,
    required String workOrderNumber,
  }) async {
    final db = await instance.database;
    final username = await SecureStorageService().getUsername() ?? 'UnknownUser';

    await db.insert(
      tableEodProcessAudits,
      {
        'id': const Uuid().v4(),
        'eodDate': eodDate,
        'workOrderNumber': workOrderNumber,
        'triggeredBy': username,
        'deviceId': DeviceInfoService.instance.deviceInfo,
        'timestamp': DateTime.now().toIso8601String(),
        'isSynced': 0,
        'isDeactivated': 1,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }


  Future<bool> isEodProcessAudited(String dateStr) async {
    final db = await instance.database;
    final res = await db.query(
      tableEodProcessAudits,
      where: 'eodDate = ? AND isDeactivated = 1',
      whereArgs: [dateStr],
    );
    return res.isNotEmpty;
  }

  Future<List<Map<String, dynamic>>> getUnsyncedEodProcessAudits() async {
    final db = await instance.database;
    return await db.query(
      tableEodProcessAudits,
      where: 'isSynced = 0',
    );
  }

  Future<void> markEodProcessAuditsSynced(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await instance.database;
    final batch = db.batch();
    for (final id in ids) {
      batch.update(
        tableEodProcessAudits,
        {'isSynced': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    await batch.commit(noResult: true);
  }
}
