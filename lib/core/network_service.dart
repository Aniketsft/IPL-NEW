import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'secure_storage_service.dart';
import 'config/api_config.dart';

class NetworkService {
  late final Dio dio;
  final SecureStorageService _storageService;

  NetworkService({required SecureStorageService storageService})
    : _storageService = storageService {
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
          return handler.next(options);
        },
        onError: (DioException e, handler) async {
          if (e.response?.statusCode == 401) {
            debugPrint('Global 401 Intercepted: Clearing session.');
            await _storageService.deleteAll();
            // Note: In a real app, you might trigger a navigation event here
            // via a GlobalKey or a dedicated AuthEvent in a top-level BLoC.
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
