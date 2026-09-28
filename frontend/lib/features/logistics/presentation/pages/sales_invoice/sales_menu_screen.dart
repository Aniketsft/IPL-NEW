import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../../core/widgets/industrial_module_layout.dart';
import '../../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../../auth/presentation/bloc/auth_state.dart';
import '../../widgets/sales_rep_selection_dialog.dart';
import '../../../data/repositories/sales_invoice_sync_repository.dart';
import 'select_transaction_screen.dart';
import 'sales_reports_screen.dart';
import 'sales_orders_list_screen.dart';

class SalesMenuScreen extends StatelessWidget {
  final List<String> permissions;

  const SalesMenuScreen({
    super.key,
    required this.permissions,
  });

  Widget _buildMenuButton(
    BuildContext context,
    String title,
    IconData icon,
    Widget screen,
  ) {
    return _buildActionButton(
      context,
      title,
      icon,
      () {
        Navigator.push(
          context,
          MaterialPageRoute(
            settings: RouteSettings(name: screen.runtimeType.toString()),
            builder: (_) => screen,
          ),
        );
      },
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    String title,
    IconData icon,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white10 : Colors.black12,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 40,
                  color: theme.primaryColor,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IndustrialModuleLayout(
      title: 'Sales',
      body: GridView.count(
        padding: const EdgeInsets.all(16),
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.9,
        children: [
          _buildMenuButton(
            context,
            'Transaction',
            Icons.shopping_cart_checkout_rounded,
            SelectTransactionScreen(permissions: permissions),
          ),
          _buildMenuButton(
            context,
            'Reports',
            Icons.analytics_rounded,
            SalesReportsScreen(permissions: permissions),
          ),
          _buildMenuButton(
            context,
            'Sales Order',
            Icons.list_alt_rounded,
            const SalesOrdersListScreen(),
          ),
          _buildActionButton(
            context,
            'Sales Reps',
            Icons.badge_rounded,
            () async {
              final authState = context.read<AuthBloc>().state;
              final siteCode = (authState is Authenticated &&
                      authState.siteCode != null &&
                      authState.siteCode!.isNotEmpty &&
                      authState.siteCode != 'ALL')
                  ? authState.siteCode
                  : null;
              final username = authState is Authenticated ? authState.username : null;
              final syncRepo = context.read<SalesInvoiceSyncRepository>();
              await SalesRepSelectionDialog.show(
                context,
                canDismiss: true,
                userSiteCode: siteCode,
                syncRepository: syncRepo,
                username: username,
              );
            },
          ),
        ],
      ),
    );
  }
}
