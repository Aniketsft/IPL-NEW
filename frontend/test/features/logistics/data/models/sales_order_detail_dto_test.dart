import 'package:flutter_test/flutter_test.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/sales_order_detail_dto.dart';

void main() {
  group('SalesOrderDetailDto', () {
    test('fromJson should correctly map "manufactured" from JSON to "scannedQuantity"', () {
      final json = {
        'soNumber': 'SO123',
        'itemCode': 'ITEM001',
        'description': 'Test Item',
        'barcodeType': 'Variable Weight',
        'quantity': 100.0,
        'remaining': 20.0,
        'manufactured': 80.0,
      };

      final dto = SalesOrderDetailDto.fromJson(json);

      expect(dto.soNumber, 'SO123');
      expect(dto.scannedQuantity, 80.0);
      expect(dto.remaining, 20.0);
    });

    test('toSqlMap should use "scanned" key for database storage', () {
      final dto = SalesOrderDetailDto(
        soNumber: 'SO123',
        itemCode: 'ITEM001',
        description: 'Test Item',
        barcodeType: 'Variable Weight',
        quantity: 100.0,
        remaining: 20.0,
        scannedQuantity: 80.0,
      );

      final sqlMap = dto.toSqlMap();

      expect(sqlMap['scanned'], 80.0);
      expect(sqlMap.containsKey('manufactured'), isFalse);
    });
  });
}
