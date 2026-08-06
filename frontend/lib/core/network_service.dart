import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'secure_storage_service.dart';
import 'config/api_config.dart';
import 'services/device_info_service.dart';

class NetworkService {
  late final Dio dio;
  final SecureStorageService _storageService;
  VoidCallback? onUnauthorized;

  NetworkService({
    required SecureStorageService storageService,
    this.onUnauthorized,
  }) : _storageService = storageService {
    dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );

    // 1. SSL Bypass for local development
    if (kDebugMode && !kIsWeb) {
      (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        client.badCertificateCallback =
            (X509Certificate cert, String host, int port) => true;
        return client;
      };
    }

    // 2. Auth Interceptor
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storageService.getToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          
          final schema = await _storageService.getSchema() ?? 'INLDRYRUN';
          options.headers['X-X3-Schema'] = schema;
          
          options.headers['X-Device-Id'] = DeviceInfoService.instance.deviceInfo;
          
          return handler.next(options);
        },
        onError: (DioException e, handler) async {
          if (e.response?.statusCode == 401) {
            debugPrint('Global 401 Intercepted: Clearing session.');
            await _storageService.deleteAll();
            onUnauthorized?.call();
          }
          return handler.next(e);
        },
      ),
    );

    // Optional: Add logging in debug mode
    if (kDebugMode) {
      dio.interceptors.add(
        LogInterceptor(
          requestHeader: true,
          requestBody: true,
          responseHeader: false,
          responseBody: true,
        ),
      );
    }
  }
}
