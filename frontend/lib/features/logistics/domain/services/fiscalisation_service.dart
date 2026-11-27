import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:enterprise_auth_mobile/core/network_service.dart';
import 'package:enterprise_auth_mobile/core/secure_storage_service.dart';
import 'package:enterprise_auth_mobile/core/services/device_info_service.dart';

class FiscalErrorDetail {
  final String? code;
  final String description;

  const FiscalErrorDetail({this.code, required this.description});

  @override
  String toString() => (code != null && code!.isNotEmpty) ? '[$code] $description' : description;
}

class FiscalisationException implements Exception {
  final String message;
  final String? hepStatus;
  final List<FiscalErrorDetail> errors;
  final bool isOfflineOrNetwork;

  FiscalisationException(
    this.message, {
    this.hepStatus,
    this.errors = const [],
    this.isOfflineOrNetwork = false,
  });

  @override
  String toString() => message;
}

class FiscalisationResult {
  final String documentNo;
  final bool isFiscalised;
  final String? hepId;
  final String? hepStatus;
  final String? statusMessage;
  final String? irn;
  final String qrCodeBase64;
  final String? mraEnvironment;
  final String? fiscalisedAt;

  const FiscalisationResult({
    required this.documentNo,
    required this.isFiscalised,
    this.hepId,
    this.hepStatus,
    this.statusMessage,
    this.irn,
    required this.qrCodeBase64,
    this.mraEnvironment,
    this.fiscalisedAt,
  });

  factory FiscalisationResult.fromJson(Map<String, dynamic> json) {
    return FiscalisationResult(
      documentNo: json['documentNo']?.toString() ?? '',
      isFiscalised: json['isFiscalised'] == true,
      hepId: json['hepId']?.toString(),
      hepStatus: json['hepStatus']?.toString(),
      statusMessage: json['statusMessage']?.toString(),
      irn: json['irn']?.toString(),
      qrCodeBase64: json['qrBase64']?.toString() ?? '',
      mraEnvironment: json['mraEnvironment']?.toString(),
      fiscalisedAt: json['fiscalisedAt']?.toString(),
    );
  }
}

class FiscalisationService {
  final NetworkService _networkService;

  FiscalisationService({NetworkService? networkService})
      : _networkService = networkService ??
            NetworkService(storageService: SecureStorageService());

  Future<void> _ensureOnlineSession() async {
    final token = await SecureStorageService().getToken();
    if (token == null || token.isEmpty || token.startsWith('OFFLINE_SESSION_')) {
      throw FiscalisationException(
        'Device is offline. An active online connection is required to fiscalise and complete this transaction.',
        hepStatus: 'offline',
        isOfflineOrNetwork: true,
        errors: const [
          FiscalErrorDetail(
            code: 'OFFLINE',
            description: 'Cannot fiscalise while offline. Connect to the network and sign in online.',
          ),
        ],
      );
    }
  }

