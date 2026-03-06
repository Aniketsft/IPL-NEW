import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_event.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/pages/receipt_screen.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/pages/transfer_screen.dart';
import 'package:enterprise_auth_mobile/features/inventory/ui/screens/stock_control_screen.dart';
import 'package:enterprise_auth_mobile/features/inventory/ui/screens/picking_screen.dart';
import 'package:enterprise_auth_mobile/features/inventory/ui/screens/by_identifier_screen.dart';
import 'package:enterprise_auth_mobile/features/manufacturing/ui/screens/manufacturing_screen.dart';
import 'package:enterprise_auth_mobile/features/settings/ui/screens/settings_modules_screen.dart';
import 'package:enterprise_auth_mobile/features/settings/ui/screens/printer_settings_screen.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/pages/view_sales_order_screen.dart';
import 'package:enterprise_auth_mobile/features/other/ui/screens/other_modules_screen.dart';

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
    print('HomeScreen: Building for user: $username');
    print('HomeScreen: Total permissions: ${permissions.length}');
    if (permissions.isEmpty) {
      print('WARNING: Permissions list is EMPTY for user $username');
    } else {
      print('HomeScreen: Sample permissions: ${permissions.take(5).toList()}');
    }
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white70),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Row(
          children: [
            const Text(
              'HIPO CLOUD',
              style: TextStyle(
                color: Color(0xFFFF9800),
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const Spacer(),
            const Text(
              'Main Plant',
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: const Icon(Icons.logout_rounded, color: Colors.white70),
              onPressed: () => context.read<AuthBloc>().add(LogoutRequested()),
            ),
          ],
        ),
      ),
      drawer: _buildDrawer(context),
      body: _buildBody(context),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: Colors.white,
        mini: true,
        child: const Icon(Icons.wb_sunny_outlined, color: Colors.black87),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (permissions.isEmpty) {
      return _buildRestrictedUI(
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
      _buildMenuButton(
        context,
        'View Sales Order',
        Icons.view_list_rounded,
        const ViewSalesOrderScreen(),
      ),
      if (_hasAccess('manufacturing', 'dashboard'))
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
          const OtherModulesScreen(),
        ),
      if (_hasAccess('inventory', 'by_identifier'))
        _buildMenuButton(
          context,
          'By identifier',
          Icons.qr_code_scanner_rounded,
          const ByIdentifierScreen(),
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
        'NO AUTHORIZED MODULES',
        'Your account has permissions ${permissions.take(3).toList()}... but none match the dashboard modules. Casing or naming mismatch?',
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

  Widget _buildRestrictedUI(String title, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.lock_person_rounded,
              size: 64,
              color: Colors.white24,
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, height: 1.5),
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
    Widget screen,
  ) {
    return Material(
      color: const Color(0xFF1E1E1E),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => screen)),
        borderRadius: BorderRadius.circular(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: const Color(0xFFFF9800)),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF1E1E1E),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF2C2C2C)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0xFFFF9800),
                  child: Icon(Icons.person, color: Colors.black87),
                ),
                const SizedBox(height: 12),
                Text(
                  username.toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
                const Text(
                  'System Administrator',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard, color: Colors.white70),
            title: const Text(
              'Dashboard',
              style: TextStyle(color: Colors.white70),
            ),
            onTap: () => Navigator.pop(context),
          ),
          const Divider(color: Colors.white10),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text(
              'Log out',
              style: TextStyle(color: Colors.redAccent),
            ),
            onTap: () => context.read<AuthBloc>().add(LogoutRequested()),
          ),
        ],
      ),
    );
  }
}
