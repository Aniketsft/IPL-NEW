import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/sales_order.dart';
import '../../domain/entities/sales_order_detail.dart';
import '../../domain/repositories/ilogistics_repository.dart';
import '../models/sales_order_dto.dart';
import '../models/sales_order_detail_dto.dart';
import '../models/location_lookup_dto.dart';
import '../../domain/entities/location_lookup.dart';
import 'package:enterprise_auth_mobile/core/config/api_config.dart';

class DeliveryRepository implements ILogisticsRepository {
  final Dio _dio;

  static String get _baseUrl => ApiConfig.baseUrl;

  DeliveryRepository()
    : _dio = Dio(
        BaseOptions(
          baseUrl: _baseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 60),
        ),
      ) {
    if (kDebugMode && !kIsWeb) {
      (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        client.badCertificateCallback =
            (X509Certificate cert, String host, int port) => true;
        return client;
      };
    }
  }

  @override
  Future<List<SalesOrderDetail>> getSalesOrderDetails(String soNumber) async {
    try {
      final response = await _dio.get(
        'Logistics/sales-order-details/$soNumber',
      );
      final data = response.data as List;
      return data.map((json) {
        final dto = SalesOrderDetailDto.fromJson(json);
        return _mapDetailDtoToEntity(dto);
      }).toList();
    } catch (e) {
      throw 'Failed to fetch sales order details: $e';
    }
  }

  @override
  Future<List<SalesOrderDetail>> getProductionTracking() async {
    try {
      final response = await _dio.get('Logistics/production-tracking');
      final data = response.data as List;
      return data.map((json) {
        final dto = SalesOrderDetailDto.fromJson(json);
        return _mapDetailDtoToEntity(dto);
      }).toList();
    } catch (e) {
      throw 'Failed to fetch production tracking: $e';
    }
  }

  @override
  Future<List<SalesOrder>> fetchSalesOrders({DateTime? date}) async {
    try {
      final queryParams = <String, dynamic>{};
      if (date != null) {
        queryParams['deliveryDate'] = DateFormat('yyyy-MM-dd').format(date);
      }

      final response = await _dio.get(
        'Logistics/consolidated-orders',
        queryParameters: queryParams,
      );
      final data = response.data as List;
      return data.map((json) {
        final dto = SalesOrderDto.fromJson(json);
        return SalesOrder(
          id: dto.soNumber,
          orderNumber: dto.soNumber,
          customerCode: dto.customerCode,
          customerName: dto.customerName,
          deliveryDate: dto.deliveryDate,
          date: DateTime.tryParse(dto.deliveryDate) ?? DateTime.now(),
          purchaseOrderNumber: dto.poNumber,
          salesManCode1: dto.salesman ?? '',
          salesManCode2: '',
          deliveryNo: dto.deliveryNo,
          deliveryFrom: dto.deliveryFrom,
          deliveryLorry: dto.deliveryLorry,
          deliverySalesman: dto.deliverySalesman,
          soLorry: dto.soLorry,
          originalSoLorry: dto.oriSoLorry,
        );
      }).toList();
    } catch (e) {
      throw 'Failed to fetch sales orders: $e';
    }
  }

  /// Fetches order-header level data for ViewSalesOrderScreen.
  /// Calls GET /api/Logistics/sales-order-headers with optional filters.
  Future<List<SalesOrder>> fetchSalesOrderHeaders({
    String status = 'all',
    DateTime? date,
    String? customerCode,
    String? rep0,
    String? rep1,
  }) async {
    try {
      final queryParams = <String, dynamic>{};

      if (status == 'open') {
        queryParams['status'] = 1; // 1 = Open
      } else if (status == 'closed') {
        queryParams['status'] = 2; // 2 = Closed
      }

      if (date != null) {
        queryParams['date'] = date.toIso8601String().split('T').first;
      }

      if (customerCode != null && customerCode.isNotEmpty) {
        queryParams['customerCode'] = customerCode;
      }

      if (rep0 != null && rep0.isNotEmpty) {
        queryParams['rep0'] = rep0;
      }

      if (rep1 != null && rep1.isNotEmpty) {
        queryParams['rep1'] = rep1;
      }

      final response = await _dio.get(
        'Logistics/sales-order-headers',
        queryParameters: queryParams,
      );
      final data = response.data as List;
      return data.map((json) => _mapHeaderJsonToEntity(json)).toList();
    } catch (e) {
      throw 'Failed to fetch sales order headers: $e';
    }
  }

  @override
  Future<void> closeOrder(String soNumber, String closedBy) async {
    try {
      await _dio.post(
        'Logistics/close-order/$soNumber',
        queryParameters: {'closedBy': closedBy},
      );
    } catch (e) {
      throw 'Failed to close order: $e';
    }
  }

  Future<List<Map<String, String>>> getCustomers() async {
    try {
      final response = await _dio.get('Logistics/customers');
      final data = response.data as List;
      return data
          .map(
            (json) => {
              'code': (json['code'] ?? '').toString(),
              'name': (json['name'] ?? '').toString(),
            },
          )
          .toList();
    } catch (e) {
      throw 'Failed to fetch customers: $e';
    }
  }

  Future<List<Map<String, String>>> getSalesReps() async {
    try {
      final response = await _dio.get('Logistics/sales-reps');
      final data = response.data as List;
      return data
          .map(
            (json) => {
              'code': (json['code'] ?? '').toString(),
              'name': (json['name'] ?? '').toString(),
            },
          )
          .toList();
    } catch (e) {
      throw 'Failed to fetch sales representatives: $e';
    }
  }

  Future<List<SalesOrderDetail>> fetchSalesOrderDetails(String soNumber) async {
    try {
      final response = await _dio.get(
        'Logistics/sales-order-details/$soNumber',
      );
      final data = response.data as List;
      return data.map((json) => _mapDetailJsonToEntity(json)).toList();
    } catch (e) {
      throw 'Failed to fetch order details: $e';
    }
  }

  Future<SalesOrderDetail?> fetchProductionTrackingInfo(
    String soNumber,
    String productCode,
  ) async {
    try {
      final response = await _dio.get(
        'Logistics/production-tracking-info',
        queryParameters: {'soNumber': soNumber, 'productCode': productCode},
      );
      if (response.data == null) return null;
      return _mapDetailJsonToEntity(response.data);
    } catch (e) {
      throw 'Failed to fetch tracking info: $e';
    }
  }

  Future<String> saveCutBulkEntry(Map<String, dynamic> entry) async {
    try {
      final response = await _dio.post('Logistics/cut-bulk', data: entry);
      return response.data.toString();
    } catch (e) {
      throw 'Failed to save Cut/Bulk entry: $e';
    }
  }

  SalesOrder _mapHeaderJsonToEntity(Map<String, dynamic> json) {
    return SalesOrder(
      id: json['sohNum'] ?? '',
      orderNumber: json['sohNum'] ?? '',
      customerCode: json['customerCode'] ?? '',
      customerName: json['customerName'] ?? '',
      deliveryDate: json['deliveryDate'] ?? '',
      date: json['deliveryDate'] != null
          ? DateTime.tryParse(json['deliveryDate']) ?? DateTime.now()
          : DateTime.now(),
      soDate: json['orderDate'] != null
          ? DateTime.tryParse(json['orderDate'])
          : null,
      purchaseOrderNumber: json['poNo'],
      salesManCode1: json['rep0'] ?? '',
      salesManCode2: json['rep1'] ?? '',
      site: json['site'],
      isClosed: json['status'] == 2,
      isEditable: true,
    );
  }

  SalesOrderDetail _mapDetailJsonToEntity(Map<String, dynamic> json) {
    return SalesOrderDetail(
      soNumber: json['soNumber'] ?? '',
      poNumber: json['poNumber'],
      customerCode: json['customerCode'],
      customerName: json['customerName'],
      deliveryDate: json['deliveryDate'] != null
          ? DateTime.tryParse(json['deliveryDate'])
          : null,
      salesMan1: json['salesMan1'],
      salesMan2: json['salesMan2'],
      site: json['site'],
      location: json['location'],
      lot: json['lot'],
      warehouse: json['warehouse'],
      warehouseName: json['warehouseName'],
      locationType: json['locationType'],
      locationTypeName: json['locationTypeName'],
      itemCode: json['itemCode'] ?? '',
      description: json['description'] ?? '',
      barcodeType: json['barcodeType'] ?? 'Variable Weight',
      quantity: (json['quantity'] ?? 0.0).toDouble(),
      remaining: (json['remaining'] ?? 0.0).toDouble(),
      manufacturedQuantity: (json['manufactured'] ?? 0.0).toDouble(),
    );
  }

  @override
  Future<void> updateSalesOrder(SalesOrder order) async {
    // Note: Update logic for Innodis might be different
    await Future.delayed(const Duration(milliseconds: 500));
  }

  @override
  Future<void> syncScans(List<Map<String, dynamic>> scans) async {
    try {
      final payload = scans
          .map(
            (s) => {
              'soNumber': s['soNumber'],
              'itemCode': s['itemCode'],
              'quantity': s['quantity'],
              'scanTimestamp': s['timestamp'],
            },
          )
          .toList();

      await _dio.post('Logistics/sync-scans', data: payload);
    } catch (e) {
      throw 'Failed to sync scans: $e';
    }
  }

  @override
  Future<void> saveProductionScan(Map<String, dynamic> scan) async {
    try {
      await _dio.post('Logistics/production-scan', data: scan);
    } catch (e) {
      throw 'Failed to save production scan: $e';
    }
  }

  @override
  Future<List<LocationLookup>> getLocationLookups(String site) async {
    try {
      final response = await _dio.get(
        'Logistics/locations',
        queryParameters: {'site': site},
      );
      final data = response.data as List;
      return data
          .map((json) => LocationLookupDto.fromJson(json).toEntity())
          .toList();
    } catch (e) {
      throw 'Failed to fetch location lookups: $e';
    }
  }

  SalesOrderDetail _mapDetailDtoToEntity(SalesOrderDetailDto dto) {
    return SalesOrderDetail(
      soNumber: dto.soNumber,
      poNumber: dto.poNumber,
      customerCode: dto.customerCode,
      customerName: dto.customerName,
      deliveryDate: dto.deliveryDate != null
          ? DateTime.tryParse(dto.deliveryDate!)
          : null,
      salesMan1: dto.salesMan1,
      salesMan2: dto.salesMan2,
      site: dto.site,
      location: dto.location,
      lot: dto.lot,
      warehouse: dto.warehouse,
      warehouseName: dto.warehouseName,
      locationType: dto.locationType,
      locationTypeName: dto.locationTypeName,
      itemCode: dto.itemCode ?? '',
      description: dto.description ?? '',
      barcodeType: dto.barcodeType ?? 'Variable Weight',
      quantity: dto.quantity,
      remaining: dto.remaining,
      manufacturedQuantity: dto.manufactured,
    );
  }
}
