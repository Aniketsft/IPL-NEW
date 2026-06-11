import 'package:flutter/material.dart';
import '../../../../../core/widgets/industrial_module_layout.dart';
import 'customer_selection_screen.dart';
import 'transaction_history_screen.dart';
class SelectTransactionScreen extends StatelessWidget {
  final List<String> permissions;

  const SelectTransactionScreen({
    super.key,
    required this.permissions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return IndustrialModuleLayout(
      title: 'Select Transaction',
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select Transaction Type',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose the type of transaction you would like to process.',
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 24),
            _buildTransactionCard(
              context: context,
              title: 'Invoice',
              description: 'Standard customer billing and sales processing.',
              icon: Icons.receipt_long_rounded,
              color: theme.primaryColor,
              onTap: () => _showActionPrompt(context, 'Invoice'),
            ),
            const SizedBox(height: 16),
            _buildTransactionCard(
              context: context,
              title: 'Credit Note',
              description: 'Issue credit for overpayments or adjustments.',
              icon: Icons.description_rounded,
              color: theme.primaryColor,
              onTap: () => _showActionPrompt(context, 'Credit Note'),
            ),
            const SizedBox(height: 16),
            _buildTransactionCard(
              context: context,
              title: 'Customer Return',
              description: 'Process inventory returns and customer refunds.',
              icon: Icons.assignment_return_rounded,
              color: theme.primaryColor,
              onTap: () => _showActionPrompt(context, 'Customer Return'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionCard({
    required BuildContext context,
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.black12,
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
          ],
        ),
      ),
    );
  }

  void _showActionPrompt(BuildContext context, String transactionType) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                  child: Text(
                    transactionType,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: Icon(Icons.add_circle_outline_rounded, color: theme.primaryColor),
                  title: const Text('Create New'),
                  onTap: () {
                    Navigator.pop(context); // close bottom sheet
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const CustomerSelectionScreen()),
                    );
                  },
                ),
                ListTile(
                  leading: Icon(Icons.history_rounded, color: theme.primaryColor),
                  title: const Text('View Previous'),
                  onTap: () {
                    Navigator.pop(context); // close bottom sheet
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => TransactionHistoryScreen(
                          transactionType: transactionType,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
