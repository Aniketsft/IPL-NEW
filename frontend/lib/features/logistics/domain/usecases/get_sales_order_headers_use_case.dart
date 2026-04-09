import '../entities/sales_order.dart';
import '../../data/repositories/delivery_repository.dart';

class GetSalesOrderHeadersUseCase {
  final DeliveryRepository _repository;

  GetSalesOrderHeadersUseCase(this._repository);

  Future<List<SalesOrder>> execute({
    String status = 'all',
    DateTime? date,
    String? siteCode,
    String? customerCode,
    String? locationCode,
    String? rep0,
    String? rep1,
    int limit = 100,
    int offset = 0,
  }) {
    return _repository.fetchSalesOrderHeaders(
      status: status,
      date: date,
      siteCode: siteCode,
      customerCode: customerCode,
      locationCode: locationCode,
      rep0: rep0,
      rep1: rep1,
      limit: limit,
      offset: offset,
    );
  }
}
