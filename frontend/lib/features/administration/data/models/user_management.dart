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
  final String description;
  final List<ModuleAccess> permissions;
  final String? siteCode;

  const UserRole({
    required this.id,
    required this.name,
    this.description = '',
    required this.permissions,
    this.siteCode,
  });

  @override
  List<Object?> get props => [id];
}

/// Represents a user in the system.
class User extends Equatable {
  final String id;
  final String username;
  final String email;
  final bool isActive;
  final String? roleId;
  final List<ModuleAccess> permissions;
  final String? siteCode;

  const User({
    required this.id,
    required this.username,
    required this.email,
    required this.isActive,
    this.roleId,
    this.permissions = const [],
    this.siteCode,
  });

  @override
  List<Object?> get props => [id];
}

/// Represents a organizational group that shares a common [UserRole].
class UserGroup extends Equatable {
  final String id;
  final String name;
  final String roleId;

  const UserGroup({required this.id, required this.name, required this.roleId});

  @override
  List<Object?> get props => [id];
}

/// Represents a site/facility in the system.
class Site extends Equatable {
  final String siteCode;
  final String siteName;
  final int isSalesSite;

  const Site({
    required this.siteCode,
    required this.siteName,
    required this.isSalesSite,
  });

  @override
  List<Object?> get props => [siteCode];
}
