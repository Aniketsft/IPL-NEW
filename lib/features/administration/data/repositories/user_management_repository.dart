import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/user_management.dart';

class UserManagementRepository {
  final Dio _dio;
  // The following lines from the user's provided "Code Edit" are syntactically incorrect
  // if placed directly after the _dio initialization.
  // The original _baseUrl getter is kept as it is syntactically correct and functional.
  // if (!kIsWeb && Platform.isAndroid) {
  //     return 'http://10.0.2.2:5004/api';
  //   }
  //   return 'https://localhost:7176/api';
  // }

  static String get _baseUrl {
    if (!kIsWeb && Platform.isAndroid) {
      return 'http://192.168.1.107:5004/api/';
    }
    return 'https://localhost:7176/api/';
  }

  UserManagementRepository()
    : _dio = Dio(
        BaseOptions(
          baseUrl: _baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
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
      throw 'Failed to update role: $e';
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
    required String groupId,
    List<ModuleAccess> permissions = const [],
  }) async {
    try {
      // Flatten ModuleAccess into permission strings expected by backend
      final List<String> permStrings = [];
      for (var access in permissions) {
        if (access.canCreate) permStrings.add('${access.moduleId}.Create');
        if (access.canRead) permStrings.add('${access.moduleId}.Read');
        if (access.canUpdate) permStrings.add('${access.moduleId}.Update');
        if (access.canDelete) permStrings.add('${access.moduleId}.Delete');
      }

      await _dio.post(
        'Users',
        data: {
          'username': username,
          'email': email,
          'password': password,
          'userGroupId': groupId,
          'isActive': true,
          'permissions': permStrings,
        },
        options: Options(contentType: Headers.jsonContentType),
      );
    } catch (e) {
      throw 'Failed to create user: $e';
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
        if (access.canCreate) permStrings.add('${access.moduleId}.Create');
        if (access.canRead) permStrings.add('${access.moduleId}.Read');
        if (access.canUpdate) permStrings.add('${access.moduleId}.Update');
        if (access.canDelete) permStrings.add('${access.moduleId}.Delete');
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
      userGroupId: json['userGroupId'],
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
      permissions: moduleAccessList,
    );
  }

  Map<String, dynamic> _mapRoleToJson(UserRole role) {
    // Generate flat permission list from ModuleAccess
    final List<Map<String, dynamic>> permissions = [];
    for (var access in role.permissions) {
      if (access.canCreate)
        permissions.add({'name': '${access.moduleId}.Create'});
      if (access.canRead) permissions.add({'name': '${access.moduleId}.Read'});
      if (access.canUpdate)
        permissions.add({'name': '${access.moduleId}.Update'});
      if (access.canDelete)
        permissions.add({'name': '${access.moduleId}.Delete'});
    }
    return {'id': role.id, 'name': role.name, 'permissions': permissions};
  }
}
