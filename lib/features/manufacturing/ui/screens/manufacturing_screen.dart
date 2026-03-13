import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:enterprise_auth_mobile/core/widgets/industrial_module_layout.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/pages/production_tracking_product_list_screen.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/pages/view_sales_order_screen.dart';
import '../../bloc/manufacturing_bloc.dart';
import '../../bloc/manufacturing_event.dart';
import '../widgets/sync_progress_dialog.dart';
import '../widgets/processing_simulator_dialog.dart';

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

  Future<void> _startEndOfDayFlow() async {
    // Step 1: Selection of Work Order
    final String? selectedWo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Select Work Order', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: const Text('WO-2026-001', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, 'WO-2026-001'),
              ),
              ListTile(
                title: const Text('WO-2026-002', style: TextStyle(color: Colors.white)),
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
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('Proceed ($selectedWo)', style: const TextStyle(color: Colors.white)),
        content: const Text('Do you want to proceed or close?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CLOSE')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('PROCEED')),
        ],
      ),
    );

    if (confirmProceed != true) return;

    // Step 3: Loading screen for 15 seconds
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProcessingSimulatorDialog(
        title: 'Processing $selectedWo...',
        duration: const Duration(seconds: 15),
      ),
    );

    // Step 4: Error connecting to X3
    if (!mounted) return;
    final bool? retry = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Connection Error', style: TextStyle(color: Colors.redAccent)),
        content: const Text('Error connecting to X3. Do you want to retry?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('RETRY')),
        ],
      ),
    );

    if (retry != true) return;

    // Step 5: Loading screen for 20 seconds
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ProcessingSimulatorDialog(
        title: 'Retrying Connection...',
        duration: Duration(seconds: 20),
      ),
    );

    // Step 6: Final Failure Prompt
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Status', style: TextStyle(color: Colors.redAccent)),
        content: const Text('Process Failed', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _simulateModuleWork(String title) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProcessingSimulatorDialog(
        title: 'Loading $title...',
        duration: const Duration(seconds: 15),
      ),
    );

    if (!mounted) return;
    // Return to home page (main dashboard)
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
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
              null,
              onTapOverride: () => _simulateModuleWork('Work order'),
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
              const ProductionTrackingProductListScreen(),
            ),
          if (_hasAccess('manufacturing', 'components'))
            _buildMenuCard(
              context,
              'Component products',
              Icons.account_tree_rounded,
              null,
              onTapOverride: () => _simulateModuleWork('Component products'),
            ),
          if (_hasAccess('manufacturing', 'products'))
            _buildMenuCard(
              context,
              'Parent product',
              Icons.view_in_ar_rounded,
              null,
              onTapOverride: () => _simulateModuleWork('Parent product'),
            ),
          _buildMenuCard(
            context,
            'End of Day',
            Icons.event_busy_rounded,
            null,
            onTapOverride: _startEndOfDayFlow,
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
                : null),
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
