import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_event.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_state.dart';
import 'package:enterprise_auth_mobile/features/inventory/ui/screens/qr_label_screen.dart';
import 'package:enterprise_auth_mobile/features/manufacturing/ui/screens/manufacturing_screen.dart';
import 'package:enterprise_auth_mobile/features/settings/ui/screens/settings_modules_screen.dart';
import 'package:enterprise_auth_mobile/features/settings/ui/screens/printer_settings_screen.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/pages/delivery_screen.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/pages/sales_invoice/sales_menu_screen.dart';
import 'package:enterprise_auth_mobile/core/theme_cubit.dart';
import 'package:enterprise_auth_mobile/features/administration/ui/screens/user_management_screen.dart';
import 'package:enterprise_auth_mobile/features/administration/ui/screens/sync_logs_screen.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'package:enterprise_auth_mobile/features/manufacturing/bloc/manufacturing_bloc.dart';
import 'package:enterprise_auth_mobile/features/manufacturing/bloc/manufacturing_state.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sync_bloc.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sync_state.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/widgets/sync_overlay.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_sync_bloc.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_sync_event.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_sync_state.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/widgets/sales_invoice_sync_overlay.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/widgets/sales_rep_selection_dialog.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/sales_invoice_sync_repository.dart';
import 'package:intl/intl.dart';

class HomeScreen extends StatefulWidget {
  final String username;
  final List<String> permissions;

  static String? _promptedSessionUser;

  static void resetSessionPrompt() {
    _promptedSessionUser = null;
  }

  const HomeScreen({
    super.key,
    required this.username,
    required this.permissions,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _lastSyncStr = 'Never';
  List<Map<String, dynamic>> _selectedSalesReps = [];

  bool _hasAccess(String permissionString) {
    return widget.permissions.contains(permissionString);
  }

  @override
  void initState() {
    super.initState();
    _loadLastSync();
    _loadSelectedSalesReps();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndPromptSalesRepSelection();
    });
  }

  @override
  void dispose() {
    HomeScreen.resetSessionPrompt();
    super.dispose();
  }

  Future<void> _loadSelectedSalesReps() async {
    try {
      final reps = await LocalDatabaseHelper.instance.getSelectedSalesReps(
        username: widget.username,
      );
      if (mounted) {
        setState(() {
          _selectedSalesReps = reps;
        });
      }
    } catch (e) {
      debugPrint("Home: Error loading selected sales reps: $e");
    }
  }

  Future<void> _checkAndPromptSalesRepSelection({bool force = false}) async {
    await _loadSelectedSalesReps();
    if (!mounted) return;

    final isNewLoginPrompt = HomeScreen._promptedSessionUser != widget.username;
    if (_selectedSalesReps.isEmpty || force || isNewLoginPrompt) {
      HomeScreen._promptedSessionUser = widget.username;
      final authState = context.read<AuthBloc>().state;
      final siteCode = (authState is Authenticated &&
              authState.siteCode != null &&
              authState.siteCode!.isNotEmpty &&
              authState.siteCode != 'ALL')
          ? authState.siteCode
          : null;

      final syncRepo = context.read<SalesInvoiceSyncRepository>();
      await SalesRepSelectionDialog.show(
        context,
        canDismiss: _selectedSalesReps.isNotEmpty && !force && !isNewLoginPrompt,
        userSiteCode: siteCode,
        syncRepository: syncRepo,
        username: widget.username,
      );
      await _loadSelectedSalesReps();
    }
  }

  Future<void> _loadLastSync() async {
    try {
      final history = await LocalDatabaseHelper.instance.getSyncHistory();
      if (history.isNotEmpty) {
        // Find latest 'Success' entry
        final last = history.firstWhere(
          (h) => h[LocalDatabaseHelper.colSyncStatus] == 'Success',
          orElse: () => history.first,
        );
        final timestampStr =
            last[LocalDatabaseHelper.colSyncTimestamp] as String;
        final timestamp = DateTime.tryParse(timestampStr);
        if (timestamp != null) {
          setState(() {
            _lastSyncStr = DateFormat('yyyy-MM-dd HH:mm').format(timestamp);
          });
        }
      }
    } catch (e) {
      debugPrint("Home: Error loading last sync: $e");
    }
  }

