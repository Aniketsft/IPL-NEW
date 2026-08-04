import 'package:flutter/material.dart';
import '../../../../core/widgets/industrial_module_layout.dart';

class ReportsScreen extends StatelessWidget {
  final List<String> permissions;

  const ReportsScreen({
    super.key,
    required this.permissions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    final List<Map<String, dynamic>> reportPlaceholders = [
      {
        'title': 'Daily Production Report',
        'icon': Icons.precision_manufacturing_rounded,
        'subtitle': 'View daily manufacturing totals',
      },
      {
        'title': 'Sync Status Report',
        'icon': Icons.sync_rounded,
        'subtitle': 'Review device synchronization logs',
      },
      {
        'title': 'User Activity Report',
        'icon': Icons.people_alt_rounded,
        'subtitle': 'Audit user actions and logins',
      },
      {
        'title': 'Inventory Variance',
        'icon': Icons.inventory_2_rounded,
        'subtitle': 'Discrepancies in stock control',
      }
    ];

    return IndustrialModuleLayout(
      title: 'Reports Dashboard',
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: reportPlaceholders.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final report = reportPlaceholders[index];
          return Card(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            elevation: isDark ? 0 : 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isDark ? Colors.white10 : Colors.black12,
              ),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              leading: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  report['icon'] as IconData,
                  color: theme.primaryColor,
                  size: 24,
                ),
              ),
              title: Text(
                report['title'] as String,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  report['subtitle'] as String,
                  style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black54,
                    fontSize: 13,
                  ),
                ),
              ),
              trailing: Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${report['title']} coming soon!')),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
