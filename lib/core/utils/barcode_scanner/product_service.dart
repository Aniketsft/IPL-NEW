import '../../network_service.dart';
import 'barcode_mapping_model.dart';
import 'db_helper.dart';

class ProductService {
  final NetworkService _networkService;
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  ProductService(this._networkService);

  Future<void> syncBarcodeMappings(String siteCode) async {
    try {
      final response = await _networkService.dio.get(
        '/api/logistics/barcode-mappings',
        queryParameters: {'siteCode': siteCode},
      );

      if (response.statusCode == 200 && response.data != null) {
        final List<dynamic> data = response.data;
        final mappings = data.map((json) => BarcodeMapping.fromMap(json)).toList();

        // Clear existing mappings
        await _dbHelper.clearMappings();

        // Insert new mappings
        await _dbHelper.insertMappings(mappings);
      } else {
        throw Exception('Failed to fetch barcode mappings: ${response.statusCode}');
      }
    } catch (e) {
      print('Error syncing barcode mappings: $e');
      throw e;
    }
  }
}
