import 'package:enterprise_auth_mobile/features/logistics/domain/entities/sales_order_detail.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/repositories/ilogistics_repository.dart';

class GetProductionTrackingUseCase {
  final ILogisticsRepository repository;

  GetProductionTrackingUseCase(this.repository);

  Future<List<SalesOrderDetail>> execute({String? location}) {
    return repository.getProductionTracking(location: location);
  }
}
