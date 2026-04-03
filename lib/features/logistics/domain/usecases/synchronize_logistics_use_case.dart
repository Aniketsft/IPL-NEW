import '../repositories/ilogistics_repository.dart';
import '../entities/sync_progress.dart';

class SynchronizeLogisticsUseCase {
  final ILogisticsRepository _repository;

  SynchronizeLogisticsUseCase(this._repository);
  ILogisticsRepository get repository => _repository;

  Future<void> execute({String? siteCode}) async {
    return await _repository.synchronize(siteCode: siteCode);
  }

  Stream<SyncProgress> executeWithProgress({String? siteCode}) {
    return _repository.synchronizeWithProgress(siteCode: siteCode);
  }
}
