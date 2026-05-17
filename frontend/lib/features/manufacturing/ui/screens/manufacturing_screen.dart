import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:enterprise_auth_mobile/core/widgets/industrial_module_layout.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/pages/production_tracking_product_list_screen.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/pages/view_sales_order_screen.dart';
import '../../bloc/manufacturing_bloc.dart';
import '../../bloc/manufacturing_event.dart';
import '../../bloc/manufacturing_state.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_state.dart';
import '../widgets/sync_progress_dialog.dart';

class ManufacturingScreen extends StatefulWidget {
  final List<String> permissions;

  const ManufacturingScreen({super.key, required this.permissions});

  @override
  State<ManufacturingScreen> createState() => _ManufacturingScreenState();
}

class _MenuItem {
  final String title;
  final IconData icon;
  final Widget? targetScreen;
  final VoidCallback? onTap;
  final String? subtitle;

  _MenuItem({
    required this.title,
    required this.icon,
    this.targetScreen,
    this.onTap,
    this.subtitle,
  });
}

class _ManufacturingScreenState extends State<ManufacturingScreen> {
  String _lastSyncStr = 'Never';

  bool _hasAccess(String module, String submodule) {
    if (widget.permissions.contains('administration.user_management.delete')) {
      return true;
    }
    return widget.permissions.contains('$module.$submodule.read');
  }

  void _triggerSync() {
    final authState = context.read<AuthBloc>().state;
    String? siteCode;
    if (authState is Authenticated) {
      siteCode = authState.siteCode;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const SyncProgressDialog(),
    );
    context.read<ManufacturingBloc>().add(SyncDataRequested(siteCode: siteCode));
    setState(() {
      _lastSyncStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    });
  }

  Future<void> _startEndOfDayFlow() async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Step 1: Selection of Work Order
    final String? selectedWo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.cardColor,
        title: Text('Select Work Order', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: Text('WO-2026-001', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                onTap: () => Navigator.pop(ctx, 'WO-2026-001'),
              ),
              ListTile(
                title: Text('WO-2026-002', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                onTap: () => Navigator.pop(ctx, 'WO-2026-002'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
        ],
      ),
    );

    if (selectedWo == null) return;

    // Step 2: Confirmation to proceed or close
    if (!mounted) return;
    final bool? confirmProceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.cardColor,
        title: Text('Proceed ($selectedWo)', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
        content: Text('Do you want to proceed or close?', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CLOSE')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('PROCEED')),
        ],
      ),
    );

    if (confirmProceed != true) return;

    // Step 3: Simulation removed

    // Step 4: Error connecting to X3
    if (!mounted) return;
    final bool? retry = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.cardColor,
        title: const Text('Connection Error', style: TextStyle(color: Colors.redAccent)),
        content: Text('Error connecting to X3. Do you want to retry?', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('RETRY')),
        ],
      ),
    );

    if (retry != true) return;

    // Step 5: Simulation removed
    if (!mounted) return;

    // Step 6: Final Failure Prompt
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.cardColor,
        title: const Text('Status', style: TextStyle(color: Colors.redAccent)),
        content: Text('Process Failed', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ManufacturingBloc, ManufacturingState>(
      builder: (context, state) {
        final query = state.dashboardSearchQuery.toLowerCase();

        final menuItems = [
          _MenuItem(
            title: 'Data Sync',
            icon: Icons.sync_rounded,
            onTap: _triggerSync,
            subtitle: 'Last: $_lastSyncStr',
          ),
          if (_hasAccess('logistics', 'delivery'))
            _MenuItem(
              title: 'Work order',
              icon: Icons.timer_outlined,
              onTap: () => Navigator.pop(context),
            ),
          if (_hasAccess('logistics', 'delivery'))
            _MenuItem(
              title: 'View sales order',
              icon: Icons.show_chart_rounded,
              targetScreen: const ViewSalesOrderScreen(),
            ),
          if (_hasAccess('logistics', 'delivery'))
            _MenuItem(
              title: 'Production order tracking',
              icon: Icons.description_outlined,
              targetScreen: const ProductionTrackingProductListScreen(),
            ),
          if (_hasAccess('logistics', 'delivery'))
            _MenuItem(
              title: 'Component products',
              icon: Icons.account_tree_rounded,
              onTap: () => Navigator.pop(context),
            ),
          if (_hasAccess('logistics', 'delivery'))
            _MenuItem(
              title: 'Parent product',
              icon: Icons.view_in_ar_rounded,
              onTap: () => Navigator.pop(context),
            ),
          _MenuItem(
            title: 'End of Day',
            icon: Icons.event_busy_rounded,
            onTap: _startEndOfDayFlow,
          ),
        ];

        final filteredItems =
            menuItems.where((item) => item.title.toLowerCase().contains(query)).toList();

        final theme = Theme.of(context);

        return IndustrialModuleLayout(
          title: 'MANUFACTURING',
          body: Column(
            children: [
              _buildFilters(context, state),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: filteredItems.length,
                  itemBuilder: (context, index) {
                    final item = filteredItems[index];
                    return _buildMenuCard(
                      context,
                      item.title,
                      item.icon,
                      item.targetScreen,
                      onTapOverride: item.onTap,
                      subtitle: item.subtitle,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilters(BuildContext context, ManufacturingState state) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: theme.cardColor,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.search, color: isDark ? Colors.white54 : Colors.black38),
                    hintText: 'Search dashboard...',
                    hintStyle: TextStyle(color: isDark ? Colors.white54 : Colors.black38),
                    filled: true,
                    fillColor: isDark ? Colors.black.withValues(alpha: 0.1) : theme.scaffoldBackgroundColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  onChanged: (value) {
                    context.read<ManufacturingBloc>().add(DashboardSearchChanged(value));
                  },
                ),
              ),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black.withValues(alpha: 0.1) : theme.scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    dropdownColor: isDark ? theme.cardColor : Colors.white,
                    value: state.currentSiteCode ?? 'IPL',
                    hint: Text('Site', style: TextStyle(color: isDark ? Colors.white54 : Colors.black38)),
                    items: [
                      DropdownMenuItem(
                        value: 'IPL',
                        child: Text('IPL - Main', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                      ),
                      DropdownMenuItem(
                        value: 'SFT',
                        child: Text('SFT - Whse', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                      ),
                    ],
                    onChanged: (value) {
                      context.read<ManufacturingBloc>().add(SiteFilterChanged(value));
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context,
    String title,
    IconData icon,
    Widget? targetScreen, {
    VoidCallback? onTapOverride,
    String? subtitle,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    return Material(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(12),
      elevation: isDark ? 0 : 2,
      child: InkWell(
        onTap:
            onTapOverride ??
            (targetScreen != null
                ? () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => targetScreen),
                  )
                : null),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 36, color: orange),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
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
      ),
    );
  }
}
