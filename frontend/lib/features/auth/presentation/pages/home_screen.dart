import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_event.dart';
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

class HomeScreen extends StatelessWidget {
  final String username;
  final List<String> permissions;

  const HomeScreen({
    super.key,
    required this.username,
    required this.permissions,
  });

  bool _hasAccess(String module, String submodule) {
    if (permissions.contains('administration.user_management.delete')) {
      return true;
    }
    return permissions.contains('$module.$submodule.read');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final bool? shouldExit = await _showExitConfirmation(context);
        if (shouldExit == true) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: theme.colorScheme.surface,
          elevation: 0,
          leading: Builder(
            builder: (context) => IconButton(
              icon: Icon(Icons.menu, color: isDark ? Colors.white70 : Colors.black87),
              onPressed: () => Scaffold.of(context).openDrawer(),
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
              onPressed: () => context.read<ThemeCubit>().toggleTheme(),
            ),
            const SizedBox(width: 8),
          ],
        ),
        drawer: _buildDrawer(context),
        body: _buildBody(context),
      ),
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
    if (permissions.isEmpty) {
      return _buildRestrictedUI(
        context,
        'NO PERMISSIONS ASSIGNED',
        'Your account ($username) has no assigned permissions. Please contact your system administrator.',
      );
    }

    final List<Widget> menuItems = [
      if (_hasAccess('logistics', 'receipt'))
        _buildMenuButton(
          context,
          'Receipt',
          Icons.receipt_long_rounded,
          const ReceiptScreen(),
        ),
      if (_hasAccess('logistics', 'delivery'))
        _buildMenuButton(
          context,
          'Delivery',
          Icons.local_shipping_rounded,
          DeliveryScreen(permissions: permissions),
        ),
      if (_hasAccess('manufacturing', 'all'))
        _buildMenuButton(
          context,
          'Manufacturing',
          Icons.precision_manufacturing_rounded,
          ManufacturingScreen(permissions: permissions),
        ),
      if (_hasAccess('inventory', 'stock_control'))
        _buildMenuButton(
          context,
          'Stock control',
          Icons.grid_view_rounded,
          const StockControlScreen(),
        ),
      if (_hasAccess('inventory', 'picking'))
        _buildMenuButton(
          context,
          'Picking',
          Icons.pan_tool_alt_rounded,
          const PickingScreen(),
        ),
      if (_hasAccess('settings', 'general'))
        _buildMenuButton(
          context,
          'Settings',
          Icons.settings_suggest_rounded,
          const SettingsModulesScreen(),
        ),
      if (_hasAccess('logistics', 'transfer'))
        _buildMenuButton(
          context,
          'Transfer',
          Icons.swap_horiz_rounded,
          const TransferScreen(),
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
        'Your account has permissions ${permissions.take(3).toList()}... but none match the dashboard modules.',
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
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(12),
      elevation: isDark ? 0 : 2,
      child: InkWell(
        onTap:
            onTapOverride ??
            (screen != null
                ? () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => screen),
                  )
                : null),
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
                        username.toUpperCase(),
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
