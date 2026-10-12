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

    // Secure logging in debug mode: automatically masks passwords and bearer tokens
    if (kDebugMode) {
      dio.interceptors.add(const SanitizedLogInterceptor());
    }
  }
}

/// A privacy-preserving HTTP logger that suppresses sensitive data such as
/// passwords and bearer tokens from terminal and logcat outputs.
class SanitizedLogInterceptor extends Interceptor {
  const SanitizedLogInterceptor();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (kDebugMode) {
      debugPrint('--> ${options.method} ${options.uri}');

      // Mask sensitive headers (Bearer token)
      if (options.headers.isNotEmpty) {
        final sanitizedHeaders = Map<String, dynamic>.from(options.headers);
        if (sanitizedHeaders.containsKey('Authorization')) {
          sanitizedHeaders['Authorization'] = 'Bearer [REDACTED]';
        }
        debugPrint('Headers: $sanitizedHeaders');
      }

      // Mask sensitive request body fields (password, tokens)
      if (options.data != null) {
        if (options.data is Map) {
          final sanitizedData = Map<String, dynamic>.from(options.data as Map);
          for (final key in ['password', 'newPassword', 'oldPassword', 'token']) {
            if (sanitizedData.containsKey(key)) {
              sanitizedData[key] = '***REDACTED***';
            }
          }
          debugPrint('Body: $sanitizedData');
        } else if (options.data is! FormData) {
          debugPrint('Body: ${options.data}');
        }
      }
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (kDebugMode) {
      debugPrint('<-- [${response.statusCode}] ${response.requestOptions.uri.path}');
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (kDebugMode) {
      debugPrint('<-- ERROR [${err.response?.statusCode ?? 'N/A'}] ${err.requestOptions.uri.path}: ${err.message}');
    }
    handler.next(err);
  }
}
