import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_event.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_state.dart';
import 'package:enterprise_auth_mobile/features/inventory/ui/screens/qr_label_screen.dart';
import 'package:enterprise_auth_mobile/features/inventory/ui/screens/picking_screen.dart';
import 'package:enterprise_auth_mobile/features/inventory/ui/screens/stock_control_screen.dart';
import 'package:enterprise_auth_mobile/features/manufacturing/ui/screens/manufacturing_screen.dart';
import 'package:enterprise_auth_mobile/features/settings/ui/screens/settings_modules_screen.dart';
import 'package:enterprise_auth_mobile/features/settings/ui/screens/printer_settings_screen.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/pages/receipt_screen.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/pages/delivery_screen.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/pages/transfer_screen.dart';
import 'package:enterprise_auth_mobile/core/theme_cubit.dart';
import 'package:enterprise_auth_mobile/features/administration/ui/screens/user_management_screen.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'package:enterprise_auth_mobile/features/manufacturing/bloc/manufacturing_bloc.dart';
import 'package:enterprise_auth_mobile/features/manufacturing/bloc/manufacturing_event.dart';
import 'package:enterprise_auth_mobile/features/manufacturing/bloc/manufacturing_state.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sync_bloc.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sync_state.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/widgets/sync_overlay.dart';
import 'package:intl/intl.dart';

class HomeScreen extends StatefulWidget {
  final String username;
  final List<String> permissions;

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

  bool _hasAccess(String module, String submodule) {
    if (widget.permissions.contains('administration.user_management.delete')) {
      return true;
    }
    return widget.permissions.contains('$module.$submodule.read');
  }

  @override
  void initState() {
    super.initState();
    _loadLastSync();
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
        final timestampStr = last[LocalDatabaseHelper.colSyncTimestamp] as String;
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
    String? siteCode;
    if (authState is Authenticated) {
      siteCode = authState.siteCode;
    }

    context.read<ManufacturingBloc>().add(SyncDataRequested(siteCode: siteCode));
    
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
            final isSyncing = syncState is SyncInProgress ||
                mfgState is ManufacturingSyncProgress;

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
                          icon: Icon(Icons.menu, color: isDark ? Colors.white70 : Colors.black87),
                          onPressed: isSyncing ? null : () => Scaffold.of(context).openDrawer(),
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
                            isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                          onPressed: isSyncing ? null : () => context.read<ThemeCubit>().toggleTheme(),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                    drawer: isSyncing ? null : _buildDrawer(context),
                    body: _buildBody(context),
                  ),
                  const SyncOverlay(),
                ],
              ),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('EXIT APP', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (widget.permissions.isEmpty) {
      return _buildRestrictedUI(
        context,
        'NO PERMISSIONS ASSIGNED',
        'Your account (${widget.username}) has no assigned permissions. Please contact your system administrator.',
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
      if (_hasAccess('logistics', 'delivery'))
        _buildMenuButton(
          context,
          'Delivery',
          Icons.local_shipping_rounded,
          DeliveryScreen(permissions: widget.permissions),
        ),
      if (_hasAccess('manufacturing', 'all'))
        _buildMenuButton(
          context,
          'Manufacturing',
          Icons.precision_manufacturing_rounded,
          ManufacturingScreen(permissions: widget.permissions),
        ),
      if (_hasAccess('settings', 'general'))
        _buildMenuButton(
          context,
          'Settings',
          Icons.settings_suggest_rounded,
          const SettingsModulesScreen(),
        ),
      if (_hasAccess('administration', 'user_management'))
        _buildMenuButton(
          context,
          'Administration',
          Icons.admin_panel_settings_rounded,
          const UserManagementScreen(),
        ),
      if (_hasAccess('inventory', 'by_identifier'))
        _buildMenuButton(
          context,
          'QR Label',
          Icons.qr_code_scanner_rounded,
          const QrLabelScreen(),
        ),
      if (_hasAccess('settings', 'printer'))
        _buildMenuButton(
          context,
          'Printer Settings',
          Icons.print_rounded,
          const PrinterSettingsScreen(),
        ),
    ];

    if (menuItems.isEmpty) {
      return _buildRestrictedUI(
        context,
        'NO AUTHORIZED MODULES',
        'Your account has permissions ${widget.permissions.take(3).toList()}... but none match the dashboard modules.',
      );
    }

    return GridView.count(
      padding: const EdgeInsets.all(16),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.9,
      children: menuItems,
    );
  }

  Widget _buildRestrictedUI(BuildContext context, String title, String message) {
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
    final isSyncing = syncState is SyncInProgress || mfgState is ManufacturingSyncProgress;

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
                        MaterialPageRoute(builder: (_) => screen),
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
                  color: isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black45,
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
                    color: isDark ? theme.colorScheme.primaryContainer.withValues(alpha: 0.1) : theme.primaryColor.withValues(alpha: 0.1),
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
                    style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
                  ),
                  onTap: () => Navigator.pop(context),
                ),
                if (_hasAccess('settings', 'general'))
                  ListTile(
                    leading: Icon(
                      Icons.settings,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    title: Text(
                      'Settings',
                      style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SettingsModulesScreen()),
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
              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
            ),
            onTap: () => context.read<AuthBloc>().add(LogoutRequested()),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
