import '../entities/sales_order.dart';
import '../../data/repositories/delivery_repository.dart';

class GetSalesOrderHeadersUseCase {
  final DeliveryRepository _repository;

  GetSalesOrderHeadersUseCase(this._repository);

  Future<List<SalesOrder>> execute({
    String status = 'all',
    DateTime? date,
    int limit = 100,
    int offset = 0,
  }) {
    return _repository.fetchSalesOrderHeaders(
      status: status,
      date: date,
      limit: limit,
      offset: offset,
    );
  }
}
