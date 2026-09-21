import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'secure_storage_service.dart';
import 'config/api_config.dart';
import 'services/device_info_service.dart';

bool isTokenExpired(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return true;
    final normalized = base64Url.normalize(parts[1]);
    final payloadString = utf8.decode(base64Url.decode(normalized));
    final payloadMap = jsonDecode(payloadString);
    if (payloadMap is Map<String, dynamic> && payloadMap.containsKey('exp')) {
      final exp = payloadMap['exp'];
      final expInt = exp is int ? exp : int.tryParse(exp.toString()) ?? 0;
      final currentSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return currentSeconds >= expInt;
    }
  } catch (e) {
    return false; // Return false so dummy/malformed tokens bypass client-side expiration forcing a logout on testing
  }
  return false;
}

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
          final path = options.path.toLowerCase();
          final isPublicEndpoint = path.contains('auth/login') ||
              path.contains('auth/register') ||
              path.contains('auth/forgot-password');

          final token = await _storageService.getToken();
          if (!isPublicEndpoint) {
            if (token == null || token.isEmpty) {
              // Token is completely missing — cannot proceed, notify AuthBloc to handle
              debugPrint('Global Auth Interceptor: JWT missing on protected route ($path).');
              onUnauthorized?.call();
              return handler.reject(DioException(
                requestOptions: options,
                error: 'JWT token is missing',
                type: DioExceptionType.cancel,
              ));
            }

            if (isTokenExpired(token)) {
              // Token is expired locally — notify AuthBloc so it can attempt a silent refresh.
              // Do NOT clear storage here; the AuthBloc decides whether to logout or refresh.
              debugPrint('Global Auth Interceptor: JWT expired locally — notifying AuthBloc for refresh.');
              onUnauthorized?.call();
              return handler.reject(DioException(
                requestOptions: options,
                error: 'Token expired locally',
                type: DioExceptionType.cancel,
              ));
            }

            options.headers['Authorization'] = 'Bearer $token';
          }
          
          final schema = await _storageService.getSchema() ?? 'INLDRYRUN';
          options.headers['X-X3-Schema'] = schema;
          
          options.headers['X-Device-Id'] = DeviceInfoService.instance.deviceInfo;
          
          return handler.next(options);
        },
        onError: (DioException e, handler) async {
          if (e.response?.statusCode == 401) {
            // Server rejected our token — notify AuthBloc to handle (it will attempt
            // a silent refresh and only logout if that also fails).
            // Do NOT clear storage here to avoid race conditions with the refresh cycle.
            debugPrint('Global 401 Intercepted: Notifying AuthBloc for session refresh.');
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
          responseBody: false, // Turned off to save memory during big syncs
        ),
      );
    }
  }
}