  void _triggerSync() {
    final authState = context.read<AuthBloc>().state;
    final siteCode = (authState is Authenticated &&
            authState.siteCode != null &&
            authState.siteCode!.isNotEmpty &&
            authState.siteCode != 'ALL')
        ? authState.siteCode
        : null;

    if (siteCode == null || siteCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot sync: No assigned site code found for logged in user.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    context.read<SalesInvoiceSyncBloc>().add(
          StartSalesInvoiceSyncRequested(siteCode: siteCode),
        );

    // Periodically check if sync is done to refresh timestamp
    Future.delayed(const Duration(seconds: 3), () => _loadLastSync());
    Future.delayed(const Duration(seconds: 10), () => _loadLastSync());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return BlocBuilder<SyncBloc, SyncState>(
      builder: (context, syncState) {
        return BlocBuilder<ManufacturingBloc, ManufacturingState>(
          builder: (context, mfgState) {
            return BlocBuilder<SalesInvoiceSyncBloc, SalesInvoiceSyncState>(
              builder: (context, salesSyncState) {
                final isSyncing =
                    syncState is SyncInProgress ||
                    mfgState is ManufacturingSyncProgress ||
                    salesSyncState is SalesInvoiceSyncInProgress;

            return PopScope(
              canPop: false,
              onPopInvoked: (didPop) async {
                if (didPop) return;
                if (isSyncing) return; // Block exiting during sync
                final bool? shouldExit = await _showExitConfirmation(context);
                if (shouldExit == true) {
                  SystemNavigator.pop();
                }
              },
              child: Stack(
                children: [
                  Scaffold(
                    backgroundColor: theme.scaffoldBackgroundColor,
                    appBar: AppBar(
                      backgroundColor: theme.colorScheme.surface,
                      elevation: 0,
                      leading: Builder(
                        builder: (context) => IconButton(
                          icon: Icon(
                            Icons.menu,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                          onPressed: isSyncing
                              ? null
                              : () => Scaffold.of(context).openDrawer(),
                        ),
                      ),
                      title: Text(
                        'HIPO CLOUD',
                        style: TextStyle(
                          color: theme.primaryColor,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      actions: [
                        IconButton(
                          icon: Icon(
                            isDark
                                ? Icons.light_mode_rounded
                                : Icons.dark_mode_rounded,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                          onPressed: isSyncing
                              ? null
                              : () => context.read<ThemeCubit>().toggleTheme(),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                    drawer: isSyncing ? null : _buildDrawer(context),
                    body: _buildBody(context),
                  ),
                  const SyncOverlay(),
                  const SalesInvoiceSyncOverlay(),
                ],
              ),
            );
              },
            );
          },
        );
      },
    );
  }

  Future<bool?> _showExitConfirmation(BuildContext context) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Confirm Exit',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to close the application?',
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primaryColor,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'EXIT APP',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (!widget.permissions.any((p) => p.startsWith('app.home.'))) {
      return _buildRestrictedUI(
        context,
        'NO PERMISSIONS ASSIGNED',
        'Your account (${widget.username}) does not have dashboard access. Please contact your system administrator.',
      );
    }

    final List<Widget> menuItems = [
      _buildMenuButton(
        context,
        'Data Sync',
        Icons.sync_rounded,
        null,
        onTapOverride: _triggerSync,
        subtitle: 'Last: $_lastSyncStr',
      ),
      if (_hasAccess('logistics.delivery.read'))
        _buildMenuButton(
          context,
          'Delivery',
          Icons.local_shipping_rounded,
          DeliveryScreen(permissions: widget.permissions),
        ),
      if (_hasAccess('logistics.sales_invoice.read'))
        _buildMenuButton(
          context,
          'Sales',
          Icons.receipt_long_rounded,
          SalesMenuScreen(permissions: widget.permissions),
        ),
      if (_hasAccess('manufacturing.all.read'))
        _buildMenuButton(
          context,
          'Manufacturing',
          Icons.precision_manufacturing_rounded,
          ManufacturingScreen(permissions: widget.permissions),
        ),

      if (_hasAccess('inventory.by_identifier.read'))
        _buildMenuButton(
          context,
          'QR Label',
          Icons.qr_code_scanner_rounded,
          QrLabelScreen(permissions: widget.permissions),
        ),
      if (_hasAccess('settings.printer.read'))
        _buildMenuButton(
          context,
          'Printer Settings',
          Icons.print_rounded,
          PrinterSettingsScreen(permissions: widget.permissions),
        ),
    ];

    if (menuItems.isEmpty) {
      return _buildRestrictedUI(
        context,
        'NO AUTHORIZED MODULES',
        'Your account has permissions ${widget.permissions.take(3).toList()}... but none match the dashboard modules.',
      );
    }

    return Column(
      children: [
        _buildSalesRepBanner(context, theme, isDark),
        Expanded(
          child: GridView.count(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.9,
            children: menuItems,
          ),
        ),
      ],
    );
  }

  Widget _buildSalesRepBanner(
    BuildContext context,
    ThemeData theme,
    bool isDark,
  ) {
    final hasReps = _selectedSalesReps.isNotEmpty;
    final repText = hasReps
        ? _selectedSalesReps
            .map((r) => '${r['code']} (${r['name']})')
            .join(', ')
        : 'None selected (Tap to choose active reps)';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      decoration: BoxDecoration(
        color: hasReps
            ? (isDark ? Colors.blueGrey.shade900.withOpacity(0.6) : Colors.blue.shade50)
            : (isDark ? Colors.red.shade900.withOpacity(0.4) : Colors.amber.shade50),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasReps
              ? theme.primaryColor.withOpacity(0.3)
              : Colors.amber.withOpacity(0.6),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _checkAndPromptSalesRepSelection(force: true),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: hasReps
                        ? theme.primaryColor.withOpacity(0.15)
                        : Colors.amber.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    hasReps
                        ? Icons.assignment_ind_rounded
                        : Icons.warning_amber_rounded,
                    color: hasReps ? theme.primaryColor : Colors.amber.shade800,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Active Sales Reps',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                          if (hasReps) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: theme.primaryColor.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${_selectedSalesReps.length}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: theme.primaryColor,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        repText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: hasReps
                              ? (isDark ? Colors.white : Colors.black87)
                              : Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _checkAndPromptSalesRepSelection(force: true),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: theme.primaryColor,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                  child: const Text(
                    'Change',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRestrictedUI(
    BuildContext context,
    String title,
    String message,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_person_rounded,
              size: 64,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black54,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuButton(
    BuildContext context,
    String title,
    IconData icon,
    Widget? screen, {
    VoidCallback? onTapOverride,
    String? subtitle,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final syncState = context.watch<SyncBloc>().state;
    final mfgState = context.watch<ManufacturingBloc>().state;
    final salesSyncState = context.watch<SalesInvoiceSyncBloc>().state;
    final isSyncing =
        syncState is SyncInProgress || mfgState is ManufacturingSyncProgress || salesSyncState is SalesInvoiceSyncInProgress;

    return Material(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(12),
      elevation: isDark ? 0 : 2,
      child: InkWell(
        onTap: isSyncing
            ? null
            : (onTapOverride ??
                  (screen != null
                      ? () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => screen,
                            settings: RouteSettings(
                              name: '/${title.toLowerCase().replaceAll(' ', '_')}',
                            ),
                          ),
                        )
                      : null)),
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: theme.primaryColor),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.5)
                      : Colors.black45,
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Drawer(
      backgroundColor: theme.colorScheme.surface,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                DrawerHeader(
                  decoration: BoxDecoration(
                    color: isDark
                        ? theme.colorScheme.primaryContainer.withValues(
                            alpha: 0.1,
                          )
                        : theme.primaryColor.withValues(alpha: 0.1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      CircleAvatar(
                        backgroundColor: theme.primaryColor,
                        child: const Icon(Icons.person, color: Colors.black),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.username.toUpperCase(),
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'System Administrator',
                        style: TextStyle(
                          color: isDark ? Colors.white38 : Colors.black45,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                ListTile(
                  leading: Icon(
                    Icons.dashboard,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                  title: Text(
                    'Dashboard',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  onTap: () => Navigator.pop(context),
                ),
                if (_hasAccess('settings.general.read'))
                  ListTile(
                    leading: Icon(
                      Icons.settings,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    title: Text(
                      'Settings',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SettingsModulesScreen(),
                        ),
                      );
                    },
                  ),
                if (_hasAccess('administration.user_management.read'))
                  ListTile(
                    leading: Icon(
                      Icons.admin_panel_settings_rounded,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    title: Text(
                      'User Admin',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const UserManagementScreen(),
                        ),
                      );
                    },
                  ),
                if (_hasAccess('administration.sync_logs.read'))
                  ListTile(
                    leading: Icon(
                      Icons.sync_alt,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    title: Text(
                      'Sync Logs',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SyncLogsScreen(),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
          Divider(color: isDark ? Colors.white10 : Colors.black12),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text(
              'Log out',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
            onTap: () {
              HomeScreen.resetSessionPrompt();
              context.read<AuthBloc>().add(LogoutRequested());
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
