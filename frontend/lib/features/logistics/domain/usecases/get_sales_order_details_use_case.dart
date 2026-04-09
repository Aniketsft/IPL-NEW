import 'package:enterprise_auth_mobile/features/logistics/domain/entities/sales_order_detail.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/repositories/ilogistics_repository.dart';

class GetSalesOrderDetailsUseCase {
  final ILogisticsRepository repository;

  GetSalesOrderDetailsUseCase(this.repository);

  Future<List<SalesOrderDetail>> execute(String soNumber) {
    return repository.getSalesOrderDetails(soNumber);
  }
}
