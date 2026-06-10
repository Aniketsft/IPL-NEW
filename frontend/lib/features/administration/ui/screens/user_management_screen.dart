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
  bool _isDeletingRole = false;
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

    final List<PermissionNode> _permissionTree = [
      PermissionNode(label: 'Home Screen', moduleId: 'app.home'),
      PermissionNode(label: 'Settings', moduleId: 'settings.general'),
      PermissionNode(label: 'Administration', moduleId: 'administration.user_management'),
      PermissionNode(label: 'Sync Logs', moduleId: 'administration.sync_logs'),
      PermissionNode(label: 'Delivery', moduleId: 'logistics.delivery'),
      PermissionNode(label: 'Manufacturing', moduleId: 'manufacturing.all'),
      PermissionNode(label: 'QR Label', moduleId: 'inventory.by_identifier'),
      PermissionNode(label: 'Printer Settings', moduleId: 'settings.printer'),
      PermissionNode(label: 'Sales Invoice', moduleId: 'logistics.sales_invoice'),
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
    final teal = theme.primaryColor;

    return IndustrialModuleLayout(
      title: 'User Management',
      body: _isLoading
          ? Center(
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
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'MODULE ACCESS',
            style: TextStyle(
              color: isDark ? Colors.white38 : Colors.black38,
              fontWeight: FontWeight.bold,
              fontSize: 11,
              letterSpacing: 1.4,
            ),
          ),
        ),
        ..._permissionTree.map(
          (node) => _buildModuleCard(node, permissions, isDark, onUpdate),
        ),
      ],
    );
  }

  Widget _buildModuleCard(
    PermissionNode node,
    List<ModuleAccess> permissions,
    bool isDark,
    Function(String moduleId, String type, bool value, {List<String>? subModuleIds}) onUpdate,
  ) {
    final access = permissions.firstWhere(
      (p) => p.moduleId == node.moduleId,
      orElse: () => ModuleAccess(moduleId: node.moduleId!),
    );

    final bool isRead = access.canRead;
    final bool isCrud = access.canCreate && access.canRead && access.canUpdate && access.canDelete;

    // Card tint based on access level
    Color cardBg;
    Color borderColor;
    if (isCrud) {
      cardBg = isDark
          ? const Color(0xFF003D3D)
          : const Color(0xFFE0F7F7);
      borderColor = Theme.of(context).primaryColor.withValues(alpha: isDark ? 0.5 : 0.3);
    } else if (isRead) {
      cardBg = isDark
          ? const Color(0xFF1A2A3D)
          : const Color(0xFFE8F0FB);
      borderColor = const Color(0xFF4A90D9).withValues(alpha: isDark ? 0.4 : 0.3);
    } else {
      cardBg = isDark ? const Color(0xFF1E1E24) : const Color(0xFFF5F5FA);
      borderColor = isDark
          ? Colors.white.withValues(alpha: 0.07)
          : Colors.black.withValues(alpha: 0.07);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
        boxShadow: isDark ? null : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Module header row
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _getModuleIconColor(node.label).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getModuleIcon(node.label),
                  color: _getModuleIconColor(node.label),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.label,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isDark ? Colors.white.withValues(alpha: 0.87) : Colors.black87,
                      ),
                    ),
                    Text(
                      _getModuleDescription(node.label),
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  ],
                ),
              ),
              // Access badge
              if (isCrud)
                _accessBadge('FULL', Theme.of(context).primaryColor, isDark)
              else if (isRead)
                _accessBadge('READ', const Color(0xFF4A90D9), isDark)
              else
                _accessBadge('NONE', Colors.grey, isDark),
            ],
          ),
          const SizedBox(height: 14),
          // Toggle row
          Row(
            children: [
              Expanded(
                child: _buildSwitchTile(
                  label: 'Read Only',
                  sublabel: 'View access',
                  value: isRead,
                  activeColor: const Color(0xFF4A90D9),
                  isDark: isDark,
                  onChanged: (v) {
                    onUpdate(node.moduleId!, 'read', v);
                    if (!v) {
                      onUpdate(node.moduleId!, 'create', false);
                      onUpdate(node.moduleId!, 'update', false);
                      onUpdate(node.moduleId!, 'delete', false);
                    }
                  },
                ),
              ),
              Container(
                width: 1,
                height: 40,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: isDark ? Colors.white12 : Colors.black12,
              ),
              Expanded(
                child: _buildSwitchTile(
                  label: 'Full CRUD',
                  sublabel: 'Create, edit, delete',
                  value: isCrud,
                  activeColor: Theme.of(context).primaryColor,
                  isDark: isDark,
                  onChanged: (v) {
                    onUpdate(node.moduleId!, 'create', v);
                    onUpdate(node.moduleId!, 'read', v);
                    onUpdate(node.moduleId!, 'update', v);
                    onUpdate(node.moduleId!, 'delete', v);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required String label,
    required String sublabel,
    required bool value,
    required Color activeColor,
    required bool isDark,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: Colors.white,
          activeTrackColor: activeColor,
          inactiveThumbColor: isDark ? Colors.grey[600] : Colors.grey[400],
          inactiveTrackColor: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.08),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: value
                      ? activeColor
                      : (isDark ? Colors.white54 : Colors.black54),
                ),
              ),
              Text(
                sublabel,
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.white24 : Colors.black26,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _accessBadge(String text, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  IconData _getModuleIcon(String label) {
    switch (label) {
      case 'Home Screen':      return Icons.home_outlined;
      case 'Settings':         return Icons.settings_outlined;
      case 'Administration':   return Icons.admin_panel_settings_outlined;
      case 'Sync Logs':        return Icons.sync_alt;
      case 'Delivery':         return Icons.local_shipping_outlined;
      case 'Manufacturing':    return Icons.precision_manufacturing_outlined;
      case 'QR Label':         return Icons.qr_code_scanner_rounded;
      case 'Printer Settings': return Icons.print_outlined;
      case 'Sales Invoice':    return Icons.receipt_long_rounded;
      default:                 return Icons.folder_outlined;
    }
  }

  Color _getModuleIconColor(String label) {
    switch (label) {
      case 'Home Screen':      return const Color(0xFFFF9800);
      case 'Settings':         return const Color(0xFF9C27B0);
      case 'Administration':   return const Color(0xFFF44336);
      case 'Sync Logs':        return const Color(0xFF009688);
      case 'Delivery':         return const Color(0xFF2196F3);
      case 'Manufacturing':    return Theme.of(context).primaryColor;
      case 'QR Label':         return const Color(0xFF4CAF50);
      case 'Printer Settings': return const Color(0xFF607D8B);
      case 'Sales Invoice':    return const Color(0xFF4A90D9);
      default:                 return Colors.grey;
    }
  }

  String _getModuleDescription(String label) {
    switch (label) {
      case 'Home Screen':      return 'Dashboard & data sync';
      case 'Settings':         return 'App configuration';
      case 'Administration':   return 'User & role management';
      case 'Sync Logs':        return 'Real-time device sync tracking';
      case 'Delivery':         return 'EOD, scanning & manifests';
      case 'Manufacturing':    return 'Sales orders & tracking';
      case 'QR Label':         return 'QR aggregation & printing';
      case 'Printer Settings': return 'Printer configuration';
      case 'Sales Invoice':    return 'Customer invoicing & returns';
      default:                 return '';
    }
  }

  // ---------------------------------------------------------
  // ROLES TAB
  // ---------------------------------------------------------

  Widget _buildRolesTab(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 800;

        // LEFT PANE: Roles List
        final leftPane = Container(
          width: isMobile ? double.infinity : 300,
          decoration: BoxDecoration(
            border: isMobile ? null : Border(right: BorderSide(color: isDark ? Colors.white12 : Colors.black12)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton.icon(
                  onPressed: () => _showCreateRoleDialog(isDark),
                  icon: const Icon(Icons.add, color: Colors.white, size: 20),
                  label: const Text('CREATE ROLE'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    minimumSize: const Size(200, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: _localRoles.length,
                  itemBuilder: (context, index) {
                    final role = _localRoles[index];
                    final isSelected = _selectedRole?.id == role.id;
                    return ListTile(
                      title: Text(
                        role.name,
                        style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                      ),
                      selected: isSelected,
                      selectedTileColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                      onTap: () => setState(() => _selectedRole = role),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            tooltip: 'Delete role',
                            color: Colors.red.shade400,
                            onPressed: _isDeletingRole
                                ? null
                                : () => _confirmDeleteRole(role),
                          ),
                          const Icon(Icons.chevron_right, size: 16),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );

        // RIGHT PANE: Permissions Editor
        final rightPane = Column(
          children: [
            if (_selectedRole != null)
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Editing: ${_selectedRole!.name}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildPermissionMatrixLayout(
                        permissions: _selectedRole!.permissions,
                        isDark: isDark,
                        onUpdate: _updateRolePermissions,
                      ),
                    ],
                  ),
                ),
              )
            else
              const Expanded(
                child: Center(
                  child: Text(
                    'Select a role to manage permissions',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            if (_selectedRole != null)
              _buildActionFooter('SAVE CHANGES', _isSavingRole, () async {
                setState(() => _isSavingRole = true);
                try {
                  await _repository.updateRole(_selectedRole!);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Role permissions saved successfully!')),
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

        if (isMobile) {
          if (_selectedRole == null) {
            return leftPane;
          } else {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _selectedRole = null),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back to Roles'),
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).primaryColor,
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(child: rightPane),
              ],
            );
          }
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            leftPane,
            Expanded(child: rightPane),
          ],
        );
      },
    );
  }

  Future<void> _confirmDeleteRole(UserRole role) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Role'),
        content: Text('Delete "${role.name}"? This cannot be undone and will remove the role from all users assigned to it.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeletingRole = true);
    try {
      await _repository.deleteRole(role.id);
      if (mounted) {
        setState(() {
          _localRoles.removeWhere((r) => r.id == role.id);
          if (_selectedRole?.id == role.id) _selectedRole = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Role "${role.name}" deleted.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete role: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDeletingRole = false);
    }
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
    List<ModuleAccess> newRolePermissions = [];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog(
              backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              insetPadding: const EdgeInsets.all(20),
              child: SizedBox(
                width: 800,
                height: MediaQuery.of(context).size.height * 0.8,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Create New Role',
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextFormField(
                              controller: nameController,
                              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                              decoration: const InputDecoration(
                                labelText: 'Role Name',
                                hintText: 'e.g. IT Admin',
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: descController,
                              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                              decoration: const InputDecoration(
                                labelText: 'Description',
                                hintText: 'e.g. IT administrators with full settings access',
                              ),
                            ),
                            const SizedBox(height: 32),
                            _buildPermissionMatrixLayout(
                              permissions: newRolePermissions,
                              isDark: isDark,
                              onUpdate: (moduleId, type, value, {subModuleIds}) {
                                setStateDialog(() {
                                  newRolePermissions = _updatePermissionsList(
                                    currentPermissions: newRolePermissions,
                                    moduleId: moduleId,
                                    type: type,
                                    value: value,
                                    subModuleIds: subModuleIds,
                                  );
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('CANCEL'),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton(
                            onPressed: () async {
                              final name = nameController.text.trim();
                              if (name.isEmpty) return;

                              Navigator.pop(context);
                              final messenger = ScaffoldMessenger.of(this.context);
                              setState(() => _isLoading = true);
                              try {
                                final newRole = UserRole(
                                  id: '', 
                                  name: name,
                                  permissions: newRolePermissions,
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
                              backgroundColor: Theme.of(context).primaryColor,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(120, 48),
                            ),
                            child: const Text('CREATE ROLE'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
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
              color: isDark ? Theme.of(context).cardColor : Colors.black.withValues(alpha: 0.05),
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
/*
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? Theme.of(context).cardColor : Colors.black.withValues(alpha: 0.05),
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
                  activeThumbColor: Theme.of(context).primaryColor,
                  activeTrackColor: Theme.of(context).primaryColor.withValues(alpha: 0.5),
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
          */
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
        TextFormField(
          controller: controller,
          obscureText: isPassword,
          style: TextStyle(
            fontSize: 15,
            color: isDark ? Colors.white : Colors.black87,
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
                  /*
                  const SizedBox(height: 24),
                  _buildPermissionMatrixLayout(
                    permissions: _selectedManagementUser!.permissions,
                    isDark: isDark,
                    onUpdate: _updateExistingUserPermissions,
                  ),
                  */
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
            /*
            await _repository.updateUserPermissions(
              _selectedManagementUser!.id,
              _selectedManagementUser!.permissions,
            );
            */
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('User details updated!')),
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
        color: isDark ? Theme.of(context).cardColor : Colors.black.withValues(alpha: 0.05),
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
        color: isDark ? Theme.of(context).cardColor : Colors.black.withValues(alpha: 0.05),
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
                backgroundColor: Theme.of(context).primaryColor,
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
