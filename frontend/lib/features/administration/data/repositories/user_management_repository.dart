import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/user_management.dart';
import 'package:enterprise_auth_mobile/core/config/api_config.dart';
import 'package:enterprise_auth_mobile/core/secure_storage_service.dart';

class UserManagementRepository {
  final Dio _dio;

  static String get _baseUrl => ApiConfig.baseUrl;

  UserManagementRepository({Dio? dio}) : _dio = dio ?? _createDefaultDio();

  static Dio _createDefaultDio() {
    final dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );

    if (kDebugMode && !kIsWeb) {
      (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        client.badCertificateCallback =
            (X509Certificate cert, String host, int port) => true;
        return client;
      };
    }

    final storageService = SecureStorageService();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await storageService.getToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          final schema = await storageService.getSchema() ?? 'INLDRYRUN';
          options.headers['X-X3-Schema'] = schema;
          return handler.next(options);
        },
      ),
    );

    return dio;
  }

  Future<void> changePassword(String userId, String newPassword) async {
    try {
      await _dio.put(
        'Users/$userId/password',
        data: {'password': newPassword},
        options: Options(contentType: Headers.jsonContentType),
      );
    } catch (e) {
      throw 'Failed to change password: $e';
    }
  }

  // Roles
  Future<List<UserRole>> getRoles() async {
    try {
      final response = await _dio.get('Roles');
      final data = response.data as List;
      return data.map((json) => _mapJsonToRole(json)).toList();
    } catch (e) {
      throw 'Failed to fetch roles: $e';
    }
  }

  Future<void> updateRole(UserRole role) async {
    try {
      await _dio.put(
        'Roles/${role.id}',
        data: _mapRoleToJson(role),
        options: Options(contentType: Headers.jsonContentType),
      );
    } catch (e) {
      throw 'Failed to update role: $e. Response: ${e is DioException ? e.response?.data : ""}';
    }
  }

  Future<void> deleteRole(String roleId) async {
    try {
      await _dio.delete('Roles/$roleId');
    } catch (e) {
      throw 'Failed to delete role: $e';
    }
  }

  // Groups
  Future<List<UserGroup>> getGroups() async {
    try {
      final response = await _dio.get('UserGroups');
      final data = response.data as List;
      return data
          .map(
            (json) => UserGroup(
              id: json['id'],
              name: json['name'],
              roleId: json['roleId'],
            ),
          )
          .toList();
    } catch (e) {
      throw 'Failed to fetch groups: $e';
    }
  }

  Future<void> updateGroup(UserGroup group) async {
    try {
      await _dio.put(
        'UserGroups/${group.id}',
        data: {'id': group.id, 'name': group.name, 'roleId': group.roleId},
        options: Options(contentType: Headers.jsonContentType),
      );
    } catch (e) {
      throw 'Failed to update group: $e';
    }
  }

  // Users
  Future<void> createUser({
    required String fullName,
    required String username,
    required String email,
    required String password,
    required String? roleId,
    required String? siteCode,
    List<ModuleAccess> permissions = const [],
  }) async {
    try {
      // Flatten ModuleAccess into permission strings expected by backend
      final List<String> permStrings = [];
      for (var access in permissions) {
        if (access.canCreate) permStrings.add('${access.moduleId}.create');
        if (access.canRead) permStrings.add('${access.moduleId}.read');
        if (access.canUpdate) permStrings.add('${access.moduleId}.update');
        if (access.canDelete) permStrings.add('${access.moduleId}.delete');
      }

      await _dio.post(
        'Users',
        data: {
          'username': username,
          'email': email,
          'password': password,
          'roleId': roleId,
          'isActive': true,
          'permissions': permStrings,
          'siteCode': siteCode,
        },
        options: Options(contentType: Headers.jsonContentType),
      );
    } catch (e) {
      throw 'Failed to create user: $e';
    }
  }

  Future<void> updateUser(User user) async {
    try {
      await _dio.put(
        'Users/${user.id}',
        data: {
          'id': user.id,
          'username': user.username,
          'email': user.email,
          'isActive': user.isActive,
          'roleId': user.roleId,
          'siteCode': user.siteCode,
        },
        options: Options(contentType: Headers.jsonContentType),
      );
    } catch (e) {
      throw 'Failed to update user: $e';
    }
  }

  Future<void> createRole(UserRole role) async {
    try {
      await _dio.post(
        'Roles',
        data: _mapRoleToJson(role),
        options: Options(contentType: Headers.jsonContentType),
      );
    } catch (e) {
      throw 'Failed to create role: $e';
    }
  }

  // Mapping helpers
  Future<List<User>> getUsers() async {
    try {
      final response = await _dio.get('Users');
      return (response.data as List)
          .map((json) => _mapJsonToUser(json))
          .toList();
    } catch (e) {
      throw 'Failed to fetch users: $e';
    }
  }

  Future<void> updateUserPermissions(
    String userId,
    List<ModuleAccess> permissions,
  ) async {
    try {
      // Flatten ModuleAccess into permission strings expected by backend
      final List<String> permStrings = [];
      for (var access in permissions) {
        if (access.canCreate) permStrings.add('${access.moduleId}.create');
        if (access.canRead) permStrings.add('${access.moduleId}.read');
        if (access.canUpdate) permStrings.add('${access.moduleId}.update');
        if (access.canDelete) permStrings.add('${access.moduleId}.delete');
      }

      await _dio.put(
        'Users/$userId/permissions',
        data: permStrings,
        options: Options(contentType: Headers.jsonContentType),
      );
    } catch (e) {
      throw 'Failed to update user permissions: $e';
    }
  }

  User _mapJsonToUser(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      email: json['email'],
      isActive: json['isActive'],
      roleId: json['roleId'],
      permissions: (json['permissions'] as List? ?? [])
          .map((p) => p.toString())
          .fold<Map<String, ModuleAccess>>({}, (acc, p) {
            final parts = p.split('.');
            if (parts.length < 2) return acc;

            // The last part is always the action
            final action = parts.last.toLowerCase();
            // Everything before the last part is the moduleId
            final moduleId = parts.sublist(0, parts.length - 1).join('.');

            final current = acc[moduleId] ?? ModuleAccess(moduleId: moduleId);
            acc[moduleId] = current.copyWith(
              canCreate: action == 'create' ? true : current.canCreate,
              canRead: action == 'read' ? true : current.canRead,
              canUpdate: action == 'update' ? true : current.canUpdate,
              canDelete: action == 'delete' ? true : current.canDelete,
            );
            return acc;
          })
          .values
          .toList(),
      siteCode: json['siteCode'],
    );
  }

  UserRole _mapJsonToRole(Map<String, dynamic> json) {
    final permissions = json['permissions'] as List;
    final Map<String, List<String>> moduleActions = {};

    for (var p in permissions) {
      final name = p['name'] as String;
      final parts = name.split('.');
      if (parts.length >= 2) {
        final action = parts.last.toLowerCase();
        final moduleId = parts.sublist(0, parts.length - 1).join('.');
        moduleActions.putIfAbsent(moduleId, () => []).add(action);
      }
    }

    final moduleAccessList = moduleActions.entries.map((entry) {
      return ModuleAccess(
        moduleId: entry.key,
        canCreate: entry.value.contains('create'),
        canRead: entry.value.contains('read'),
        canUpdate: entry.value.contains('update'),
        canDelete: entry.value.contains('delete'),
      );
    }).toList();

    return UserRole(
      id: json['id'],
      name: json['name'],
      description: json['description'] ?? '',
      permissions: moduleAccessList,
      siteCode: json['siteCode'],
    );
  }

  Map<String, dynamic> _mapRoleToJson(UserRole role) {
    // Generate flat permission list from ModuleAccess
    final List<Map<String, dynamic>> permissions = [];
    for (var access in role.permissions) {
      if (access.canCreate) {
        permissions.add({'name': '${access.moduleId}.create'});
      }
      if (access.canRead) permissions.add({'name': '${access.moduleId}.read'});
      if (access.canUpdate) {
        permissions.add({'name': '${access.moduleId}.update'});
      }
      if (access.canDelete) {
        permissions.add({'name': '${access.moduleId}.delete'});
      }
    }
    final map = {
      'name': role.name,
      'description': role.description,
      'permissions': permissions,
      'siteCode': role.siteCode
    };
    if (role.id.isNotEmpty) {
      map['id'] = role.id;
    }
    return map;
  }

  // Sites
  Future<List<Site>> getSites() async {
    try {
      final response = await _dio.get('Sites');
      final data = response.data as List;
      return data
          .map(
            (json) => Site(
              siteCode: json['siteCode'],
              siteName: json['siteName'],
              isSalesSite: json['isSalesSite'],
            ),
          )
          .toList();
    } catch (e) {
      throw 'Failed to fetch sites: $e';
    }
  }
}
