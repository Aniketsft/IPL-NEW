import 'package:enterprise_auth_mobile/features/logistics/domain/entities/sales_rep.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/repositories/ilogistics_repository.dart';

class GetSalesRepsUseCase {
  final ILogisticsRepository repository;

  GetSalesRepsUseCase(this.repository);

  Future<List<SalesRep>> call() async {
    return await repository.getSalesReps();
  }
}
