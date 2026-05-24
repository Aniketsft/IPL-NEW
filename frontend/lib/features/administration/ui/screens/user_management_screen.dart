import 'package:flutter/material.dart';
import '../../../../core/widgets/industrial_module_layout.dart';
import '../../data/models/user_management.dart';
import '../../data/repositories/user_management_repository.dart';

class PermissionNode {
  final String label;
  final String? moduleId;
  final List<PermissionNode> children;

  PermissionNode({
    required this.label,
    this.moduleId,
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
  final UserManagementRepository _repository = UserManagementRepository();

  // Local state for editing roles
  List<UserRole> _localRoles = [];
  bool _isLoading = true;

  bool _isSavingRole = false;
  bool _isCreatingUser = false;
  bool _useCustomPermissions = false;
  List<ModuleAccess> _selectedUserPermissions = [];

  // Selected state for User Creation
  UserRole? _selectedCreationRole;

  // State for Managing Existing Users
  List<User> _allUsers = [];
  User? _selectedManagementUser;
  bool _isSavingUserPermissions = false;

  // Controllers for User Creation
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // Define the permission tree structure based on Home Screen modules
  final List<PermissionNode> _permissionTree = [
    PermissionNode(
      label: 'Logistics',
      children: [
        PermissionNode(label: 'Receipt', moduleId: 'logistics.receipt'),
        PermissionNode(label: 'Delivery', moduleId: 'logistics.delivery'),
        PermissionNode(label: 'Transfer', moduleId: 'logistics.transfer'),
      ],
    ),
    PermissionNode(
      label: 'Manufacturing',
      children: [
        PermissionNode(label: 'All Production', moduleId: 'manufacturing.all'),
      ],
    ),
    PermissionNode(
      label: 'Inventory',
      children: [
        PermissionNode(label: 'Stock Control', moduleId: 'inventory.stock_control'),
        PermissionNode(label: 'Picking', moduleId: 'inventory.picking'),
        PermissionNode(label: 'By Identifier', moduleId: 'inventory.by_identifier'),
      ],
    ),
    PermissionNode(
      label: 'Administration',
      children: [
        PermissionNode(label: 'User Management', moduleId: 'administration.user_management'),
      ],
    ),
    PermissionNode(
      label: 'Settings',
      children: [
        PermissionNode(label: 'General', moduleId: 'settings.general'),
        PermissionNode(label: 'Printer Settings', moduleId: 'settings.printer'),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final roles = await _repository.getRoles();
      final users = await _repository.getUsers();
      if (mounted) {
        setState(() {
          _localRoles = roles;
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tabColor = isDark ? const Color(0xFF1E1E1E) : theme.cardColor;
    const teal = Color(0xFF008080);

    return IndustrialModuleLayout(
      title: 'User Management',
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: teal),
            )
          : Column(
              children: [
                Container(
                  color: tabColor,
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: teal,
                    labelColor: teal,
                    unselectedLabelColor: isDark
                        ? Colors.white54
                        : Colors.black54,
                    tabs: const [
                      Tab(text: 'ROLES'),
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
  // PERMISSION TREE / CHECKBOX CALCULATION LOGIC
  // ---------------------------------------------------------

  bool? _getSubModuleState(List<ModuleAccess> permissions, String moduleId) {
    final access = permissions.firstWhere(
      (p) => p.moduleId == moduleId,
      orElse: () => ModuleAccess(moduleId: moduleId),
    );
    final list = [access.canCreate, access.canRead, access.canUpdate, access.canDelete];
    final checkedCount = list.where((v) => v).length;
    if (checkedCount == 4) return true;
    if (checkedCount == 0) return false;
    return null; // Indeterminate
  }

  bool? _getCategoryState(List<ModuleAccess> permissions, PermissionNode categoryNode) {
    int totalCount = categoryNode.children.length * 4;
    int checkedCount = 0;
    for (var child in categoryNode.children) {
      final access = permissions.firstWhere(
        (p) => p.moduleId == child.moduleId,
        orElse: () => ModuleAccess(moduleId: child.moduleId!),
      );
      if (access.canCreate) checkedCount++;
      if (access.canRead) checkedCount++;
      if (access.canUpdate) checkedCount++;
      if (access.canDelete) checkedCount++;
    }
    if (checkedCount == totalCount) return true;
    if (checkedCount == 0) return false;
    return null; // Indeterminate
  }

  List<ModuleAccess> _updatePermissionsList({
    required List<ModuleAccess> currentPermissions,
    required String moduleId,
    required String type, // 'create', 'read', 'update', 'delete', 'all_sub', 'all_cat'
    required bool value,
    List<String>? subModuleIds,
  }) {
    final List<ModuleAccess> updated = List.from(currentPermissions);

    void setModulePerms(String mId, bool val, {bool c = true, bool r = true, bool u = true, bool d = true}) {
      final idx = updated.indexWhere((p) => p.moduleId == mId);
      if (idx != -1) {
        final current = updated[idx];
        updated[idx] = current.copyWith(
          canCreate: c ? val : current.canCreate,
          canRead: r ? val : current.canRead,
          canUpdate: u ? val : current.canUpdate,
          canDelete: d ? val : current.canDelete,
        );
      } else {
        updated.add(ModuleAccess(
          moduleId: mId,
          canCreate: c ? val : false,
          canRead: r ? val : false,
          canUpdate: u ? val : false,
          canDelete: d ? val : false,
        ));
      }
    }

    if (type == 'all_cat' && subModuleIds != null) {
      for (var mId in subModuleIds) {
        setModulePerms(mId, value);
      }
    } else if (type == 'all_sub') {
      setModulePerms(moduleId, value);
    } else {
      final idx = updated.indexWhere((p) => p.moduleId == moduleId);
      ModuleAccess updatedAccess;
      if (idx != -1) {
        updatedAccess = _getUpdatedPerm(updated[idx], type, value);
        updated[idx] = updatedAccess;
      } else {
        updatedAccess = _getUpdatedPerm(ModuleAccess(moduleId: moduleId), type, value);
        updated.add(updatedAccess);
      }
    }
    return updated;
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

  // ---------------------------------------------------------
  // PERMISSION SELECTION UI (REUSABLE)
  // ---------------------------------------------------------

  Widget _buildPermissionMatrixLayout({
    required List<ModuleAccess> permissions,
    required bool isDark,
    required Function(String moduleId, String type, bool value, {List<String>? subModuleIds}) onUpdate,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Expanded(
                child: Text(
                  'MODULES & SUBMODULES',
                  style: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              _headerLabel('MASTER'),
              _headerLabel('C'),
              _headerLabel('R'),
              _headerLabel('U'),
              _headerLabel('D'),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ..._permissionTree.map(
          (categoryNode) => _buildCategoryCard(
            categoryNode,
            permissions,
            isDark,
            onUpdate,
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryCard(
    PermissionNode categoryNode,
    List<ModuleAccess> permissions,
    bool isDark,
    Function(String moduleId, String type, bool value, {List<String>? subModuleIds}) onUpdate,
  ) {
    final catState = _getCategoryState(permissions, categoryNode);
    final subModuleIds = categoryNode.children.map((c) => c.moduleId!).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24) : const Color(0xFFF5F5FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category Header Row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
              child: Row(
                children: [
                  Icon(
                    _getCategoryIcon(categoryNode.label),
                    color: const Color(0xFF00BCD4),
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      categoryNode.label.toUpperCase(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        letterSpacing: 1.0,
                        color: Color(0xFF008080),
                      ),
                    ),
                  ),
                  // Tristate Checkbox for the entire category
                  SizedBox(
                    width: 40,
                    child: Center(
                      child: Checkbox(
                        tristate: true,
                        value: catState,
                        activeColor: const Color(0xFF008080),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        onChanged: (v) {
                          final targetVal = v ?? true;
                          onUpdate('', 'all_cat', targetVal, subModuleIds: subModuleIds);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 160), // Align with CRUD columns
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1),
            // Sub-modules list
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: categoryNode.children.map((childNode) {
                  final subState = _getSubModuleState(permissions, childNode.moduleId!);
                  final access = permissions.firstWhere(
                    (p) => p.moduleId == childNode.moduleId,
                    orElse: () => ModuleAccess(moduleId: childNode.moduleId!),
                  );

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: Text(
                              childNode.label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: isDark ? Colors.white.withValues(alpha: 0.9) : Colors.black87,
                              ),
                            ),
                          ),
                        ),
                        // Master Toggle for Sub-module
                        SizedBox(
                          width: 40,
                          child: Center(
                            child: Checkbox(
                              tristate: true,
                              value: subState,
                              activeColor: const Color(0xFF008080),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              onChanged: (v) {
                                final targetVal = v ?? true;
                                onUpdate(childNode.moduleId!, 'all_sub', targetVal);
                              },
                            ),
                          ),
                        ),
                        // Individual CRUD Checkboxes
                        _matrixToggle(
                          access.canCreate,
                          (v) => onUpdate(childNode.moduleId!, 'create', v),
                        ),
                        _matrixToggle(
                          access.canRead,
                          (v) => onUpdate(childNode.moduleId!, 'read', v),
                        ),
                        _matrixToggle(
                          access.canUpdate,
                          (v) => onUpdate(childNode.moduleId!, 'update', v),
                        ),
                        _matrixToggle(
                          access.canDelete,
                          (v) => onUpdate(childNode.moduleId!, 'delete', v),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getCategoryIcon(String label) {
    switch (label.toLowerCase()) {
      case 'logistics':
        return Icons.local_shipping_outlined;
      case 'manufacturing':
        return Icons.precision_manufacturing_outlined;
      case 'inventory':
        return Icons.inventory_2_outlined;
      case 'administration':
        return Icons.admin_panel_settings_outlined;
      case 'settings':
        return Icons.settings_outlined;
      default:
        return Icons.folder_outlined;
    }
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
          fontSize: 10,
        ),
      ),
    );
  }

  Widget _matrixToggle(bool value, Function(bool) onChanged) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: 40,
      child: Center(
        child: Checkbox(
          value: value,
          onChanged: (v) => onChanged(v ?? false),
          activeColor: const Color(0xFF008080),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          side: BorderSide(color: isDark ? Colors.grey : Colors.black26),
        ),
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
          child: Row(
            children: [
              Expanded(child: _buildRoleSelector(isDark)),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => _showCreateRoleDialog(isDark),
                icon: const Icon(Icons.add, color: Colors.white, size: 20),
                label: const Text('CREATE ROLE'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF008080),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_selectedRole != null)
          Expanded(child: _buildPermissionMatrix(isDark))
        else
          const Expanded(
            child: Center(
              child: Text(
                'Select a role or create one to manage permissions',
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
        color: isDark ? const Color(0xFF38383B) : Colors.black.withValues(alpha: 0.05),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          _buildPermissionMatrixLayout(
            permissions: _selectedRole!.permissions,
            isDark: isDark,
            onUpdate: _updateRolePermissions,
          ),
        ],
      ),
    );
  }

  void _updateRolePermissions(String moduleId, String type, bool value, {List<String>? subModuleIds}) {
    if (_selectedRole == null) return;
    setState(() {
      final roleIdx = _localRoles.indexOf(_selectedRole!);
      final updatedPerms = _updatePermissionsList(
        currentPermissions: _selectedRole!.permissions,
        moduleId: moduleId,
        type: type,
        value: value,
        subModuleIds: subModuleIds,
      );
      _localRoles[roleIdx] = UserRole(
        id: _selectedRole!.id,
        name: _selectedRole!.name,
        permissions: updatedPerms,
      );
      _selectedRole = _localRoles[roleIdx];
    });
  }

  void _showCreateRoleDialog(bool isDark) {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Create New Role',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: const InputDecoration(
                  labelText: 'Role Name',
                  hintText: 'e.g. IT Admin',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'e.g. IT administrators with full settings access',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;

                Navigator.pop(context);
                final messenger = ScaffoldMessenger.of(context);
                setState(() => _isLoading = true);
                try {
                  final newRole = UserRole(
                    id: '', // Backend creates Guid
                    name: name,
                    permissions: const [],
                  );
                  await _repository.createRole(newRole);
                  await _loadData();
                  if (mounted) {
                    final created = _localRoles.firstWhere(
                      (r) => r.name.toLowerCase() == name.toLowerCase(),
                      orElse: () => _localRoles.first,
                    );
                    setState(() {
                      _selectedRole = created;
                    });
                    messenger.showSnackBar(
                      SnackBar(content: Text('Role "$name" created successfully!')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Failed to create role: $e')),
                    );
                  }
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF008080),
                foregroundColor: Colors.white,
              ),
              child: const Text('CREATE'),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------
  // USERS TAB (CREATE USER)
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

          const Text(
            'Assign Role',
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
              color: isDark ? const Color(0xFF38383B) : Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<UserRole>(
                value: _selectedCreationRole,
                hint: const Text('Select Role'),
                isExpanded: true,
                dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                items: _localRoles.map((r) {
                  return DropdownMenuItem(value: r, child: Text(r.name));
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedCreationRole = val;
                    if (_useCustomPermissions && val != null) {
                      _selectedUserPermissions = List.from(val.permissions);
                    }
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF38383B) : Colors.black.withValues(alpha: 0.05),
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
                      if (val && _selectedCreationRole != null) {
                        _selectedUserPermissions = List.from(_selectedCreationRole!.permissions);
                      }
                    });
                  },
                  activeThumbColor: const Color(0xFF008080),
                  activeTrackColor: const Color(0xFF008080).withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
          if (_useCustomPermissions) ...[
            const SizedBox(height: 24),
            _buildPermissionMatrixLayout(
              permissions: _selectedUserPermissions,
              isDark: isDark,
              onUpdate: _updateCreationUserPermissions,
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
            color: isDark ? const Color(0xFF38383B) : Colors.black.withValues(alpha: 0.05),
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

  void _updateCreationUserPermissions(String moduleId, String type, bool value, {List<String>? subModuleIds}) {
    setState(() {
      _selectedUserPermissions = _updatePermissionsList(
        currentPermissions: _selectedUserPermissions,
        moduleId: moduleId,
        type: type,
        value: value,
        subModuleIds: subModuleIds,
      );
    });
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
        roleId: _selectedCreationRole?.id,
        permissions: _useCustomPermissions ? _selectedUserPermissions : [],
      );

      if (mounted) {
        _fullNameController.clear();
        _usernameController.clear();
        _emailController.clear();
        _passwordController.clear();
        setState(() {
          _selectedCreationRole = null;
          _selectedUserPermissions = [];
          _useCustomPermissions = false;
        });
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
  // EXISTING USERS TAB (MANAGE USERS)
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  _buildUserRoleSelector(isDark),
                  const SizedBox(height: 24),
                  _buildPermissionMatrixLayout(
                    permissions: _selectedManagementUser!.permissions,
                    isDark: isDark,
                    onUpdate: _updateExistingUserPermissions,
                  ),
                ],
              ),
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
            // Update User details (like roleId)
            await _repository.updateUser(_selectedManagementUser!);
            // Update User permissions
            await _repository.updateUserPermissions(
              _selectedManagementUser!.id,
              _selectedManagementUser!.permissions,
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('User details and permissions updated!')),
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
        color: isDark ? const Color(0xFF38383B) : Colors.black.withValues(alpha: 0.05),
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

  Widget _buildUserRoleSelector(bool isDark) {
    if (_selectedManagementUser == null) return const SizedBox.shrink();
    
    final currentRoleId = _selectedManagementUser!.roleId;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF38383B) : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<UserRole>(
          value: _localRoles.any((r) => r.id == currentRoleId) ? _localRoles.firstWhere((r) => r.id == currentRoleId) : null,
          hint: const Text('Select Standard Role'),
          isExpanded: true,
          dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          items: _localRoles.map((r) {
            return DropdownMenuItem(value: r, child: Text(r.name));
          }).toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() {
                final userIdx = _allUsers.indexOf(_selectedManagementUser!);
                _allUsers[userIdx] = User(
                  id: _selectedManagementUser!.id,
                  username: _selectedManagementUser!.username,
                  email: _selectedManagementUser!.email,
                  isActive: _selectedManagementUser!.isActive,
                  roleId: val.id,
                  permissions: _selectedManagementUser!.permissions,
                );
                _selectedManagementUser = _allUsers[userIdx];
              });
            }
          },
        ),
      ),
    );
  }

  void _updateExistingUserPermissions(String moduleId, String type, bool value, {List<String>? subModuleIds}) {
    if (_selectedManagementUser == null) return;

    setState(() {
      final userIdx = _allUsers.indexOf(_selectedManagementUser!);
      final updatedPerms = _updatePermissionsList(
        currentPermissions: _selectedManagementUser!.permissions,
        moduleId: moduleId,
        type: type,
        value: value,
        subModuleIds: subModuleIds,
      );

      _allUsers[userIdx] = User(
        id: _selectedManagementUser!.id,
        username: _selectedManagementUser!.username,
        email: _selectedManagementUser!.email,
        isActive: _selectedManagementUser!.isActive,
        roleId: _selectedManagementUser!.roleId,
        permissions: updatedPerms,
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
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: isLoading ? null : onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF008080),
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
