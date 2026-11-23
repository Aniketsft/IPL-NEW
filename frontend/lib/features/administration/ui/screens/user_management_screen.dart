import 'package:flutter/material.dart';
import '../../../../core/widgets/industrial_module_layout.dart';
import '../../data/models/user_management.dart';
import '../../data/repositories/user_management_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../../../features/auth/presentation/bloc/auth_state.dart';
import '../../../../core/network_service.dart';
import '../../../../core/secure_storage_service.dart';

class PermissionNode {
  final String label;
  final String? moduleId;
  final String category; // 'sales', 'manufacturing', 'system'
  final String description;
  final IconData icon;
  final Color? iconColor;
  final List<PermissionNode> children;

  const PermissionNode({
    required this.label,
    this.moduleId,
    this.category = 'sales',
    this.description = '',
    this.icon = Icons.folder_outlined,
    this.iconColor,
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
  late final UserManagementRepository _repository;

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
  String? _selectedCreationSite;

  // State for Managing Existing Users
  List<User> _allUsers = [];
  User? _selectedManagementUser;
  bool _isSavingUserPermissions = false;

  // Controllers for User Creation
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();


  static const List<PermissionNode> _salesPermissionNodes = [
    PermissionNode(
      label: 'Sales Invoicing',
      moduleId: 'logistics.sales_invoice',
      category: 'sales',
      description: 'Standard sales catalog, cart ordering & invoice posting',
      icon: Icons.point_of_sale_rounded,
      iconColor: Color(0xFF4A90D9),
    ),
    PermissionNode(
      label: 'Invoice Reversal Credit Note',
      moduleId: 'logistics.sales.credit_reversal',
      category: 'sales',
      description: 'Select invoice to reverse settlement and restore stock',
      icon: Icons.undo_rounded,
      iconColor: Colors.redAccent,
    ),
    PermissionNode(
      label: 'Open / Standalone Credit Note',
      moduleId: 'logistics.sales.credit_standalone',
      category: 'sales',
      description: 'Create standalone credit note with direct item selection',
      icon: Icons.description_rounded,
      iconColor: Colors.blueAccent,
    ),
    PermissionNode(
      label: 'Cash Refund Credit Note',
      moduleId: 'logistics.sales.credit_refund',
      category: 'sales',
      description: 'Process amount-only cash refunds against customer balance',
      icon: Icons.payments_rounded,
      iconColor: Colors.green,
    ),
    PermissionNode(
      label: 'Customer Return',
      moduleId: 'logistics.sales.customer_return',
      category: 'sales',
      description: 'Process inventory returns and customer refund slips',
      icon: Icons.assignment_return_rounded,
      iconColor: Colors.teal,
    ),
    PermissionNode(
      label: 'Receipt (Cash Collection)',
      moduleId: 'logistics.sales.cash_collection',
      category: 'sales',
      description: 'Collect payments & allocate against open customer invoices',
      icon: Icons.receipt_long_rounded,
      iconColor: Colors.amber,
    ),
    PermissionNode(
      label: 'Sales Orders',
      moduleId: 'logistics.sales.sales_order',
      category: 'sales',
      description: 'Create & view pre-sales customer orders',
      icon: Icons.list_alt_rounded,
      iconColor: Colors.indigoAccent,
    ),
    PermissionNode(
      label: 'Price Override',
      moduleId: 'logistics.sales.price_override',
      category: 'sales',
      description: 'Allow manual base price editing on products in cart',
      icon: Icons.edit_note_rounded,
      iconColor: Colors.deepOrange,
    ),
    PermissionNode(
      label: 'Discount Override',
      moduleId: 'logistics.sales.discount_override',
      category: 'sales',
      description: 'Allow applying custom line and document discounts',
      icon: Icons.percent_rounded,
      iconColor: Colors.purple,
    ),
    PermissionNode(
      label: 'Discount Limit Config',
      moduleId: 'logistics.sales.discount_limit',
      category: 'sales',
      description: 'Configure global maximum sales discount percentage',
      icon: Icons.tune_rounded,
      iconColor: Colors.deepPurple,
    ),
    PermissionNode(
      label: 'Sales Rep Selection',
      moduleId: 'logistics.sales.rep_selection',
      category: 'sales',
      description: 'Select and change active sales representative on transactions',
      icon: Icons.badge_rounded,
      iconColor: Colors.cyan,
    ),
    PermissionNode(
      label: 'Tender: Cash',
      moduleId: 'logistics.sales.tender_cash',
      category: 'sales',
      description: 'Allow accepting Cash payments on mobile terminal',
      icon: Icons.payments_outlined,
      iconColor: Colors.green,
    ),
    PermissionNode(
      label: 'Tender: Credit',
      moduleId: 'logistics.sales.tender_credit',
      category: 'sales',
      description: 'Allow charging sales to Customer Credit line',
      icon: Icons.account_balance_wallet_outlined,
      iconColor: Colors.blue,
    ),
    PermissionNode(
      label: 'Tender: Cheque',
      moduleId: 'logistics.sales.tender_cheque',
      category: 'sales',
      description: 'Allow accepting Cheques with drawer bank details',
      icon: Icons.receipt_outlined,
      iconColor: Colors.brown,
    ),
    PermissionNode(
      label: 'Tender: Digital (Juice / Blink)',
      moduleId: 'logistics.sales.tender_digital',
      category: 'sales',
      description: 'Allow QR code and mobile app tenders (Juice, Blink, Myt Money)',
      icon: Icons.qr_code_2_rounded,
      iconColor: Colors.orange,
    ),
    PermissionNode(
      label: 'Sales Reports & EOD',
      moduleId: 'logistics.reports',
      category: 'sales',
      description: 'Daily sales summaries, driver settlement & EOD reports',
      icon: Icons.analytics_rounded,
      iconColor: Color(0xFF00B4D8),
    ),
    PermissionNode(
      label: 'Reports: Previous Date',
      moduleId: 'logistics.reports.previous_date',
      category: 'sales',
      description: 'Allow selecting past dates for EOD, Invoice Summary & Stock reports',
      icon: Icons.date_range_rounded,
      iconColor: Color(0xFF0096C7),
    ),
    PermissionNode(
      label: 'Supervisor Override OTP',
      moduleId: 'logistics.otp_generation',
      category: 'sales',
      description: 'Generate supervisor approval PINs for limits and holds',
      icon: Icons.pin_outlined,
      iconColor: Color(0xFFFF9F1C),
    ),
  ];

  static const List<PermissionNode> _manufacturingPermissionNodes = [
    PermissionNode(
      label: 'Manufacturing Execution',
      moduleId: 'manufacturing.all',
      category: 'manufacturing',
      description: 'Sales orders, work order tracking & production reporting',
      icon: Icons.precision_manufacturing_rounded,
      iconColor: Colors.amber,
    ),
    PermissionNode(
      label: 'Delivery & Manifests',
      moduleId: 'logistics.delivery',
      category: 'manufacturing',
      description: 'Lorry loading, route manifests & proof of delivery',
      icon: Icons.local_shipping_outlined,
      iconColor: Color(0xFF2196F3),
    ),
    PermissionNode(
      label: 'QR Label Printing',
      moduleId: 'inventory.by_identifier',
      category: 'manufacturing',
      description: 'QR aggregation, item identification & label printing',
      icon: Icons.qr_code_scanner_rounded,
      iconColor: Color(0xFF4CAF50),
    ),
    PermissionNode(
      label: 'Printer Settings',
      moduleId: 'settings.printer',
      category: 'manufacturing',
      description: 'Configure thermal Bluetooth & network printers',
      icon: Icons.print_outlined,
      iconColor: Color(0xFF607D8B),
    ),
    PermissionNode(
      label: 'Device Management',
      moduleId: 'administration.devices',
      category: 'manufacturing',
      description: 'Bind and authorize handheld devices by MAC address',
      icon: Icons.devices_other_rounded,
      iconColor: Color(0xFF00897B),
    ),
  ];

  static const List<PermissionNode> _systemPermissionNodes = [
    PermissionNode(
      label: 'Home Dashboard & Sync',
      moduleId: 'app.home',
      category: 'system',
      description: 'Dashboard access and offline SQLite data sync',
      icon: Icons.home_outlined,
      iconColor: Color(0xFFFF9800),
    ),
    PermissionNode(
      label: 'General Settings',
      moduleId: 'settings.general',
      category: 'system',
      description: 'App configuration & network endpoints',
      icon: Icons.settings_outlined,
      iconColor: Color(0xFF9C27B0),
    ),
    PermissionNode(
      label: 'User Administration',
      moduleId: 'administration.user_management',
      category: 'system',
      description: 'Create users, assign roles and modify permissions',
      icon: Icons.admin_panel_settings_outlined,
      iconColor: Color(0xFFF44336),
    ),
    PermissionNode(
      label: 'Sync Logs',
      moduleId: 'administration.sync_logs',
      category: 'system',
      description: 'Real-time sync audit log inspection',
      icon: Icons.sync_alt,
      iconColor: Color(0xFF009688),
    ),
  ];

  List<PermissionNode> get _permissionTree => [
    ..._salesPermissionNodes,
    ..._manufacturingPermissionNodes,
    ..._systemPermissionNodes,
  ];

  List<Site> _availableSites = [];
  String? _currentLoggedInUsername;
  bool _isInit = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      _repository = UserManagementRepository(dio: context.read<NetworkService>().dio);
      _loadData();
      _isInit = true;
    }
  }

