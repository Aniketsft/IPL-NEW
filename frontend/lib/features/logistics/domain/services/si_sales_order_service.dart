import '../../data/local/local_database_helper.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_cart_cubit.dart';
import 'package:sqflite/sqflite.dart';

class SISalesOrderService {
  final LocalDatabaseHelper _dbHelper;
  final Future<Database> Function()? _dbProvider;

  SISalesOrderService({
    LocalDatabaseHelper? dbHelper,
    Future<Database> Function()? dbProvider,
  })  : _dbHelper = dbHelper ?? LocalDatabaseHelper.instance,
        _dbProvider = dbProvider;

  Future<Database> _getDb() async {
    final provider = _dbProvider;
    if (provider != null) return await provider();
    return await _dbHelper.database;
  }

  static const String hardcodedOrderNumber = 'CGDSO250800001';
  static const String hardcodedCustomerCode = 'WIN001';
  static const String hardcodedCustomerName = "WINNER'S BEL AIR";

  Future<void> saveSalesOrder({
    required Map<String, dynamic> customer,
    required List<CartItem> items,
    required double totalAmount,
    required String deliveryDate,
    String? orderNumber,
  }) async {
    final db = await _getDb();
    await db.transaction((txn) async {
      final effectiveOrderNumber = (orderNumber != null && orderNumber.trim().isNotEmpty)
          ? orderNumber.trim()
          : 'SO-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';

      // Insert Order
      final orderId = await txn.insert(
        LocalDatabaseHelper.tableSiSalesOrders,
        {
          'orderNumber': effectiveOrderNumber,
          'customerCode': customer['code'] ?? '',
          'customerName': customer['name'] ?? '',
          'totalAmount': totalAmount,
          'status': 'Open',
          'deliveryDate': deliveryDate.isNotEmpty ? deliveryDate : DateTime.now().toIso8601String(),
          'createdAt': DateTime.now().toIso8601String(),
        },
      );

      // Insert Details
      for (final item in items) {
        await txn.insert(
          LocalDatabaseHelper.tableSiSalesOrderDetails,
          {
            'orderId': orderId,
            'productCode': item.product.sku,
            'productName': item.product.name,
            'quantity': item.quantity,
            'basePrice': item.basePrice,
            'discountAmount': item.discountAmount,
            'vatAmount': item.vatAmount,
            'total': item.total,
            'salesUnit': item.product.salesUnit,
            'lotNumber': item.lotNumber,
            'warehouse': item.warehouse,
            'location': item.location,
            'cce0': item.product.cce0,
            'taxRule': item.taxRule,
          },
        );
      }
    });
  }

  Future<List<Map<String, dynamic>>> getSalesOrders() async {
    final db = await _getDb();
    final List<Map<String, dynamic>> maps = await db.query(
      LocalDatabaseHelper.tableSiSalesOrders,
      orderBy: 'createdAt DESC',
    );
    return maps;
  }

  Future<List<Map<String, dynamic>>> getSalesOrderDetails(int orderId) async {
    final db = await _getDb();
    final List<Map<String, dynamic>> maps = await db.query(
      LocalDatabaseHelper.tableSiSalesOrderDetails,
      where: 'orderId = ?',
      whereArgs: [orderId],
    );
    return maps;
  }

  Future<void> markOrderAsConverted(int orderId) async {
    final db = await _getDb();
    await db.update(
      LocalDatabaseHelper.tableSiSalesOrders,
      {'status': 'Converted'},
      where: 'id = ?',
      whereArgs: [orderId],
    );
  }

  Future<void> updateDeliveryDate(int orderId, String deliveryDate) async {
    final db = await _getDb();
    await db.update(
      LocalDatabaseHelper.tableSiSalesOrders,
      {'deliveryDate': deliveryDate},
      where: 'id = ?',
      whereArgs: [orderId],
    );
  }

