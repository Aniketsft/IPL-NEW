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

class DeliveryRepository implements ILogisticsRepository {
  final Dio _dio;

  static String get _baseUrl {
    if (!kIsWeb && Platform.isAndroid) {
      return 'http://10.0.2.2:5150/api/';
    }
    return 'https://localhost:7176/api/';
  }

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
  }) async {
    try {
      final queryParams = <String, dynamic>{};
      if (status != 'all') queryParams['status'] = status;
      if (date != null) {
        queryParams['deliveryDate'] = DateFormat('yyyy-MM-dd').format(date);
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

  SalesOrder _mapHeaderJsonToEntity(Map<String, dynamic> json) {
    return SalesOrder(
      id: json['soNumber'] ?? '',
      orderNumber: json['soNumber'] ?? '',
      customerCode: json['customerCode'] ?? '',
      customerName: json['customerName'] ?? '',
      deliveryDate: json['deliveryDate'] ?? '',
      date: json['deliveryDate'] != null
          ? DateTime.tryParse(json['deliveryDate']) ?? DateTime.now()
          : DateTime.now(),
      soDate: json['soDate'] != null ? DateTime.tryParse(json['soDate']) : null,
      purchaseOrderNumber: json['poNumber'],
      salesManCode1: json['salesManCode1'] ?? '',
      salesManCode2: json['salesManCode2'] ?? '',
      isClosed: json['isClosed'] ?? false,
      isEditable: json['isEditable'] ?? true,
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
              'productCode': s['productCode'],
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

  SalesOrderDetail _mapDetailDtoToEntity(SalesOrderDetailDto dto) {
    return SalesOrderDetail(
      soNumber: dto.soNumber,
      poNumber: dto.poNumber,
      customerCode: dto.customerCode,
      customerName: dto.customerName,
      deliveryDate: dto.deliveryDate != null
          ? DateTime.parse(dto.deliveryDate!)
          : null,
      productCode: dto.productCode,
      productDescription: dto.productDescription,
      barcodeType: dto.barcodeType,
      orderedQuantity: dto.orderedQuantity,
      remainingQuantity: dto.remainingQuantity,
      manufactured: dto.manufactured,
      salesMan1: dto.salesMan1,
      salesMan2: dto.salesMan2,
    );
  }
}