  Future<FiscalisationResult> fiscaliseDocument({
    required String documentNo,
    required String documentCategory, // INVOICE, CREDIT_NOTE, RETURN
    String? invoiceType,
    required String salesSite,
    required String customerCode,
    required String customerName,
    String currency = 'MUR',
    String? originalInvoiceId,
    String? reason,
    String? invoiceDate,
    String? deviceId,
    String? settlementType,
    double? totalPaid,
    required List<Map<String, dynamic>> lines,
    List<Map<String, dynamic>> payments = const [],
  }) async {
    await _ensureOnlineSession();

    final resolvedDeviceId = (deviceId != null && deviceId.trim().isNotEmpty)
        ? deviceId.trim()
        : DeviceInfoService.instance.deviceId;

    final payload = {
      'documentNo': documentNo,
      'documentCategory': documentCategory,
      if (invoiceType != null && invoiceType.isNotEmpty) 'invoiceType': invoiceType,
      'salesSite': salesSite,
      'customerCode': customerCode,
      'customerName': customerName,
      'currency': currency,
      'rateMultiplier': 1.0,
      if (originalInvoiceId != null && originalInvoiceId.isNotEmpty) 'originalInvoiceId': originalInvoiceId,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
      'invoiceDate': invoiceDate ?? DateTime.now().toIso8601String(),
      if (resolvedDeviceId.isNotEmpty) 'deviceId': resolvedDeviceId,
      if (settlementType != null && settlementType.isNotEmpty) 'settlementType': settlementType,
      if (totalPaid != null) 'totalPaid': totalPaid,
      'lines': lines,
      'payments': payments,
    };

    debugPrint(
      '[FISCAL-MOBILE] >>> POST Fiscalisation/fiscalise ($documentNo):\n${const JsonEncoder.withIndent('  ').convert(payload)}',
    );

    try {
      final response = await _networkService.dio.post(
        'Fiscalisation/fiscalise',
        data: payload,
        options: Options(
          sendTimeout: const Duration(seconds: 35),
          receiveTimeout: const Duration(seconds: 35),
        ),
      );

      debugPrint(
        '[FISCAL-MOBILE] <<< HTTP ${response.statusCode} ($documentNo): ${jsonEncode(response.data)}',
      );

      final data = response.data;
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        final result = FiscalisationResult.fromJson(map);
        if (map['success'] == true && result.isFiscalised && result.qrCodeBase64.isNotEmpty) {
          return result;
        }
        throw _buildExceptionFromMap(map, fallbackMsg: 'Fiscalisation did not return valid QR credentials.');
      }

      throw FiscalisationException('Unexpected response from fiscalisation server.');
    } on DioException catch (e) {
      debugPrint(
        '[FISCAL-MOBILE] <<< ERROR HTTP ${e.response?.statusCode} ($documentNo): ${e.response?.data ?? e.message}',
      );
      final isNet = e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          (e.error != null && e.error.toString().toLowerCase().contains('offline'));

      if (e.response?.data is Map) {
        final map = Map<String, dynamic>.from(e.response!.data as Map);
        throw _buildExceptionFromMap(
          map,
          fallbackMsg: e.message ?? 'Fiscalisation rejected (HTTP ${e.response?.statusCode}).',
          isNetwork: isNet,
        );
      }

      throw FiscalisationException(
        isNet
            ? 'Cannot reach fiscalisation server. Verify network connectivity and retry.'
            : (e.message ?? 'Fiscalisation request failed.'),
        hepStatus: isNet ? 'networkError' : 'httpError',
        isOfflineOrNetwork: isNet,
        errors: [
          FiscalErrorDetail(
            code: isNet ? 'NETWORK' : 'HTTP_${e.response?.statusCode ?? "ERR"}',
            description: e.message ?? 'Connection error',
          ),
        ],
      );
    }
  }

  Future<FiscalisationResult?> fetchFiscalCredentials(String documentNo) async {
    if (documentNo.trim().isEmpty) return null;
    try {
      final token = await SecureStorageService().getToken();
      if (token == null || token.isEmpty || token.startsWith('OFFLINE_SESSION_')) {
        return null;
      }
      final resp = await _networkService.dio.get('Fiscalisation/${Uri.encodeComponent(documentNo.trim())}');
      if (resp.statusCode == 200 && resp.data is Map) {
        final result = FiscalisationResult.fromJson(Map<String, dynamic>.from(resp.data as Map));
        if (result.isFiscalised && result.qrCodeBase64.isNotEmpty) {
          return result;
        }
      }
    } catch (_) {}
    return null;
  }

  FiscalisationException _buildExceptionFromMap(
    Map<String, dynamic> map, {
    required String fallbackMsg,
    bool isNetwork = false,
  }) {
    final errors = <FiscalErrorDetail>[];
    if (map['errors'] is List) {
      for (final item in (map['errors'] as List)) {
        if (item is Map) {
          final code = item['code']?.toString();
          final desc = item['description']?.toString() ?? '';
          if (desc.isNotEmpty || (code != null && code.isNotEmpty)) {
            errors.add(FiscalErrorDetail(code: code, description: desc.isNotEmpty ? desc : (code ?? 'Error')));
          }
        }
      }
    }
    final statusMsg = map['statusMessage']?.toString();
    final msg = (statusMsg != null && statusMsg.isNotEmpty)
        ? statusMsg
        : (errors.isNotEmpty ? errors.map((e) => e.toString()).join('\n') : fallbackMsg);
    return FiscalisationException(
      msg,
      hepStatus: map['hepStatus']?.toString(),
      errors: errors,
      isOfflineOrNetwork: isNetwork,
    );
  }
}
