import 'package:dio/dio.dart';
import 'package:enterprise_auth_mobile/features/auth/domain/entities/user.dart';
import 'package:enterprise_auth_mobile/features/auth/domain/repositories/iauth_repository.dart';
import 'package:enterprise_auth_mobile/features/auth/data/models/user_dto.dart';
import 'package:enterprise_auth_mobile/core/secure_storage_service.dart';
import 'package:enterprise_auth_mobile/core/network_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

class AuthRepository implements IAuthRepository {
  final Dio _dio;
  final SecureStorageService _storageService;

  AuthRepository({
    required NetworkService networkService,
    required SecureStorageService storageService,
  }) : _storageService = storageService,
       _dio = networkService.dio;

  @override
  Future<User> login(String username, String password) async {
    try {
      final response = await _dio.post(
        'Auth/login',
        data: {'username': username, 'password': password},
      );

      final dto = UserDto.fromJson(response.data);

      // 1. Storage Service (Session tokens)
      await _storageService.saveToken(dto.token);
      await _storageService.saveUsername(dto.username);

      // 2. Local DB (Offline caching)
      final db = await LocalDatabaseHelper.instance.database;
      final passHash = sha256.convert(utf8.encode(password)).toString();

      await db.insert(
        LocalDatabaseHelper.tableCachedUsers,
        {
          LocalDatabaseHelper.colUserUsername: dto.username,
          LocalDatabaseHelper.colUserPassHash: passHash,
          LocalDatabaseHelper.colUserPermissions: jsonEncode(dto.permissions),
          LocalDatabaseHelper.colUserEmail: dto.email,
          LocalDatabaseHelper.colUserId: dto.id,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      return User(
        id: dto.id,
        username: dto.username,
        email: dto.email,
        permissions: dto.permissions.map((p) => p.toLowerCase()).toList(),
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        return _attemptOfflineLogin(username, password);
      }
      throw _handleDioError(e, 'Login');
    } catch (e) {
      throw 'Unexpected error: $e';
    }
  }

  Future<User> _attemptOfflineLogin(String username, String password) async {
    final db = await LocalDatabaseHelper.instance.database;
    final passHash = sha256.convert(utf8.encode(password)).toString();

    final maps = await db.query(
      LocalDatabaseHelper.tableCachedUsers,
      where:
          '${LocalDatabaseHelper.colUserUsername} = ? AND ${LocalDatabaseHelper.colUserPassHash} = ?',
      whereArgs: [username, passHash],
    );

    if (maps.isNotEmpty) {
      final row = maps.first;
      final permissions =
          jsonDecode(row[LocalDatabaseHelper.colUserPermissions] as String)
              as List;

      return User(
        id: row[LocalDatabaseHelper.colUserId] as String,
        username: row[LocalDatabaseHelper.colUserUsername] as String,
        email: row[LocalDatabaseHelper.colUserEmail] as String,
        permissions: permissions
            .map((p) => (p as String).toLowerCase())
            .toList(),
      );
    }

    throw 'Cannot reach server and no valid offline credentials found.';
  }

  @override
  Future<void> register(String email, String username, String password) async {
    try {
      await _dio.post(
        'Auth/register',
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
      await _dio.post('Auth/forgot-password', data: {'email': email});
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
