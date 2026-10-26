import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'secure_storage_service.dart';
import 'config/api_config.dart';
import 'services/device_info_service.dart';

bool isTokenExpired(String token) {
  if (token.startsWith('OFFLINE_SESSION_')) return false; // Offline session governed by AuthConfig.offlineLoginWindow
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
        headers: {
          'Accept-Encoding': 'gzip, deflate',
        },
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
            if (token == null || token.isEmpty || token.startsWith('OFFLINE_SESSION_')) {
              // Device is operating in offline mode or token not yet issued — reject network request safely without session eviction.
              debugPrint('Global Auth Interceptor: Offline session or JWT missing on ($path). Suppressing network request.');
              return handler.reject(DioException(
                requestOptions: options,
                error: 'Device is operating in offline mode. Connect to network to synchronize.',
                type: DioExceptionType.connectionError,
              ));
            }

            final isRefreshCall = path.contains('auth/refresh');
            if (isTokenExpired(token) && !isRefreshCall) {
              // Token expired locally — reject network call without evicting the offline user.
              debugPrint('Global Auth Interceptor: JWT expired locally on ($path). Rejecting without session eviction.');
              return handler.reject(DioException(
                requestOptions: options,
                error: 'Token expired locally. Please sync when online.',
                type: DioExceptionType.connectionError,
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
            return handler.next(e);
          }

          // Retry logic for transient errors on idempotent GET operations (sync pull)
          final isGet = e.requestOptions.method.toUpperCase() == 'GET';
          final statusCode = e.response?.statusCode;
          final isTransient = statusCode == 429 ||
              statusCode == 502 ||
              statusCode == 503 ||
              statusCode == 504 ||
              e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.receiveTimeout;

          if (isGet && isTransient) {
            final currentRetry =
                (e.requestOptions.extra['_retryCount'] as int? ?? 0);
            if (currentRetry < 2) {
              e.requestOptions.extra['_retryCount'] = currentRetry + 1;
              final backoffMs =
                  (500 * (1 << currentRetry)) + math.Random().nextInt(400);
              debugPrint(
                  'Network transient error ($statusCode / ${e.type}). Retrying GET ${e.requestOptions.path} in ${backoffMs}ms (attempt ${currentRetry + 1}/2)...');
              await Future.delayed(Duration(milliseconds: backoffMs));
              try {
                final retryResponse = await dio.fetch(e.requestOptions);
                return handler.resolve(retryResponse);
              } on DioException catch (retryErr) {
                return handler.next(retryErr);
              } catch (_) {
                return handler.next(e);
              }
            }
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
