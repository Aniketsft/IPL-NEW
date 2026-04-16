import 'package:intl/intl.dart';
import '../../domain/entities/sales_order_detail.dart';

class LabelQrGenerator {
  /// Generates a structured string for the label QR code.
  /// Format: [SO]|[CUSTOMER]|[ITEM]|[DESCRIPTION]|[WEIGHT]|[UNIT]|[TIMESTAMP]
  static String generate(SalesOrderDetail item) {
    final timestamp = DateFormat('yyyyMMddHHmm').format(DateTime.now());
    final customer = item.customerName ?? 'N/A';
    final weight = item.manufacturedQuantity.toStringAsFixed(3);
    
    // Using pipe delimiter for clean parsing
    return [
      item.soNumber,
      customer,
      item.itemCode,
      item.description,
      weight,
      item.unit,
      timestamp,
    ].join('|');
  }

  /// Parses the generated string back into parts (useful for verification/receiving)
  static Map<String, String> parse(String data) {
    final parts = data.split('|');
    if (parts.length < 6) return {};
    
    return {
      'soNumber': parts[0],
      'customer': parts[1],
      'itemCode': parts[2],
      'description': parts[3],
      'weight': parts[4],
      'unit': parts[5],
      'timestamp': parts.length > 6 ? parts[6] : '',
    };
  }
}
