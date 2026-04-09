import '../models/user_management.dart';

class UserManagementRepositoryMock {
  static final List<UserRole> roles = [
    const UserRole(
      id: 'role1',
      name: 'Admin',
      permissions: [
        ModuleAccess(
          moduleId: 'manufacturing',
          canCreate: true,
          canRead: true,
          canUpdate: true,
          canDelete: true,
        ),
        ModuleAccess(
          moduleId: 'sales',
          canCreate: true,
          canRead: true,
          canUpdate: true,
          canDelete: true,
        ),
        ModuleAccess(
          moduleId: 'userManagement',
          canCreate: true,
          canRead: true,
          canUpdate: true,
          canDelete: true,
        ),
        ModuleAccess(
          moduleId: 'delivery',
          canCreate: true,
          canRead: true,
          canUpdate: true,
          canDelete: true,
        ),
      ],
    ),
    const UserRole(
      id: 'role2',
      name: 'Manager',
      permissions: [
        ModuleAccess(
          moduleId: 'manufacturing',
          canCreate: false,
          canRead: true,
          canUpdate: true,
          canDelete: false,
        ),
        ModuleAccess(
          moduleId: 'sales',
          canCreate: false,
          canRead: true,
          canUpdate: true,
          canDelete: false,
        ),
        ModuleAccess(
          moduleId: 'userManagement',
          canCreate: false,
          canRead: true,
          canUpdate: false,
          canDelete: false,
        ),
        ModuleAccess(
          moduleId: 'delivery',
          canCreate: true,
          canRead: true,
          canUpdate: true,
          canDelete: false,
        ),
      ],
    ),
    const UserRole(
      id: 'role3',
      name: 'Operator',
      permissions: [
        ModuleAccess(
          moduleId: 'manufacturing',
          canCreate: true,
          canRead: true,
          canUpdate: true,
          canDelete: false,
        ),
        ModuleAccess(
          moduleId: 'sales',
          canCreate: false,
          canRead: true,
          canUpdate: false,
          canDelete: false,
        ),
      ],
    ),
  ];

  static final List<UserGroup> userGroups = [
    const UserGroup(id: 'group1', name: 'IT Department', roleId: 'role1'),
    const UserGroup(id: 'group2', name: 'Production Team', roleId: 'role3'),
    const UserGroup(id: 'group3', name: 'Sales Managers', roleId: 'role2'),
  ];
}
