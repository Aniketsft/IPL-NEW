import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:enterprise_auth_mobile/core/widgets/industrial_module_layout.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/pages/production_tracking_list_screen.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/pages/view_sales_order_screen.dart';
import '../../bloc/manufacturing_bloc.dart';
import '../../bloc/manufacturing_event.dart';
import '../widgets/sync_progress_dialog.dart';

class ManufacturingScreen extends StatefulWidget {
  final List<String> permissions;

  const ManufacturingScreen({super.key, required this.permissions});

  @override
  State<ManufacturingScreen> createState() => _ManufacturingScreenState();
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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const SyncProgressDialog(),
    );
    context.read<ManufacturingBloc>().add(const SyncDataRequested());
    setState(() {
      _lastSyncStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    });
  }

  @override
  Widget build(BuildContext context) {
    return IndustrialModuleLayout(
      title: 'Manufacturing',
      body: GridView.count(
        padding: const EdgeInsets.all(24),
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.85,
        children: [
          _buildMenuCard(
            context,
            'Data Sync',
            Icons.sync_rounded,
            null,
            onTapOverride: _triggerSync,
            subtitle: 'Last: $_lastSyncStr',
          ),
          if (_hasAccess('manufacturing', 'work_order'))
            _buildMenuCard(
              context,
              'Work order',
              Icons.timer_outlined,
              null, // Placeholder
            ),
          if (_hasAccess('manufacturing', 'view_sales_order'))
            _buildMenuCard(
              context,
              'View sales order',
              Icons.show_chart_rounded,
              const ViewSalesOrderScreen(),
            ),
          if (_hasAccess('manufacturing', 'tracking'))
            _buildMenuCard(
              context,
              'Production order tracking',
              Icons.description_outlined,
              const ProductionTrackingListScreen(),
            ),
          if (_hasAccess('manufacturing', 'components'))
            _buildMenuCard(
              context,
              'Component products',
              Icons.account_tree_rounded,
              null, // Placeholder
            ),
          if (_hasAccess('manufacturing', 'products'))
            _buildMenuCard(
              context,
              'Parent product',
              Icons.view_in_ar_rounded,
              null, // Placeholder
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
    return Material(
      color: const Color(0xFF1E1E1E),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap:
            onTapOverride ??
            (targetScreen != null
                ? () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => targetScreen),
                  )
                : () => ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$title module is coming soon')),
                  )),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white.withOpacity(0.05)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 36, color: const Color(0xFFFF9800)),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
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
                    color: Colors.white.withOpacity(0.5),
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
