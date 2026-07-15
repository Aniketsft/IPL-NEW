import 'package:enterprise_auth_mobile/features/logistics/domain/entities/sales_order.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/entities/sales_order_detail.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/entities/location_lookup.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/entities/sync_progress.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/entities/site.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/entities/customer.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/entities/sales_rep.dart';

abstract class ILogisticsRepository {
  Future<List<SalesOrder>> fetchSalesOrders({DateTime? date, String? siteCode});
  Future<List<SalesOrderDetail>> getSalesOrderDetails(String soNumber);
  Future<List<SalesOrderDetail>> getProductionTracking({
    String? siteCode,
    String? customerCode,
    String? salesRepCode,
    DateTime? date,
  });
  Future<void> updateSalesOrder(SalesOrder order);
  Future<void> syncScans(List<Map<String, dynamic>> scans, {String? siteCode});
  Future<void> saveProductionScan(Map<String, dynamic> scan);
  Future<void> saveProductionScansBatch(List<Map<String, dynamic>> scans);
  Future<bool> isValidProduct(String code);
  Future<List<SalesOrder>> fetchSalesOrderHeaders({
    String status = 'all',
    DateTime? date,
    String? siteCode,
    String? customerCode,
    String? locationCode,
    String? rep0,
    String? rep1,
    int limit = 100,
    int offset = 0,
  });
  Future<void> closeOrder(String soNumber, String closedBy);
  Future<List<LocationLookup>> getLocationLookups(String site);
  Future<List<LocationLookup>> getTargetLocations(String site, String itemCode);
  Future<void> synchronize({String? siteCode});
  Stream<SyncProgress> synchronizeWithProgress({String? siteCode});
  Future<List<Site>> getSites();
  Future<List<Customer>> getCustomers();
  Future<List<SalesRep>> getSalesReps();
  Future<List<String>> getProductionSites();
  Future<List<String>> getLots(String itemCode, String siteCode);

  // Filtered Lookups
  Future<List<Site>> getFilteredSites({required DateTime date});
  Future<List<SalesRep>> getFilteredSalesReps({
    required DateTime date,
    String? siteCode,
    String? poType,
  });
  Future<List<Customer>> getFilteredCustomers({
    required DateTime date,
    String? siteCode,
    String? salesmanCode,
    String? poType,
  });

  Future<String> saveCutBulkEntry(Map<String, dynamic> entry);
  Future<void> updateItemPreparationStatus({
    required String soNumber,
    required String itemCode,
    required bool isPrepared,
  });
  Future<void> updateShipmentPreparationStatus({
    required String soNumber,
    required bool isPrepared,
  });
  Future<Map<String, dynamic>?> getProductByBarcode(String barcode);
  Future<List<Map<String, dynamic>>> getExcessByDateAndItem(DateTime deliveryDate, String itemCode);
  Future<String> allocateExcess({
    required String sourceBulkSoNumber,
    required String targetSoNumber,
    required String itemCode,
    required double amount,
    String? lot,
    String? location,
    String? siteId,
  });
  Future<Map<String, double>> getExcessPoolSummaries(DateTime date);
  Future<Set<String>> getOrdersWithExcessAvailable();
  Future<String> logLabelAudit(Map<String, dynamic> auditData);
  Future<List<Map<String, String>>> getOpenInternalOrders();
  Future<Map<String, dynamic>> processEndOfDay();
  Future<void> completeProductionEod(String workOrder, List<Map<String, dynamic>> items);
  Future<List<Map<String, dynamic>>> getProductionSummaryFromServer(DateTime date);
}

