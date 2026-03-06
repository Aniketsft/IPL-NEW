import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:enterprise_auth_mobile/features/auth/domain/entities/user.dart';
import 'package:enterprise_auth_mobile/features/auth/domain/repositories/iauth_repository.dart';
import 'package:enterprise_auth_mobile/features/auth/data/models/user_dto.dart';
import 'package:enterprise_auth_mobile/core/secure_storage_service.dart';

class AuthRepository implements IAuthRepository {
  final Dio _dio;
  final SecureStorageService _storageService;

  // Use 10.0.2.2 for Android Emulator; localhost otherwise
  static String get _baseUrl {
    if (!kIsWeb && Platform.isAndroid) {
      return 'http://192.168.1.107:5004/api/Auth/';
    }
    return 'https://localhost:7176/api/Auth/';
  }

  AuthRepository({required SecureStorageService storageService})
    : _storageService = storageService,
      _dio = Dio(
        BaseOptions(
          baseUrl: _baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 10),
        ),
      ) {
    // SSL Bypass for local development (self-signed certs)
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
  Future<User> login(String username, String password) async {
    try {
      final response = await _dio.post(
        'login',
        data: {'username': username, 'password': password},
      );

      final dto = UserDto.fromJson(response.data);

      // Save sensitive data in repository implementation (Data Layer responsibility)
      await _storageService.saveToken(dto.token);
      await _storageService.saveUsername(dto.username);

      return User(
        id: dto.id,
        username: dto.username,
        email: dto.email,
        permissions: dto.permissions.map((p) => p.toLowerCase()).toList(),
      );
    } on DioException catch (e) {
      throw _handleDioError(e, 'Login');
    } catch (e) {
      throw 'Unexpected error: $e';
    }
  }

  @override
  Future<void> register(String email, String username, String password) async {
    try {
      await _dio.post(
        'register',
        data: {'email': email, 'username': username, 'password': password},
      );
    } on DioException catch (e) {
      throw _handleDioError(e, 'Registration');
    } catch (e) {
      throw 'Unexpected error: $e';
    }
  }

  @override
  Future<void> forgotPassword(String email) async {
    try {
      await _dio.post('forgot-password', data: {'email': email});
    } on DioException catch (e) {
      throw _handleDioError(e, 'Password Reset');
    } catch (e) {
      throw 'Unexpected error: $e';
    }
  }

  @override
  Future<void> logout() async {
    await _storageService.deleteAll();
  }

  String _handleDioError(DioException e, String operation) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return '$operation failed: Server timed out. Check if backend is running on ${_baseUrl}.';
    }
    if (e.type == DioExceptionType.connectionError) {
      return '$operation failed: Cannot reach server at ${_baseUrl}. Ensure backend is running and firewall allows port 5004.';
    }
    if (e.response != null) {
      final data = e.response?.data;
      if (data is Map && data.containsKey('message')) {
        return data['message'];
      }
      return '$operation failed: Server returned ${e.response?.statusCode}';
    }
    return '$operation failed: ${e.message}';
  }
}
