import 'package:flutter/material.dart';
import '../../../../../core/widgets/industrial_module_layout.dart';
import 'select_transaction_screen.dart';
import 'sales_reports_screen.dart';

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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => screen),
          );
        },
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
        ],
      ),
    );
  }
}