  Future<void> _loadData() async {
    try {
      final roles = await _repository.getRoles();
      final users = await _repository.getUsers();
      final sites = await _repository.getSites();
      final currentUsername = await SecureStorageService().getUsername();
      if (mounted) {
        setState(() {
          _localRoles = roles;
          _allUsers = users;
          _availableSites = sites;
          _currentLoggedInUsername = currentUsername;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading data: $e')));
        setState(() {
          _isLoading = false;
        });
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
  // PERMISSION SELECTION UI (SEGREGATED: MOBILE SALES & MANUFACTURING)
  // ---------------------------------------------------------

  Widget _buildPermissionMatrixLayout({
    required List<ModuleAccess> permissions,
    required bool isDark,
    required Function(String moduleId, String type, bool value, {List<String>? subModuleIds}) onUpdate,
  }) {
    return _SegregatedPermissionMatrix(
      permissions: permissions,
      isDark: isDark,
      onUpdate: onUpdate,
    );
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
    String? selectedSite = 'ALL';
    List<ModuleAccess> newRolePermissions = [];

    final authState = context.read<AuthBloc>().state;
    final canSetSite = authState is Authenticated &&
        authState.permissions.contains('administration.user_management.set_site');
    final currentUserSite = authState is Authenticated ? authState.siteCode : 'ALL';
    if (!canSetSite) {
      selectedSite = currentUserSite;
    }

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
                            if (canSetSite) ...[
                              const SizedBox(height: 16),
                              DropdownButtonFormField<String>(
                                value: selectedSite,
                                isExpanded: true,
                                decoration: const InputDecoration(labelText: 'Site Code'),
                                items: _availableSites.map((site) => DropdownMenuItem(value: site.siteCode, child: Text('${site.siteCode} - ${site.siteName}', overflow: TextOverflow.ellipsis))).toList()
                                  ..insert(0, const DropdownMenuItem(value: 'ALL', child: Text('ALL - Global Admin', overflow: TextOverflow.ellipsis))),
                                onChanged: (val) {
                                  setStateDialog(() {
                                    selectedSite = val;
                                  });
                                },
                              ),
                            ],
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
                                  description: descController.text.trim(),
                                  permissions: newRolePermissions,
                                  siteCode: selectedSite ?? 'ALL',
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
                  return DropdownMenuItem(value: r, child: Text(r.name, overflow: TextOverflow.ellipsis));
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
          
          Builder(builder: (context) {
            final authState = context.read<AuthBloc>().state;
            final canSetSite = authState is Authenticated &&
                authState.permissions.contains('administration.user_management.set_site');
            final currentUserSite = authState is Authenticated ? authState.siteCode : 'ALL';
            
            final displaySite = canSetSite ? (_selectedCreationSite ?? 'ALL') : currentUserSite;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Assign Site Code',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (!canSetSite) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Locked to $currentUserSite',
                          style: TextStyle(
                            color: Colors.amber.shade400,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: isDark ? Theme.of(context).cardColor : Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: displaySite,
                      hint: const Text('Select Site'),
                      isExpanded: true,
                      dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      items: _availableSites.map((site) {
                        return DropdownMenuItem(value: site.siteCode, child: Text('${site.siteCode} - ${site.siteName}', overflow: TextOverflow.ellipsis));
                      }).toList()
                        ..insert(0, const DropdownMenuItem(value: 'ALL', child: Text('ALL - Global Admin', overflow: TextOverflow.ellipsis))),
                      onChanged: canSetSite ? (val) {
                        setState(() {
                          _selectedCreationSite = val;
                        });
                      } : null, // Disabled for non-user-admins
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            );
          }),
          
          const SizedBox(height: 32),
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
      final authState = context.read<AuthBloc>().state;
      final canSetSite = authState is Authenticated &&
          authState.permissions.contains('administration.user_management.set_site');
      final currentUserSite = authState is Authenticated ? authState.siteCode : 'ALL';
      final finalSite = canSetSite ? (_selectedCreationSite ?? 'ALL') : currentUserSite;

      // Note: The backend UsersController POST doesn't directly take siteCode currently (it assumes what we send in the payload).
      // Wait, in user_management_repository.dart we pass siteCode!
      // But we need to make sure we pass it down to `createUser`. Let's update `createUser` signature to accept `siteCode`.
      // I will update that call.

      await _repository.createUser(
        fullName: _fullNameController.text,
        username: _usernameController.text,
        email: _emailController.text,
        password: _passwordController.text,
        roleId: _selectedCreationRole?.id,
        permissions: _useCustomPermissions ? _selectedUserPermissions : [],
        siteCode: finalSite == 'ALL' ? null : finalSite,
      );

      if (mounted) {
        _fullNameController.clear();
        _usernameController.clear();
        _emailController.clear();
        _passwordController.clear();
        setState(() {
          _selectedCreationRole = null;
          _selectedCreationSite = null;
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
          Builder(
            builder: (context) {
              final authState = context.read<AuthBloc>().state;
              final canSetSite = authState is Authenticated &&
                  authState.permissions.contains('administration.user_management.set_site');
              final isSelectedAdmin = _selectedManagementUser!.username.toLowerCase() == 'admin' ||
                  _localRoles.any((r) =>
                      r.id == _selectedManagementUser!.roleId &&
                      (r.name.toLowerCase() == 'admin' || r.name.toLowerCase() == 'superadmin'));
              final bool isLocked = isSelectedAdmin && !canSetSite;

              return Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isLocked) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.withOpacity(0.5)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.shield_rounded, color: Colors.amber, size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Only the primary User Administrator can modify permissions for administrative accounts.',
                                  style: TextStyle(
                                    color: Colors.amber.shade200,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const Text(
                        'ASSIGNED ROLE',
                        style: TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 10),
                      AbsorbPointer(
                        absorbing: isLocked,
                        child: Opacity(
                          opacity: isLocked ? 0.6 : 1.0,
                          child: _buildUserRoleSelector(isDark),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Text(
                            'ASSIGNED SITE CODE',
                            style: TextStyle(
                              color: Colors.grey,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          if (!canSetSite) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amber.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Locked (Admin only)',
                                style: TextStyle(
                                  color: Colors.amber.shade400,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      AbsorbPointer(
                        absorbing: isLocked || !canSetSite,
                        child: Opacity(
                          opacity: (isLocked || !canSetSite) ? 0.6 : 1.0,
                          child: _buildUserSiteSelector(isDark, canSetSite),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'PERMISSIONS OVERRIDE',
                        style: TextStyle(
                          color: isDark ? Colors.white38 : Colors.black38,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      AbsorbPointer(
                        absorbing: isLocked,
                        child: Opacity(
                          opacity: isLocked ? 0.6 : 1.0,
                          child: _buildPermissionMatrixLayout(
                            permissions: _selectedManagementUser!.permissions,
                            isDark: isDark,
                            onUpdate: _updateExistingUserPermissions,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
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
        Builder(
          builder: (context) {
            final authState = context.read<AuthBloc>().state;
            final canSetSite = authState is Authenticated &&
                authState.permissions.contains('administration.user_management.set_site');
            final isSelectedAdmin = _selectedManagementUser != null &&
                (_selectedManagementUser!.username.toLowerCase() == 'admin' ||
                    _localRoles.any((r) =>
                        r.id == _selectedManagementUser!.roleId &&
                        (r.name.toLowerCase() == 'admin' || r.name.toLowerCase() == 'superadmin')));
            final bool isLocked = isSelectedAdmin && !canSetSite;

            return _buildActionFooter('SAVE CHANGES', _isSavingUserPermissions || isLocked, isLocked ? () {} : () async {
              if (_selectedManagementUser == null) return;
              setState(() => _isSavingUserPermissions = true);
              try {
                // Update User details (like roleId)
                await _repository.updateUser(_selectedManagementUser!);
                // Update User custom permissions
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
            });
          },
        ),
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
            return DropdownMenuItem(value: u, child: Text(u.username, overflow: TextOverflow.ellipsis));
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
            return DropdownMenuItem(value: r, child: Text(r.name, overflow: TextOverflow.ellipsis));
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
                  siteCode: _selectedManagementUser!.siteCode,
                );
                _selectedManagementUser = _allUsers[userIdx];
              });
            }
          },
        ),
      ),
    );
  }

  Widget _buildUserSiteSelector(bool isDark, bool canSetSite) {
    if (_selectedManagementUser == null) return const SizedBox.shrink();

    final currentSiteCode = _selectedManagementUser!.siteCode ?? 'ALL';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? Theme.of(context).cardColor : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentSiteCode,
          hint: const Text('Select Site'),
          isExpanded: true,
          dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          items: _availableSites.map((site) {
            return DropdownMenuItem(value: site.siteCode, child: Text('${site.siteCode} - ${site.siteName}', overflow: TextOverflow.ellipsis));
          }).toList()
            ..insert(0, const DropdownMenuItem(value: 'ALL', child: Text('ALL - Global Admin', overflow: TextOverflow.ellipsis))),
          onChanged: canSetSite ? (val) {
            if (val != null) {
              setState(() {
                final userIdx = _allUsers.indexOf(_selectedManagementUser!);
                _allUsers[userIdx] = User(
                  id: _selectedManagementUser!.id,
                  username: _selectedManagementUser!.username,
                  email: _selectedManagementUser!.email,
                  isActive: _selectedManagementUser!.isActive,
                  roleId: _selectedManagementUser!.roleId,
                  permissions: _selectedManagementUser!.permissions,
                  siteCode: val == 'ALL' ? null : val,
                );
                _selectedManagementUser = _allUsers[userIdx];
              });
            }
          } : null,
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
        siteCode: _selectedManagementUser!.siteCode,
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

// ============================================================================
// SEGREGATED PERMISSION MATRIX (MOBILE SALES & MANUFACTURING)
// ============================================================================

class _SegregatedPermissionMatrix extends StatefulWidget {
  final List<ModuleAccess> permissions;
  final bool isDark;
  final Function(String moduleId, String type, bool value, {List<String>? subModuleIds}) onUpdate;

  const _SegregatedPermissionMatrix({
    required this.permissions,
    required this.isDark,
    required this.onUpdate,
  });

  @override
  State<_SegregatedPermissionMatrix> createState() => _SegregatedPermissionMatrixState();
}

class _SegregatedPermissionMatrixState extends State<_SegregatedPermissionMatrix> {
  int _activeCategory = 0; // 0 = Mobile Sales, 1 = Manufacturing
  bool _isSystemExpanded = false;

  int _countActive(List<PermissionNode> nodes) {
    int count = 0;
    for (final node in nodes) {
      final access = widget.permissions.firstWhere(
        (p) => p.moduleId == node.moduleId,
        orElse: () => ModuleAccess(moduleId: node.moduleId ?? ''),
      );
      if (access.canRead || access.canCreate || access.canUpdate || access.canDelete) {
        count++;
      }
    }
    return count;
  }

  void _applySalesPreset(String preset) {
    final salesIds = _UserManagementScreenState._salesPermissionNodes
        .map((n) => n.moduleId!)
        .toList();

    if (preset == 'ALL') {
      widget.onUpdate('', 'all_cat', true, subModuleIds: salesIds);
      widget.onUpdate('app.home', 'read', true);
    } else if (preset == 'CLEAR') {
      widget.onUpdate('', 'all_cat', false, subModuleIds: salesIds);
    } else if (preset == 'STANDARD') {
      widget.onUpdate('', 'all_cat', false, subModuleIds: salesIds);
      const standardSales = [
        'logistics.sales_invoice',
        'logistics.sales.tender_cash',
        'logistics.sales.tender_credit',
        'logistics.sales.sales_order',
      ];
      for (final id in standardSales) {
        widget.onUpdate(id, 'create', true);
        widget.onUpdate(id, 'read', true);
        widget.onUpdate(id, 'update', true);
        widget.onUpdate(id, 'delete', true);
      }
      widget.onUpdate('logistics.reports', 'read', true);
      widget.onUpdate('logistics.sales.reports', 'read', true);
      widget.onUpdate('app.home', 'read', true);
    }
  }

  void _applyMfgPreset(String preset) {
    final mfgIds = _UserManagementScreenState._manufacturingPermissionNodes
        .map((n) => n.moduleId!)
        .toList();

    if (preset == 'ALL') {
      widget.onUpdate('', 'all_cat', true, subModuleIds: mfgIds);
      widget.onUpdate('app.home', 'read', true);
    } else if (preset == 'CLEAR') {
      widget.onUpdate('', 'all_cat', false, subModuleIds: mfgIds);
    } else if (preset == 'STANDARD') {
      widget.onUpdate('', 'all_cat', false, subModuleIds: mfgIds);
      const standardMfg = [
        'manufacturing.execution',
        'manufacturing.delivery',
        'manufacturing.qr_label',
      ];
      for (final id in standardMfg) {
        widget.onUpdate(id, 'create', true);
        widget.onUpdate(id, 'read', true);
        widget.onUpdate(id, 'update', true);
        widget.onUpdate(id, 'delete', true);
      }
      widget.onUpdate('app.home', 'read', true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = widget.isDark;
    final primary = theme.primaryColor;

    final salesActiveCount = _countActive(_UserManagementScreenState._salesPermissionNodes);
    final mfgActiveCount = _countActive(_UserManagementScreenState._manufacturingPermissionNodes);
    final sysActiveCount = _countActive(_UserManagementScreenState._systemPermissionNodes);

    final activeNodes = _activeCategory == 0
        ? _UserManagementScreenState._salesPermissionNodes
        : _UserManagementScreenState._manufacturingPermissionNodes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category Header / Count
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'MODULE ACCESS CATEGORY',
              style: TextStyle(
                color: isDark ? Colors.white38 : Colors.black38,
                fontWeight: FontWeight.bold,
                fontSize: 11,
                letterSpacing: 1.4,
              ),
            ),
            Text(
              '${_activeCategory == 0 ? salesActiveCount : mfgActiveCount}/${activeNodes.length} Granted',
              style: TextStyle(
                color: primary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Modern 2-Segment Tab Selector
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141418) : const Color(0xFFE9EBEF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
            ),
          ),
          child: Row(
            children: [
              // Mobile Sales Tab
              Expanded(
                child: _buildCategoryTab(
                  index: 0,
                  label: 'Mobile Sales',
                  icon: Icons.point_of_sale_rounded,
                  badgeText: '$salesActiveCount/${_UserManagementScreenState._salesPermissionNodes.length}',
                  isSelected: _activeCategory == 0,
                  primaryColor: primary,
                  isDark: isDark,
                  onTap: () => setState(() => _activeCategory = 0),
                ),
              ),
              const SizedBox(width: 4),
              // Manufacturing Tab
              Expanded(
                child: _buildCategoryTab(
                  index: 1,
                  label: 'Manufacturing',
                  icon: Icons.precision_manufacturing_rounded,
                  badgeText: '$mfgActiveCount/${_UserManagementScreenState._manufacturingPermissionNodes.length}',
                  isSelected: _activeCategory == 1,
                  primaryColor: primary,
                  isDark: isDark,
                  onTap: () => setState(() => _activeCategory = 1),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Supervisor Quick Presets
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C222B) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: primary.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.bolt_rounded, size: 18, color: primary),
              const SizedBox(width: 8),
              Text(
                'Presets:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _activeCategory == 0
                      ? [
                          _buildPresetChip(
                            label: 'Grant All',
                            icon: Icons.check_circle_outline,
                            color: Colors.green,
                            onTap: () => _applySalesPreset('ALL'),
                            isDark: isDark,
                          ),
                          _buildPresetChip(
                            label: 'Standard Salesman',
                            icon: Icons.badge_outlined,
                            color: const Color(0xFF4A90D9),
                            onTap: () => _applySalesPreset('STANDARD'),
                            isDark: isDark,
                          ),
                          _buildPresetChip(
                            label: 'Clear',
                            icon: Icons.clear_all_rounded,
                            color: Colors.redAccent,
                            onTap: () => _applySalesPreset('CLEAR'),
                            isDark: isDark,
                          ),
                        ]
                      : [
                          _buildPresetChip(
                            label: 'Grant All',
                            icon: Icons.check_circle_outline,
                            color: Colors.green,
                            onTap: () => _applyMfgPreset('ALL'),
                            isDark: isDark,
                          ),
                          _buildPresetChip(
                            label: 'Standard Operator',
                            icon: Icons.engineering_outlined,
                            color: const Color(0xFF00897B),
                            onTap: () => _applyMfgPreset('STANDARD'),
                            isDark: isDark,
                          ),
                          _buildPresetChip(
                            label: 'Clear',
                            icon: Icons.clear_all_rounded,
                            color: Colors.redAccent,
                            onTap: () => _applyMfgPreset('CLEAR'),
                            isDark: isDark,
                          ),
                        ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // List of Active Category Permission Cards
        ...activeNodes.map(
          (node) => _buildModuleCard(node, widget.permissions, isDark, widget.onUpdate),
        ),

        const SizedBox(height: 16),

        // Collapsible System & Foundation Settings Section
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF18181E) : const Color(0xFFF7F8FA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.white10 : Colors.black12,
            ),
          ),
          child: Column(
            children: [
              InkWell(
                onTap: () => setState(() => _isSystemExpanded = !_isSystemExpanded),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF9800).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.admin_panel_settings_outlined,
                          size: 20,
                          color: Color(0xFFFF9800),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Core System & Base Access',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            Text(
                              'Dashboard, Settings, User Admin & Sync ($sysActiveCount/${_UserManagementScreenState._systemPermissionNodes.length} active)',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white38 : Colors.black38,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        _isSystemExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ],
                  ),
                ),
              ),
              if (_isSystemExpanded) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: _UserManagementScreenState._systemPermissionNodes.map(
                      (node) => _buildModuleCard(node, widget.permissions, isDark, widget.onUpdate),
                    ).toList(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryTab({
    required int index,
    required String label,
    required IconData icon,
    required String badgeText,
    required bool isSelected,
    required Color primaryColor,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? primaryColor.withValues(alpha: 0.25) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isSelected
              ? Border.all(color: primaryColor, width: 1.5)
              : null,
          boxShadow: isSelected && !isDark
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected
                  ? primaryColor
                  : (isDark ? Colors.white54 : Colors.black54),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 13,
                  color: isSelected
                      ? (isDark ? Colors.white : primaryColor)
                      : (isDark ? Colors.white60 : Colors.black54),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? primaryColor.withValues(alpha: 0.2)
                    : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                badgeText,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected
                      ? primaryColor
                      : (isDark ? Colors.white38 : Colors.black45),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetChip({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
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

    final theme = Theme.of(context);
    final iconColor = node.iconColor ?? theme.primaryColor;
    final icon = node.icon;
    final description = node.description;

    Color cardBg;
    Color borderColor;
    if (isCrud) {
      cardBg = isDark ? const Color(0xFF003D3D) : const Color(0xFFE0F7F7);
      borderColor = theme.primaryColor.withValues(alpha: isDark ? 0.5 : 0.3);
    } else if (isRead) {
      cardBg = isDark ? const Color(0xFF1A2A3D) : const Color(0xFFE8F0FB);
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
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 18),
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
                    if (description.isNotEmpty)
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                  ],
                ),
              ),
              if (isCrud)
                _accessBadge('FULL', theme.primaryColor, isDark)
              else if (isRead)
                _accessBadge('READ', const Color(0xFF4A90D9), isDark)
              else
                _accessBadge('NONE', Colors.grey, isDark),
            ],
          ),
          const SizedBox(height: 14),
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
                  activeColor: theme.primaryColor,
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
}

