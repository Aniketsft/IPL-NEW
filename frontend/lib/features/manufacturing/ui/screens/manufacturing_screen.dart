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
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import './end_of_day_screen.dart';

class ManufacturingScreen extends StatefulWidget {
  final List<String> permissions;

  const ManufacturingScreen({super.key, required this.permissions});

  @override
  State<ManufacturingScreen> createState() => _ManufacturingScreenState();
}

class _MenuItem {
  final String title;
  final IconData? icon;
  final Widget? targetScreen;
  final VoidCallback? onTap;
  final String? subtitle;

  _MenuItem({
    required this.title,
    this.icon,
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
      debugPrint("Manufacturing: Error loading last sync: $e");
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
          /*
          if (_hasAccess('logistics', 'delivery'))
            _MenuItem(
              title: 'Work order',
              icon: Icons.timer_outlined,
              onTap: () => Navigator.pop(context),
            ),
          */
          if (_hasAccess('logistics', 'delivery'))
            _MenuItem(
              title: 'View sales order',
              icon: Icons.show_chart_rounded,
              targetScreen: const ViewSalesOrderScreen(),
            ),
          if (_hasAccess('logistics', 'delivery'))
            _MenuItem(
              title: 'Manufacturing Tracking',
              icon: Icons.description_outlined,
              targetScreen: const ProductionTrackingProductListScreen(),
            ),
          /*
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
          */
          _MenuItem(
            title: 'End of Day',
            icon: Icons.event_busy_rounded,
            targetScreen: const EndOfDayScreen(),
          ),
        ];

        final filteredItems =
            menuItems.where((item) => item.title.toLowerCase().contains(query)).toList();

        return IndustrialModuleLayout(
          title: 'MANUFACTURING',
          showLogout: false,
          showPlantName: false,
          extraActions: [
            _buildSchemaSelector(context, state),
          ],
          body: GridView.builder(
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
        );
      },
    );
  }

  Widget _buildSchemaSelector(BuildContext context, ManufacturingState state) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    return Theme(
      data: theme.copyWith(
        canvasColor: isDark ? theme.cardColor : Colors.white,
      ),
      child: Padding(
        padding: const EdgeInsets.only(right: 8.0),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: state.selectedSchema,
            icon: Icon(Icons.keyboard_arrow_down_rounded, color: orange, size: 25),
            style: TextStyle(
              color: orange,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
            items: const [
              DropdownMenuItem(
                value: 'INLPROD',
                child: Text('X3'),
              ),
              DropdownMenuItem(
                value: 'INLDRYRUN',
                child: Text('SC'),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                context.read<ManufacturingBloc>().add(ManufacturingSchemaChanged(value));
              }
            },
          ),
        ),
      ),
    );
  }


  Widget _buildMenuCard(
    BuildContext context,
    String title,
    IconData? icon,
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
              if (icon != null) ...[
                Icon(icon, size: 36, color: orange),
                const SizedBox(height: 16),
              ],
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
