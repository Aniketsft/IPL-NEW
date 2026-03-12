import 'package:flutter_test/flutter_test.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/product_master_dto.dart';

void main() {
  group('ProductMasterDto', () {
    test('should correctly parse from camelCase JSON', () {
      final json = {
        'productCode': 'PROD001',
        'productDescription': 'Test Product',
        'stockUnit': 'KG',
        'salesUnit': 'KG',
      };

      final dto = ProductMasterDto.fromJson(json);

      expect(dto.productCode, 'PROD001');
      expect(dto.productDescription, 'Test Product');
      expect(dto.stockUnit, 'KG');
      expect(dto.salesUnit, 'KG');
    });

    test('should handle missing fields with default empty strings', () {
      final json = <String, dynamic>{};

      final dto = ProductMasterDto.fromJson(json);

      expect(dto.productCode, '');
      expect(dto.productDescription, '');
      expect(dto.stockUnit, '');
      expect(dto.salesUnit, '');
    });
  });
}
