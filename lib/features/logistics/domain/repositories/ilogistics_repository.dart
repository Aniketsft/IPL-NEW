import 'package:enterprise_auth_mobile/features/logistics/domain/entities/sales_order.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/entities/sales_order_detail.dart';

abstract class ILogisticsRepository {
  Future<List<SalesOrder>> fetchSalesOrders({DateTime? date});
  Future<List<SalesOrderDetail>> getSalesOrderDetails(String soNumber);
  Future<List<SalesOrderDetail>> getProductionTracking();
  Future<void> updateSalesOrder(SalesOrder order);
  Future<void> syncScans(List<Map<String, dynamic>> scans);
  Future<void> saveProductionScan(Map<String, dynamic> scan);
  Future<List<SalesOrder>> fetchSalesOrderHeaders({
    String status = 'all',
    DateTime? date,
    String? customerCode,
    String? rep0,
    String? rep1,
  });
  Future<void> closeOrder(String soNumber, String closedBy);
}
