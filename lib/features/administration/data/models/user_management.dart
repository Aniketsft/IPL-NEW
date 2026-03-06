import 'package:equatable/equatable.dart';

/// Defines granular access permissions for a specific module.
class ModuleAccess extends Equatable {
  final String moduleId;
  final bool canCreate;
  final bool canRead;
  final bool canUpdate;
  final bool canDelete;

  const ModuleAccess({
    required this.moduleId,
    this.canCreate = false,
    this.canRead = false,
    this.canUpdate = false,
    this.canDelete = false,
  });

  ModuleAccess copyWith({
    bool? canCreate,
    bool? canRead,
    bool? canUpdate,
    bool? canDelete,
  }) {
    return ModuleAccess(
      moduleId: moduleId,
      canCreate: canCreate ?? this.canCreate,
      canRead: canRead ?? this.canRead,
      canUpdate: canUpdate ?? this.canUpdate,
      canDelete: canDelete ?? this.canDelete,
    );
  }

  @override
  List<Object?> get props => [
    moduleId,
    canCreate,
    canRead,
    canUpdate,
    canDelete,
  ];
}

/// Represents a set of permissions that can be assigned to a group or user.
class UserRole extends Equatable {
  final String id;
  final String name;
  final List<ModuleAccess> permissions;

  const UserRole({
    required this.id,
    required this.name,
    required this.permissions,
  });

  @override
  List<Object?> get props => [id, name, permissions];
}

/// Represents a user in the system.
class User extends Equatable {
  final String id;
  final String username;
  final String email;
  final bool isActive;
  final String? userGroupId;
  final List<ModuleAccess> permissions;

  const User({
    required this.id,
    required this.username,
    required this.email,
    required this.isActive,
    this.userGroupId,
    this.permissions = const [],
  });

  @override
  List<Object?> get props => [
    id,
    username,
    email,
    isActive,
    userGroupId,
    permissions,
  ];
}

/// Represents a organizational group that shares a common [UserRole].
class UserGroup extends Equatable {
  final String id;
  final String name;
  final String roleId;

  const UserGroup({required this.id, required this.name, required this.roleId});

  @override
  List<Object?> get props => [id, name, roleId];
}
