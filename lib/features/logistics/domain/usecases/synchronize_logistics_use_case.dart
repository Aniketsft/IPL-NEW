import '../repositories/ilogistics_repository.dart';
import '../entities/sync_progress.dart';

class SynchronizeLogisticsUseCase {
  final ILogisticsRepository _repository;

  SynchronizeLogisticsUseCase(this._repository);

  Future<void> execute() async {
    return await _repository.synchronize();
  }

  Stream<SyncProgress> executeWithProgress() {
    return _repository.synchronizeWithProgress();
  }
}
