import 'package:enterprise_auth_mobile/features/logistics/domain/entities/customer.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/repositories/ilogistics_repository.dart';

class GetCustomersUseCase {
  final ILogisticsRepository repository;

  GetCustomersUseCase(this.repository);

  Future<List<Customer>> call() async {
    return await repository.getCustomers();
  }
}
