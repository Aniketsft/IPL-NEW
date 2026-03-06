import 'package:enterprise_auth_mobile/features/logistics/domain/repositories/ilogistics_repository.dart';

class SyncScansUseCase {
  final ILogisticsRepository repository;

  SyncScansUseCase(this.repository);

  Future<void> execute(List<Map<String, dynamic>> scans) {
    return repository.syncScans(scans);
  }
}
