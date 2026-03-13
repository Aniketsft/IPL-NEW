import 'package:enterprise_auth_mobile/features/logistics/domain/entities/sales_order.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/entities/sales_order_detail.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/entities/location_lookup.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/entities/sync_progress.dart';

abstract class ILogisticsRepository {
  Future<List<SalesOrder>> fetchSalesOrders({DateTime? date});
  Future<List<SalesOrderDetail>> getSalesOrderDetails(String soNumber);
  Future<List<SalesOrderDetail>> getProductionTracking();
  Future<void> updateSalesOrder(SalesOrder order);
  Future<void> syncScans(List<Map<String, dynamic>> scans);
  Future<void> saveProductionScan(Map<String, dynamic> scan);
  Future<bool> isValidProduct(String code);
  Future<List<SalesOrder>> fetchSalesOrderHeaders({
    String status = 'all',
    DateTime? date,
    String? customerCode,
    String? rep0,
    String? rep1,
    int limit = 100,
    int offset = 0,
  });
  Future<void> closeOrder(String soNumber, String closedBy);
  Future<List<LocationLookup>> getLocationLookups(String site);
  Future<void> synchronize();
  Stream<SyncProgress> synchronizeWithProgress();
}
