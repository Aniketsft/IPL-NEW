import 'package:flutter/material.dart';
import '../../../../core/widgets/industrial_module_layout.dart';
import '../../data/models/user_management.dart';
import '../../data/repositories/user_management_repository.dart';

class PermissionNode {
  final String label;
  final String moduleId;
  final List<PermissionNode> children;

  PermissionNode({
    required this.label,
    required this.moduleId,
    this.children = const [],
  });
}

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Selected state
  UserRole? _selectedRole;
  UserGroup? _selectedGroup;

  final UserManagementRepository _repository = UserManagementRepository();

  // Local state for editing roles
  List<UserRole> _localRoles = [];
  List<UserGroup> _localGroups = [];

  bool _isLoading = true;

  bool _isSavingRole = false;
  bool _isSavingGroup = false;
  bool _isCreatingUser = false;
  bool _useCustomPermissions = false;
  List<ModuleAccess> _selectedUserPermissions = [];

  // Selected state for User Creation
  UserGroup? _selectedCreationGroup;

  // State for Managing Existing Users
  List<User> _allUsers = [];
  User? _selectedManagementUser;
  bool _isSavingUserPermissions = false;

  // Controllers for User Creation
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // Define the permission tree structure based on Home Screen order
  final List<PermissionNode> _permissionTree = [
    PermissionNode(
      label: 'LOGISTICS',
      moduleId: 'logistics',
      children: [
        PermissionNode(label: 'Receipt', moduleId: 'logistics.receipt'),
        PermissionNode(label: 'Transfer', moduleId: 'logistics.transfer'),
        PermissionNode(label: 'Delivery', moduleId: 'logistics.delivery'),
      ],
    ),
    PermissionNode(
      label: 'MANUFACTURING',
      moduleId: 'manufacturing',
      children: [
        PermissionNode(label: 'Dashboard', moduleId: 'manufacturing.dashboard'),
        PermissionNode(
          label: 'View Sales Order',
          moduleId: 'manufacturing.view_sales_order',
          children: [
            PermissionNode(
              label: 'Sales Order',
              moduleId: 'manufacturing.view_sales_order.sales_order',
            ),
          ],
        ),
        PermissionNode(
          label: 'Work Order',
          moduleId: 'manufacturing.work_order',
        ),
        PermissionNode(label: 'Tracking', moduleId: 'manufacturing.tracking'),
        PermissionNode(
          label: 'Components',
          moduleId: 'manufacturing.components',
        ),
        PermissionNode(label: 'Products', moduleId: 'manufacturing.products'),
      ],
    ),
    PermissionNode(
      label: 'INVENTORY',
      moduleId: 'inventory',
      children: [
        PermissionNode(
          label: 'Stock Control',
          moduleId: 'inventory.stock_control',
        ),
        PermissionNode(label: 'Picking', moduleId: 'inventory.picking'),
        PermissionNode(
          label: 'By Identifier',
          moduleId: 'inventory.by_identifier',
        ),
      ],
    ),
    PermissionNode(
      label: 'ADMINISTRATION',
      moduleId: 'administration',
      children: [
        PermissionNode(
          label: 'User Management',
          moduleId: 'administration.user_management',
        ),
      ],
    ),
    PermissionNode(
      label: 'SETTINGS',
      moduleId: 'settings',
      children: [
        PermissionNode(label: 'General', moduleId: 'settings.general'),
        PermissionNode(label: 'Printer', moduleId: 'settings.printer'),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final roles = await _repository.getRoles();
      final groups = await _repository.getGroups();
      final users = await _repository.getUsers();
      if (mounted) {
        setState(() {
          _localRoles = roles;
          _localGroups = groups;
          _allUsers = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading data: $e')));
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _fullNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tabColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return IndustrialModuleLayout(
      title: 'User Management',
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF9800)),
            )
          : Column(
              children: [
                Container(
                  color: tabColor,
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: const Color(0xFFFF9800),
                    labelColor: const Color(0xFFFF9800),
                    unselectedLabelColor: isDark
                        ? Colors.white54
                        : Colors.black54,
                    tabs: const [
                      Tab(text: 'ROLES'),
                      Tab(text: 'USER GROUPS'),
                      Tab(text: 'USERS'),
                      Tab(text: 'EXISTING USERS'),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildRolesTab(isDark),
                      _buildGroupsTab(isDark),
                      _buildUsersTab(isDark),
                      _buildManageUsersTab(isDark),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ---------------------------------------------------------
  // PERMISSION SELECTION UI (REUSABLE)
  // ---------------------------------------------------------

  Widget _buildPermissionMatrixLayout({
    required List<ModuleAccess> permissions,
    required bool isDark,
    required Function(String moduleId, String type, bool value) onUpdate,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _headerLabel('C'),
            _headerLabel('R'),
            _headerLabel('U'),
            _headerLabel('D'),
          ],
        ),
        const SizedBox(height: 10),
        ..._permissionTree.expand(
          (rootNode) => _buildPermissionTreeRows(
            rootNode,
            permissions,
            isDark,
            onUpdate,
            0,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildPermissionTreeRows(
    PermissionNode node,
    List<ModuleAccess> permissions,
    bool isDark,
    Function(String moduleId, String type, bool value) onUpdate,
    int depth,
  ) {
    final List<Widget> rows = [];

    // Check if this node itself has permissions (some might be just headers)
    // In our current structure, all nodes have moduleId and thus permissions.
    final perm = permissions.firstWhere(
      (p) => p.moduleId == node.moduleId,
      orElse: () => ModuleAccess(moduleId: node.moduleId),
    );

    rows.add(_buildMatrixRowLayout(node.label, perm, isDark, onUpdate, depth));

    if (node.children.isNotEmpty) {
      for (var child in node.children) {
        rows.addAll(
          _buildPermissionTreeRows(
            child,
            permissions,
            isDark,
            onUpdate,
            depth + 1,
          ),
        );
      }
    }

    return rows;
  }

  Widget _buildMatrixRowLayout(
    String label,
    ModuleAccess perm,
    bool isDark,
    Function(String moduleId, String type, bool value) onUpdate,
    int depth,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.only(
        left: 16.0 + (depth * 20.0),
        top: 12,
        bottom: 12,
        right: 16,
      ),
      decoration: BoxDecoration(
        color: isDark
            ? (depth == 0 ? const Color(0xFF2C2C2E) : const Color(0xFF252528))
            : (depth == 0 ? Colors.grey[100] : Colors.white),
        borderRadius: BorderRadius.circular(8),
        border: depth == 0
            ? Border.all(color: const Color(0xFFFF9800).withOpacity(0.3))
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              depth == 0 ? label.toUpperCase() : label,
              style: TextStyle(
                fontWeight: depth == 0 ? FontWeight.bold : FontWeight.w500,
                fontSize: depth == 0 ? 14 : 13,
                color: depth == 0
                    ? const Color(0xFFFF9800)
                    : (isDark ? Colors.white : Colors.black87),
              ),
            ),
          ),
          _matrixToggle(
            perm.canCreate,
            (v) => onUpdate(perm.moduleId, 'create', v),
          ),
          _matrixToggle(
            perm.canRead,
            (v) => onUpdate(perm.moduleId, 'read', v),
          ),
          _matrixToggle(
            perm.canUpdate,
            (v) => onUpdate(perm.moduleId, 'update', v),
          ),
          _matrixToggle(
            perm.canDelete,
            (v) => onUpdate(perm.moduleId, 'delete', v),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------
  // ROLES TAB
  // ---------------------------------------------------------

  Widget _buildRolesTab(bool isDark) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: _buildRoleSelector(isDark),
        ),
        if (_selectedRole != null)
          Expanded(child: _buildPermissionMatrix(isDark))
        else
          const Expanded(
            child: Center(
              child: Text(
                'Select a role to manage permissions',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
        _buildActionFooter('SAVE ROLE', _isSavingRole, () async {
          setState(() => _isSavingRole = true);
          try {
            await _repository.updateRole(_selectedRole!);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Role permissions saved successfully!'),
                ),
              );
              await _loadData();
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to save role: $e')),
              );
            }
          } finally {
            if (mounted) setState(() => _isSavingRole = false);
          }
        }),
      ],
    );
  }

  Widget _buildRoleSelector(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF38383B) : Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<UserRole>(
          value: _selectedRole,
          hint: const Text('Select Role'),
          isExpanded: true,
          dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          items: _localRoles.map((r) {
            return DropdownMenuItem(value: r, child: Text(r.name));
          }).toList(),
          onChanged: (val) => setState(() => _selectedRole = val),
        ),
      ),
    );
  }

  Widget _buildPermissionMatrix(bool isDark) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        _buildPermissionMatrixLayout(
          permissions: _selectedRole!.permissions,
          isDark: isDark,
          onUpdate: _updatePermission,
        ),
      ],
    );
  }

  Widget _headerLabel(String text) {
    return SizedBox(
      width: 40,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.grey,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  void _updateUserPermission(String moduleId, String type, bool value) {
    setState(() {
      final idx = _selectedUserPermissions.indexWhere(
        (p) => p.moduleId == moduleId,
      );
      ModuleAccess updatedPerm;
      if (idx != -1) {
        updatedPerm = _getUpdatedPerm(
          _selectedUserPermissions[idx],
          type,
          value,
        );
        _selectedUserPermissions[idx] = updatedPerm;
      } else {
        updatedPerm = _getUpdatedPerm(
          ModuleAccess(moduleId: moduleId),
          type,
          value,
        );
        _selectedUserPermissions.add(updatedPerm);
      }
    });
  }

  void _updatePermission(String moduleId, String type, bool value) {
    if (_selectedRole == null) return;

    setState(() {
      final roleIdx = _localRoles.indexOf(_selectedRole!);
      final List<ModuleAccess> perms = List.from(_selectedRole!.permissions);
      final permIdx = perms.indexWhere((p) => p.moduleId == moduleId);

      ModuleAccess updatedPerm;
      if (permIdx != -1) {
        updatedPerm = _getUpdatedPerm(perms[permIdx], type, value);
        perms[permIdx] = updatedPerm;
      } else {
        updatedPerm = _getUpdatedPerm(
          ModuleAccess(moduleId: moduleId),
          type,
          value,
        );
        perms.add(updatedPerm);
      }

      _localRoles[roleIdx] = UserRole(
        id: _selectedRole!.id,
        name: _selectedRole!.name,
        permissions: perms,
      );
      _selectedRole = _localRoles[roleIdx];
    });
  }

  ModuleAccess _getUpdatedPerm(ModuleAccess old, String type, bool value) {
    switch (type) {
      case 'create':
        return old.copyWith(canCreate: value);
      case 'read':
        return old.copyWith(canRead: value);
      case 'update':
        return old.copyWith(canUpdate: value);
      case 'delete':
        return old.copyWith(canDelete: value);
      default:
        return old;
    }
  }

  Widget _matrixToggle(bool value, Function(bool) onChanged) {
    return SizedBox(
      width: 40,
      child: Center(
        child: Transform.scale(
          scale: 0.8,
          child: Checkbox(
            value: value,
            onChanged: (v) => onChanged(v ?? false),
            activeColor: const Color(0xFFFF9800),
            side: const BorderSide(color: Colors.grey),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------
  // GROUPS TAB
  // ---------------------------------------------------------

  Widget _buildGroupsTab(bool isDark) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: _buildGroupSelector(isDark),
        ),
        if (_selectedGroup != null)
          Expanded(child: _buildGroupAssignmentUI(isDark))
        else
          const Expanded(
            child: Center(
              child: Text(
                'Select a group to manage assignment',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
        _buildActionFooter('SAVE GROUP', _isSavingGroup, () async {
          setState(() => _isSavingGroup = true);
          try {
            await _repository.updateGroup(_selectedGroup!);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Group assignments updated successfully!'),
                ),
              );
              await _loadData();
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to update group: $e')),
              );
            }
          } finally {
            if (mounted) setState(() => _isSavingGroup = false);
          }
        }),
      ],
    );
  }

  Widget _buildGroupSelector(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF38383B) : Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<UserGroup>(
          value: _selectedGroup,
          hint: const Text('Select User Group'),
          isExpanded: true,
          dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          items: _localGroups.map((g) {
            return DropdownMenuItem(value: g, child: Text(g.name));
          }).toList(),
          onChanged: (val) => setState(() => _selectedGroup = val),
        ),
      ),
    );
  }

  Widget _buildGroupAssignmentUI(bool isDark) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        const Text(
          'ASSIGNED ROLE',
          style: TextStyle(
            color: Colors.grey,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF252528) : Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: _localRoles.map((role) {
              return RadioListTile<String>(
                title: Text(
                  role.name,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                value: role.id,
                groupValue: _selectedGroup!.roleId,
                activeColor: const Color(0xFFFF9800),
                onChanged: (val) {
                  setState(() {
                    final idx = _localGroups.indexOf(_selectedGroup!);
                    _localGroups[idx] = UserGroup(
                      id: _selectedGroup!.id,
                      name: _selectedGroup!.name,
                      roleId: val!,
                    );
                    _selectedGroup = _localGroups[idx];
                  });
                },
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------
  // USERS TAB
  // ---------------------------------------------------------

  Widget _buildUsersTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CREATE NEW USER',
            style: TextStyle(
              color: Colors.grey,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          _buildInputField('Full Name', _fullNameController, isDark),
          const SizedBox(height: 16),
          _buildInputField('Username', _usernameController, isDark),
          const SizedBox(height: 16),
          _buildInputField('Email', _emailController, isDark),
          const SizedBox(height: 16),
          _buildInputField(
            'Password',
            _passwordController,
            isDark,
            isPassword: true,
          ),
          const SizedBox(height: 16),

          // Added Group selector as User belongs to a Group conceptually in the original app flow
          const Text(
            'Assign Group',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF38383B) : Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<UserGroup>(
                value: _selectedCreationGroup,
                hint: const Text('Select Group'),
                isExpanded: true,
                dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                items: _localGroups.map((g) {
                  return DropdownMenuItem(value: g, child: Text(g.name));
                }).toList(),
                onChanged: (val) =>
                    setState(() => _selectedCreationGroup = val),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF38383B) : Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Custom Permissions',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                Switch(
                  value: _useCustomPermissions,
                  onChanged: (val) {
                    setState(() {
                      _useCustomPermissions = val;
                      if (val && _selectedCreationGroup != null) {
                        // Initialize with group permissions if possible
                        final role = _localRoles.firstWhere(
                          (r) => r.id == _selectedCreationGroup!.roleId,
                        );
                        _selectedUserPermissions = List.from(role.permissions);
                      }
                    });
                  },
                  activeColor: const Color(0xFFFF9800),
                ),
              ],
            ),
          ),
          if (_useCustomPermissions) ...[
            const SizedBox(height: 24),
            _buildPermissionMatrixLayout(
              permissions: _selectedUserPermissions,
              isDark: isDark,
              onUpdate: _updateUserPermission,
            ),
          ],
          const SizedBox(height: 32),
          _buildActionFooter('CREATE USER', _isCreatingUser, _handleCreateUser),
        ],
      ),
    );
  }

  Widget _buildInputField(
    String label,
    TextEditingController controller,
    bool isDark, {
    bool isPassword = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF38383B) : Colors.grey[200],
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextField(
            controller: controller,
            obscureText: isPassword,
            style: TextStyle(
              fontSize: 15,
              color: isDark ? Colors.white : Colors.black87,
            ),
            decoration: const InputDecoration(border: InputBorder.none),
          ),
        ),
      ],
    );
  }

  Future<void> _handleCreateUser() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in required fields.')),
      );
      return;
    }

    setState(() => _isCreatingUser = true);
    try {
      await _repository.createUser(
        fullName: _fullNameController.text,
        username: _usernameController.text,
        email: _emailController.text,
        password: _passwordController.text,
        groupId: _selectedCreationGroup!.id,
        permissions: _useCustomPermissions ? _selectedUserPermissions : [],
      );

      if (mounted) {
        _fullNameController.clear();
        _usernameController.clear();
        _emailController.clear();
        _passwordController.clear();
        setState(() => _selectedCreationGroup = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User created successfully!')),
        );
        await _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to create user: $e')));
      }
    } finally {
      if (mounted) setState(() => _isCreatingUser = false);
    }
  }

  // ---------------------------------------------------------
  // EXISTING USERS TAB
  // ---------------------------------------------------------

  Widget _buildManageUsersTab(bool isDark) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: _buildUserSelector(isDark),
        ),
        if (_selectedManagementUser != null)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                _buildPermissionMatrixLayout(
                  permissions: _selectedManagementUser!.permissions,
                  isDark: isDark,
                  onUpdate: _updateExistingUserPermission,
                ),
              ],
            ),
          )
        else
          const Expanded(
            child: Center(
              child: Text(
                'Select a user to manage permissions',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
        _buildActionFooter('SAVE CHANGES', _isSavingUserPermissions, () async {
          if (_selectedManagementUser == null) return;
          setState(() => _isSavingUserPermissions = true);
          try {
            await _repository.updateUserPermissions(
              _selectedManagementUser!.id,
              _selectedManagementUser!.permissions,
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('User permissions updated!')),
              );
              await _loadData();
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Update failed: $e')));
            }
          } finally {
            if (mounted) setState(() => _isSavingUserPermissions = false);
          }
        }),
      ],
    );
  }

  Widget _buildUserSelector(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF38383B) : Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<User>(
          value: _selectedManagementUser,
          hint: const Text('Select User'),
          isExpanded: true,
          dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          items: _allUsers.map((u) {
            return DropdownMenuItem(value: u, child: Text(u.username));
          }).toList(),
          onChanged: (val) => setState(() => _selectedManagementUser = val),
        ),
      ),
    );
  }

  void _updateExistingUserPermission(String moduleId, String type, bool value) {
    if (_selectedManagementUser == null) return;

    setState(() {
      final userIdx = _allUsers.indexOf(_selectedManagementUser!);
      final List<ModuleAccess> perms = List.from(
        _selectedManagementUser!.permissions,
      );
      final permIdx = perms.indexWhere((p) => p.moduleId == moduleId);

      ModuleAccess updatedPerm;
      if (permIdx != -1) {
        updatedPerm = _getUpdatedPerm(perms[permIdx], type, value);
        perms[permIdx] = updatedPerm;
      } else {
        updatedPerm = _getUpdatedPerm(
          ModuleAccess(moduleId: moduleId),
          type,
          value,
        );
        perms.add(updatedPerm);
      }

      _allUsers[userIdx] = User(
        id: _selectedManagementUser!.id,
        username: _selectedManagementUser!.username,
        email: _selectedManagementUser!.email,
        isActive: _selectedManagementUser!.isActive,
        userGroupId: _selectedManagementUser!.userGroupId,
        permissions: perms,
      );
      _selectedManagementUser = _allUsers[userIdx];
    });
  }

  Widget _buildActionFooter(
    String text,
    bool isLoading,
    VoidCallback onPressed,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1E1E1E)
            : Colors.white,
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: isLoading ? null : onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF9800),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      text,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
