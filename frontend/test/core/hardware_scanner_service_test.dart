import 'package:flutter_test/flutter_test.dart';
import 'package:enterprise_auth_mobile/core/utils/barcode_scanner/hardware_scanner_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HardwareScannerService Tests', () {
    late HardwareScannerService scannerService;

    setUp(() {
      scannerService = HardwareScannerService();
    });

    test('is a singleton instance', () {
      final instance1 = HardwareScannerService();
      final instance2 = HardwareScannerService();
      expect(identical(instance1, instance2), isTrue);
    });

    test('simulateScan emits barcode on onScan stream', () async {
      const testBarcode = 'PROD-123456';
      
      expectLater(
        scannerService.onScan,
        emits(testBarcode),
      );

      scannerService.simulateScan(testBarcode);
    });

    test('simulateScan trims whitespace and ignores empty string', () async {
      final received = <String>[];
      final subscription = scannerService.onScan.listen(received.add);

      scannerService.simulateScan('   ');
      scannerService.simulateScan('  ITEM-789  ');

      await Future.delayed(const Duration(milliseconds: 50));
      await subscription.cancel();

      expect(received, equals(['ITEM-789']));
    });

    test('multiple listeners can subscribe simultaneously (broadcast stream)', () async {
      const testBarcode = 'BATCH-999';
      int count1 = 0;
      int count2 = 0;

      final sub1 = scannerService.onScan.listen((_) => count1++);
      final sub2 = scannerService.onScan.listen((_) => count2++);

      scannerService.simulateScan(testBarcode);

      await Future.delayed(const Duration(milliseconds: 50));
      await sub1.cancel();
      await sub2.cancel();

      expect(count1, equals(1));
      expect(count2, equals(1));
    });
  });
}
