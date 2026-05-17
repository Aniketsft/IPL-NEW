import 'package:enterprise_auth_mobile/features/logistics/data/repositories/delivery_repository.dart';

class SetPreparationStatusUseCase {
  final DeliveryRepository _repository;

  SetPreparationStatusUseCase(this._repository);

  Future<void> execute({
    required String soNumber,
    required String itemCode,
    required bool isPrepared,
  }) async {
    return _repository.updateItemPreparationStatus(
      soNumber: soNumber,
      itemCode: itemCode,
      isPrepared: isPrepared,
    );
  }
}
