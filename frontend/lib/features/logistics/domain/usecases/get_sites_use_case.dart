import 'package:enterprise_auth_mobile/features/logistics/domain/entities/site.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/repositories/ilogistics_repository.dart';

class GetSitesUseCase {
  final ILogisticsRepository repository;

  GetSitesUseCase(this.repository);

  Future<List<Site>> call() async {
    return await repository.getSites();
  }
}
