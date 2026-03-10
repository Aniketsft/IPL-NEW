import '../repositories/ilogistics_repository.dart';

class SynchronizeLogisticsUseCase {
  final ILogisticsRepository _repository;

  SynchronizeLogisticsUseCase(this._repository);

  Future<void> execute() async {
    return await _repository.synchronize();
  }
}