  /// Seeds the hardcoded Sage X3 Sales Orders (CGDSO250800001, CGDSO250800002, CGDSO250800006)
  /// and ensures customer/product records exist in master tables for seamless invoice conversion.
  Future<void> ensureHardcodedSalesOrderSeeded() async {
    final db = await _getDb();

    final ordersToSeed = [
      // ORDER 1: WINNER'S BEL AIR (CGDSO250800001)
      {
        'orderNumber': 'CGDSO250800001',
        'customerCode': 'WIN001',
        'customerName': "WINNER'S BEL AIR",
        'totalAmount': 9577.96,
        'status': 'Open',
        'deliveryDate': '2025-08-21T00:00:00.000',
        'createdAt': '2025-08-21T10:30:00.000',
        'lineItems': [
          {
            'productCode': '8101',
            'productName': 'Barilla Macaroni 500g',
            'quantity': 16.0,
            'basePrice': 75.0,
            'discountAmount': 0.0,
            'vatAmount': 180.0,
            'total': 1380.0,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-BAR-8101',
            'warehouse': 'CGD',
            'location': 'A-01',
            'cce0': '',
            'taxRule': 'VATR',
          },
          {
            'productCode': '620410',
            'productName': 'Lorenz Naturels Sal&Pep 100g',
            'quantity': 25.0,
            'basePrice': 77.74,
            'discountAmount': 0.0,
            'vatAmount': 291.56,
            'total': 2235.29,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-LOR-620410',
            'warehouse': 'CGD',
            'location': 'A-02',
            'cce0': '',
            'taxRule': 'VATR',
          },
          {
            'productCode': '624050',
            'productName': 'EVERFRESH UHT MILK 1L LOWFATX6',
            'quantity': 6.0,
            'basePrice': 324.0,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 1944.0,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-EVR-624050',
            'warehouse': 'CGD',
            'location': 'B-01',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
          {
            'productCode': '624004',
            'productName': 'Twin Cows UHT FC 1L',
            'quantity': 15.0,
            'basePrice': 61.25,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 918.75,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-TC-624004',
            'warehouse': 'CGD',
            'location': 'B-02',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
          {
            'productCode': '6251',
            'productName': 'Twin Cows IFCMP 1Kg',
            'quantity': 10.0,
            'basePrice': 309.992,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 3099.92,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-TC-6251',
            'warehouse': 'CGD',
            'location': 'B-03',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
        ],
      },
      // ORDER 2: WINNER'S FLACQ (CGDSO250800002)
      {
        'orderNumber': 'CGDSO250800002',
        'customerCode': 'WIN006',
        'customerName': "WINNER'S FLACQ",
        'totalAmount': 71954.66,
        'status': 'Open',
        'deliveryDate': '2025-08-21T00:00:00.000',
        'createdAt': '2025-08-21T10:30:00.000',
        'lineItems': [
          {
            'productCode': '6243',
            'productName': 'Twin Cows ISMP 750g',
            'quantity': 12.0,
            'basePrice': 242.64,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 2911.68,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-TC-6243',
            'warehouse': 'CGD',
            'location': 'D265',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
          {
            'productCode': '624006',
            'productName': 'Twin Cows UHT SSk 1L',
            'quantity': 24.0,
            'basePrice': 80.55,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 1933.20,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-TC-624006',
            'warehouse': 'CGD',
            'location': 'B01',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
          {
            'productCode': '624005',
            'productName': 'Twin Cows UHT Sk 1L',
            'quantity': 42.0,
            'basePrice': 80.55,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 3383.10,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-TC-624005',
            'warehouse': 'CGD',
            'location': 'B02',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
          {
            'productCode': '624049',
            'productName': 'EFRESH UHT MILK 1L FULLCREAMX6',
            'quantity': 9.0,
            'basePrice': 412.38,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 3711.42,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-EVR-624049',
            'warehouse': 'CGD',
            'location': 'K011',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
          {
            'productCode': '624004',
            'productName': 'Twin Cows UHT FC 1L',
            'quantity': 42.0,
            'basePrice': 80.55,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 3383.10,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-TC-624004',
            'warehouse': 'CGD',
            'location': 'B03',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
          {
            'productCode': '721201',
            'productName': 'Lucky Star Pil TomSauce 425g',
            'quantity': 168.0,
            'basePrice': 77.01,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 12937.68,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-LS-721201',
            'warehouse': 'CGD',
            'location': 'B141',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
          {
            'productCode': '721401',
            'productName': 'Princess Sardines VegOil 125g',
            'quantity': 200.0,
            'basePrice': 31.44,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 6288.00,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-PR-721401',
            'warehouse': 'CGD',
            'location': 'B061',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
          {
            'productCode': '624315',
            'productName': 'Palm Corned Beef 326g',
            'quantity': 48.0,
            'basePrice': 174.02,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 8352.96,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-PLM-624315',
            'warehouse': 'CGD',
            'location': 'INSP',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
          {
            'productCode': '6121',
            'productName': 'LVQR Light 8portions 120g',
            'quantity': 40.0,
            'basePrice': 74.70,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 2988.00,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-LVQR-6121',
            'warehouse': 'CGD',
            'location': 'AC011',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
          {
            'productCode': '6430',
            'productName': 'LVQR 8 Portions 112g',
            'quantity': 36.0,
            'basePrice': 65.70,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 2365.20,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-LVQR-6430',
            'warehouse': 'CGD',
            'location': 'AC011',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
          {
            'productCode': '6433',
            'productName': 'LVQR 32 Portions 448g',
            'quantity': 10.0,
            'basePrice': 193.50,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 1935.00,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-LVQR-6433',
            'warehouse': 'CGD',
            'location': 'AC011',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
          {
            'productCode': '8392',
            'productName': 'Sunbeam EdOil Canola 2L',
            'quantity': 6.0,
            'basePrice': 359.00,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 2154.00,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-SB-8392',
            'warehouse': 'CGD',
            'location': 'F031',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
          {
            'productCode': '651426',
            'productName': 'Bois Cheri 3Pav Van 250g',
            'quantity': 80.0,
            'basePrice': 134.35,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 10748.00,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-BC-651426',
            'warehouse': 'CGD',
            'location': 'G251',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
          {
            'productCode': '8257',
            'productName': 'Rimilda Basmati SpGrade 5Kg',
            'quantity': 8.0,
            'basePrice': 314.79,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 2518.32,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-RIM-8257',
            'warehouse': 'CGD',
            'location': 'D211',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
          {
            'productCode': '6435',
            'productName': 'LVQR Rouge 8 Portions 120g',
            'quantity': 36.0,
            'basePrice': 74.70,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 2689.20,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-LVQR-6435',
            'warehouse': 'CGD',
            'location': 'AC011',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
          {
            'productCode': '6437',
            'productName': 'LVQR XtraCrème 8 Portions 120g',
            'quantity': 36.0,
            'basePrice': 74.70,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 2689.20,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-LVQR-6437',
            'warehouse': 'CGD',
            'location': 'AC011',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
          {
            'productCode': '624035',
            'productName': 'Twin Cows UHT FC 1L*6',
            'quantity': 1.0,
            'basePrice': 483.30,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 483.30,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-TC-624035',
            'warehouse': 'CGD',
            'location': 'K131',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
          {
            'productCode': '624036',
            'productName': 'Twin Cows UHT SSK 1L*6',
            'quantity': 1.0,
            'basePrice': 483.30,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 483.30,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-TC-624036',
            'warehouse': 'CGD',
            'location': 'K091',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
        ],
      },
      // ORDER 3: DREAM PRICE - TRIOLET EXPRESS (CGDSO250800006)
      {
        'orderNumber': 'CGDSO250800006',
        'customerCode': 'SDP028',
        'customerName': 'DREAM PRICE - TRIOLET EXPRESS',
        'totalAmount': 125946.62,
        'status': 'Open',
        'deliveryDate': '2025-08-21T00:00:00.000',
        'createdAt': '2025-08-21T10:30:00.000',
        'lineItems': [
          {
            'productCode': '624251',
            'productName': 'Island Dairy FCMP 1Kg',
            'quantity': 60.0,
            'basePrice': 233.95,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 14037.00,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-ID-624251',
            'warehouse': 'CGD',
            'location': 'E201',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
          {
            'productCode': '6252',
            'productName': 'Twin Cows IFCMP 500g',
            'quantity': 48.0,
            'basePrice': 117.88,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 5658.24,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-TC-6252',
            'warehouse': 'CGD',
            'location': 'E181',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
          {
            'productCode': '6431',
            'productName': 'LVQR 16 Portions 224g',
            'quantity': 32.0,
            'basePrice': 119.70,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 3830.40,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-LVQR-6431',
            'warehouse': 'CGD',
            'location': 'AC011',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
          {
            'productCode': '6432',
            'productName': 'LVQR 24 Portions 336g',
            'quantity': 60.0,
            'basePrice': 157.50,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 9450.00,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-LVQR-6432',
            'warehouse': 'CGD',
            'location': 'AC011',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
          {
            'productCode': '6430',
            'productName': 'LVQR 8 Portions 112g',
            'quantity': 36.0,
            'basePrice': 65.70,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 2365.20,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-LVQR-6430',
            'warehouse': 'CGD',
            'location': 'AC011',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
          {
            'productCode': '6121',
            'productName': 'LVQR Light 8portions 120g',
            'quantity': 36.0,
            'basePrice': 74.70,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 2689.20,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-LVQR-6121',
            'warehouse': 'CGD',
            'location': 'AC011',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
          {
            'productCode': '721205',
            'productName': 'Lucky Star Pil SwChilSauce 425g',
            'quantity': 30.0,
            'basePrice': 77.01,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 2310.30,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-LS-721205',
            'warehouse': 'CGD',
            'location': 'B111',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
          {
            'productCode': '720601',
            'productName': 'L STAR PILCHARDS TOMATO - 155G',
            'quantity': 240.0,
            'basePrice': 34.39,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 8253.60,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-LS-720601',
            'warehouse': 'CGD',
            'location': 'B111',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
          {
            'productCode': '720503',
            'productName': 'L STAR PILCHARDS TOMATO - 215G',
            'quantity': 240.0,
            'basePrice': 43.83,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 10519.20,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-LS-720503',
            'warehouse': 'CGD',
            'location': 'B121',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
          {
            'productCode': '721401',
            'productName': 'Princess Sardines VegOil 125g',
            'quantity': 1000.0,
            'basePrice': 31.44,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 31440.00,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-PR-721401',
            'warehouse': 'CGD',
            'location': 'B061',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
          {
            'productCode': '624321',
            'productName': 'Palm Corned Beef 210g',
            'quantity': 24.0,
            'basePrice': 121.77,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 2922.48,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-PLM-624321',
            'warehouse': 'CGD',
            'location': 'INSP',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
          {
            'productCode': '624315',
            'productName': 'Palm Corned Beef 326g',
            'quantity': 24.0,
            'basePrice': 174.02,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 4176.48,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-PLM-624315',
            'warehouse': 'CGD',
            'location': 'INSP',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
          {
            'productCode': '842162',
            'productName': 'Pure Joy 100% Apple 1L',
            'quantity': 6.0,
            'basePrice': 93.10,
            'discountAmount': 0.0,
            'vatAmount': 83.79,
            'total': 642.39,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-PJ-842162',
            'warehouse': 'CGD',
            'location': 'INSP',
            'cce0': '',
            'taxRule': 'VATR',
          },
          {
            'productCode': '842163',
            'productName': 'Pure Joy 100% Guava 1L',
            'quantity': 6.0,
            'basePrice': 93.10,
            'discountAmount': 0.0,
            'vatAmount': 83.79,
            'total': 642.39,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-PJ-842163',
            'warehouse': 'CGD',
            'location': 'INSP',
            'cce0': '',
            'taxRule': 'VATR',
          },
          {
            'productCode': '842164',
            'productName': 'Pure Joy 100% Litchi 1L',
            'quantity': 6.0,
            'basePrice': 93.10,
            'discountAmount': 0.0,
            'vatAmount': 83.79,
            'total': 642.39,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-PJ-842164',
            'warehouse': 'CGD',
            'location': 'INSP',
            'cce0': '',
            'taxRule': 'VATR',
          },
          {
            'productCode': '6360',
            'productName': 'Emborg Cooking Cream 1L 20%',
            'quantity': 6.0,
            'basePrice': 236.55,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 1419.30,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-EMB-6360',
            'warehouse': 'CGD',
            'location': 'AC011',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
          {
            'productCode': '6361',
            'productName': 'Emborg Cooking Cream 200ml',
            'quantity': 27.0,
            'basePrice': 84.15,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 2272.05,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-EMB-6361',
            'warehouse': 'CGD',
            'location': 'CH011',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
          {
            'productCode': '651426',
            'productName': 'Bois Cheri 3Pav Van 250g',
            'quantity': 80.0,
            'basePrice': 134.35,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 10748.00,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-BC-651426',
            'warehouse': 'CGD',
            'location': 'G251',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
          {
            'productCode': '651431',
            'productName': 'Bois Cheri 3Pav Van 125g',
            'quantity': 160.0,
            'basePrice': 74.55,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': 11928.00,
            'salesUnit': 'EA',
            'lotNumber': 'LOT-BC-651431',
            'warehouse': 'CGD',
            'location': 'G271',
            'cce0': '',
            'taxRule': 'EXEMPT',
          },
        ],
      },
    ];

    for (final orderData in ordersToSeed) {
      final orderNumber = orderData['orderNumber'] as String;
      final customerCode = orderData['customerCode'] as String;
      final customerName = orderData['customerName'] as String;
      final totalAmount = orderData['totalAmount'] as double;
      final lineItems = orderData['lineItems'] as List<Map<String, dynamic>>;

      // Check if already seeded
      final existing = await db.query(
        LocalDatabaseHelper.tableSiSalesOrders,
        where: 'orderNumber = ?',
        whereArgs: [orderNumber],
        limit: 1,
      );

      if (existing.isEmpty) {
        await db.transaction((txn) async {
          // 1. Insert Master Order Header
          final orderId = await txn.insert(
            LocalDatabaseHelper.tableSiSalesOrders,
            {
              'orderNumber': orderNumber,
              'customerCode': customerCode,
              'customerName': customerName,
              'totalAmount': totalAmount,
              'status': 'Open',
              'deliveryDate': orderData['deliveryDate'],
              'createdAt': orderData['createdAt'],
            },
          );

          // 2. Insert Line Items
          for (final item in lineItems) {
            final detail = Map<String, dynamic>.from(item);
            detail['orderId'] = orderId;
            await txn.insert(
              LocalDatabaseHelper.tableSiSalesOrderDetails,
              detail,
            );
          }

          // 3. Ensure Customer Exists in Master
          try {
            final custExists = await txn.query(
              LocalDatabaseHelper.tableSalesInvoiceCustomers,
              where: 'code = ?',
              whereArgs: [customerCode],
              limit: 1,
            );
            if (custExists.isEmpty) {
              await txn.insert(
                LocalDatabaseHelper.tableSalesInvoiceCustomers,
                {
                  'code': customerCode,
                  'name': customerName,
                  'status': '1',
                  'taxRule': 'VATR',
                  'paymentTerm': '30 Days',
                  'outstandingBalance': 0.0,
                },
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
          } catch (_) {}

          // 4. Ensure Products & Stock Records Exist in Master
          try {
            for (final item in lineItems) {
              final sku = item['productCode'] as String;
              final name = item['productName'] as String;
              final unit = item['salesUnit'] as String;

              await txn.insert(
                LocalDatabaseHelper.tableSalesInvoiceProducts,
                {
                  LocalDatabaseHelper.colSiProdSku: sku,
                  LocalDatabaseHelper.colSiProdName: name,
                  LocalDatabaseHelper.colSiProdStockQty: 500.0,
                  LocalDatabaseHelper.colSiProdWarehouse: 'CGD',
                  LocalDatabaseHelper.colSiProdSalesUnit: unit,
                  LocalDatabaseHelper.colSiProdIsSynced: 1,
                  'cce0': '',
                },
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );

              await txn.insert(
                LocalDatabaseHelper.tableSalesInvoiceItemStockDetails,
                {
                  'itemCode': sku,
                  'itemName': name,
                  'lotNumber': item['lotNumber'],
                  'warehouse': 'CGD',
                  'location': item['location'],
                  'totalQty': 500.0,
                  'salesUnit': unit,
                  'isSynced': 1,
                },
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
            }
          } catch (_) {}
        });
      }
    }
  }
}
