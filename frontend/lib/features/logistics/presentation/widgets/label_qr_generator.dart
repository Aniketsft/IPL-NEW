import 'package:intl/intl.dart';
import '../../domain/entities/sales_order_detail.dart';

class LabelQrGenerator {
  /// CASE 1: INDIVIDUAL ITEM LABEL
  /// Format: [SO]|[CUSTOMER]|[ITEM]|[DESCRIPTION]|[WEIGHT]|[UNIT]|[PRINT_TIME]|[DELIVERY_DATE]
  static String generate(SalesOrderDetail item) {
    final printTime = DateFormat('yyyyMMddHHmm').format(DateTime.now());
    final deliveryDate = item.deliveryDate != null 
        ? DateFormat('yyyy-MM-dd').format(item.deliveryDate!) 
        : 'N/A';
        
    final customer = item.customerName ?? 'N/A';
    final weight = item.manufacturedQuantity.toStringAsFixed(3);
    
    return [
      item.soNumber,
      customer,
      item.itemCode,
      item.description,
      weight,
      item.unit,
      printTime,
      deliveryDate,
    ].join('|');
  }

  /// Parses aggregated strings back into parts
  static Map<String, String> parse(String data) {
    if (data.startsWith('CRATE|')) {
      final parts = data.split('|');
      return {
        'type': 'CRATE',
        'soNumber': parts.length > 1 ? parts[1] : 'N/A',
        'customer': parts.length > 2 ? parts[2] : 'N/A',
        'delivery': parts.length > 3 ? parts[3] : 'N/A',
        'count': parts.length > 4 ? parts[4] : '0',
        'manifest': parts.length > 5 ? parts[5] : '', 
        'unit': parts.length > 6 ? parts[6] : 'KG',
        'timestamp': parts.length > 7 ? parts[7] : '',
      };
    }
    
    if (data.startsWith('PALETTE|')) {
      final parts = data.split('|');
      return {
        'type': 'PALETTE',
        'timestamp': parts.length > 1 ? parts[1] : '',
        'manifest': parts.length > 2 ? parts[2] : '', 
      };
    }
    
    final parts = data.split('|');
    if (parts.length < 6) return {};
    
    return {
      'type': 'ITEM',
      'soNumber': parts[0],
      'customer': parts[1],
      'itemCode': parts[2],
      'description': parts[3],
      'weight': parts[4],
      'unit': parts[5],
      'printTime': parts.length > 6 ? parts[6] : '',
      'deliveryDate': parts.length > 7 ? parts[7] : 'N/A',
    };
  }

  /// CASE 2: CRATE AGGREGATION
  /// Format: CRATE|[SO]|[CUST]|[DELIVERY]|[COUNT]|[P1:W1,P2:W2]|[UNIT]|[TIMESTAMP]
  static String generateCrate({
    required String soNumber,
    required String customer,
    required String delivery,
    required List<Map<String, String>> items, 
    required String unit,
  }) {
    final timestamp = DateFormat('yyyyMMddHHmm').format(DateTime.now());
    final manifestStr = items.map((i) => '${(i['itemCode'] ?? 'N/A').replaceAll(':','')}:${i['weight'] ?? '0'}').join(',');

    return [
      'CRATE', 
      soNumber, 
      customer, 
      delivery, 
      items.length.toString(), 
      manifestStr, 
      unit, 
      timestamp
    ].join('|');
  }

  /// CASE 3: PALETTE AGGREGATION (Granular Traceability)
  /// Format: PALETTE|[TIMESTAMP]|[SO:CUST:DELIV:P1:W1,P2:W2;SO:CUST:DELIV:P3:W3]
  static String generatePalette(Map<String, Map<String, dynamic>> manifest) {
    final timestamp = DateFormat('yyyyMMddHHmm').format(DateTime.now());
    final List<String> soParts = [];
    
    manifest.forEach((so, data) {
      final String cust = data['customer'] ?? 'N/A';
      final String deliv = data['delivery'] ?? 'N/A';
      final List<Map<String, String>> items = List<Map<String, String>>.from(data['items'] ?? []);
      
      // Serialize items as P1:W1,P2:W2
      final itemStr = items.map((i) => '${(i['itemCode'] ?? 'N/A').replaceAll(':','')}:${i['weight'] ?? '0'}').join(',');
      
      soParts.add('$so:$cust:$deliv:$itemStr');
    });
    
    return ['PALETTE', timestamp, soParts.join(';')].join('|');
  }
}
