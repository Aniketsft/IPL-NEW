import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';

class LocalRepository {
  final LocalDatabaseHelper _dbHelper = LocalDatabaseHelper.instance;

  Future<void> saveScan({
    required String soNumber,
    required String productCode,
    required double quantity,
  }) async {
    await _dbHelper.insertScan({
      LocalDatabaseHelper.columnSoNumber: soNumber,
      LocalDatabaseHelper.columnProductCode: productCode,
      LocalDatabaseHelper.columnQuantity: quantity,
      LocalDatabaseHelper.columnTimestamp: DateTime.now().toIso8601String(),
      LocalDatabaseHelper.columnIsSynced: 0,
    });
  }

  Future<List<Map<String, dynamic>>> getUnsyncedScans() async {
    return await _dbHelper.getUnsyncedScans();
  }

  Future<void> markScansAsSynced(List<int> ids) async {
    await _dbHelper.markAsSynced(ids);
  }
}
