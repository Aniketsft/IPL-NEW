import 'package:enterprise_auth_mobile/features/logistics/domain/entities/sales_order_detail.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/repositories/ilogistics_repository.dart';

class GetProductionTrackingUseCase {
  final ILogisticsRepository repository;

  GetProductionTrackingUseCase(this.repository);

  Future<Map<String, dynamic>> execute({
    String? siteCode,
    String? customerCode,
    String? salesRepCode,
    DateTime? date,
  }) async {
    final items = await repository.getProductionTracking(
      siteCode: siteCode,
      customerCode: customerCode,
      salesRepCode: salesRepCode,
      date: date,
    );

    final excessPools = await repository.getExcessPoolSummaries(date ?? DateTime.now());

    return {
      'items': items,
      'excessPools': excessPools,
    };
  }
}
