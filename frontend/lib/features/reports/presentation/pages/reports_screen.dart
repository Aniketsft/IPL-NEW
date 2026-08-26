import 'package:flutter/material.dart';
import '../../../../core/widgets/industrial_module_layout.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../features/logistics/data/local/local_database_helper.dart';
import '../../../../features/logistics/data/repositories/delivery_repository.dart';
import '../../../../features/manufacturing/logic/eod_pdf_generator.dart';
import '../../../../features/manufacturing/ui/screens/end_of_day_screen.dart'; // For ProductionTrackingItem
import '../../logic/order_completion_pdf_generator.dart';
import '../../logic/sales_delivery_pdf_generator.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/pages/production_tracking_product_list_screen.dart';

class ReportsScreen extends StatefulWidget {
  final List<String> permissions;

  const ReportsScreen({
    super.key,
    required this.permissions,
  });

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool _isLoading = false;

  Future<void> _generateDailyProductionReport() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: Theme.of(context).primaryColor,
              onPrimary: Colors.white,
              surface: const Color(0xFF1E1E1E),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null || !mounted) return;

    // Ask user to choose report type
    final bool? isSummary = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'Report Type',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Select the type of Daily Production Report to generate.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx, false),
            icon: const Icon(Icons.list_alt_rounded, color: Colors.amber),
            label: const Text(
              'Detailed',
              style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
            ),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.summarize_rounded, color: Colors.amber),
            label: const Text(
              'Summary',
              style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (isSummary == null || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final repository = context.read<DeliveryRepository>();
      final db = LocalDatabaseHelper.instance;
      
      final data = await repository.getProductionSummaryFromServer(picked);
      
      final List<ProductionTrackingItem> parsedItems = [];
      for (final e in data) {
         final code = e['itemCode'] as String? ?? '';
         double stdWeight = 0.0;
         if (code.isNotEmpty) {
           final product = await db.getProductByCode(code);
           if (product != null && product[LocalDatabaseHelper.colProdStandardWeight] != null) {
              stdWeight = (product[LocalDatabaseHelper.colProdStandardWeight] as num).toDouble();
           }
         }
         
         parsedItems.add(ProductionTrackingItem(
            soNumber: e['soNumber'] as String? ?? '',
            itemCode: code,
            description: e['description'] as String? ?? '',
            quantity: (e['quantity'] as num?)?.toDouble() ?? 0.0,
            manufactured: (e['manufactured'] as num?)?.toDouble() ?? 0.0,
            lotNumber: e['lotNumber'] as String? ?? '',
            unit: e['unit'] as String? ?? 'KG',
            conversion: (e['conversion'] as num?)?.toDouble() ?? 1.0,
            location: e['location'] as String? ?? 'IPLCH',
            statusLabel: e['statusLabel'] as String? ?? 'A',
            eaQuantity: (e['eaQuantity'] as num?)?.toDouble() ?? 0.0,
            standardWeight: stdWeight,
            processedQuantity: (e['processedQuantity'] as num?)?.toDouble() ?? 0.0,
            unprocessedQuantity: (e['unprocessedQuantity'] as num?)?.toDouble() ?? 0.0,
            processedEaQuantity: (e['processedEaQuantity'] as num?)?.toDouble() ?? 0.0,
            unprocessedEaQuantity: (e['unprocessedEaQuantity'] as num?)?.toDouble() ?? 0.0,
            workOrderNumber: e['workOrderNumber'] as String? ?? '',
            createdAt: e['createdAt'] != null ? DateTime.tryParse(e['createdAt'].toString()) : null,
         ));
      }

      if (parsedItems.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No production data found for this date.')),
          );
        }
        return;
      }

      await EodPdfGenerator.generateAndPrint(
        workOrder: 'Daily Summary',
        productionDate: picked,
        items: parsedItems.where((item) => item.manufactured > 0).toList(),
        isSummary: isSummary,
      );

    } catch (e) {
      debugPrint('Report Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate report: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _generateOrderCompletionReport() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: Theme.of(context).primaryColor,
              onPrimary: Colors.white,
              surface: const Color(0xFF1E1E1E),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null || !mounted) return;

    // Ask user to choose report type
    final bool? isSummary = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'Report Type',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Select the type of Order Completion Report to generate.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx, false),
            icon: const Icon(Icons.list_alt_rounded, color: Colors.amber),
            label: const Text(
              'Detailed',
              style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
            ),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.summarize_rounded, color: Colors.amber),
            label: const Text(
              'Summary',
              style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (isSummary == null || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final db = LocalDatabaseHelper.instance;
      final dateStr = DateFormat('yyyy-MM-dd').format(picked);

      final orderDetails = await db.getSalesOrdersByDeliveryDate(dateStr);

      if (orderDetails.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No orders found for this delivery date.')),
          );
        }
        return;
      }

      await OrderCompletionPdfGenerator.generateAndPrint(
        targetDate: picked,
        orderDetails: orderDetails,
        isSummary: isSummary,
      );

    } catch (e) {
      debugPrint('Report Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate report: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _generateSalesDeliveryReport() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: Theme.of(context).primaryColor,
              onPrimary: Colors.white,
              surface: const Color(0xFF1E1E1E),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() => _isLoading = true);
      try {
        final repository = context.read<DeliveryRepository>();
        final orderDetails = await repository.getStagingReportByDate(picked);

        if (orderDetails.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No sales delivery records found for this date.')),
            );
          }
          return;
        }

        await SalesDeliveryPdfGenerator.generateAndPrint(
          targetDate: picked,
          orderDetails: orderDetails,
        );

      } catch (e) {
        debugPrint('Report Error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to generate report: $e'), backgroundColor: Colors.redAccent),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    final List<Map<String, dynamic>> reportItems = [
      if (widget.permissions.contains('manufacturing.all.read') || widget.permissions.contains('manufacturing.bulk_allocate.read'))
        {
          'title': 'Manufacturing Tracking',
          'icon': Icons.description_outlined,
          'subtitle': 'Track production products and batches',
          'onTap': () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProductionTrackingProductListScreen(permissions: widget.permissions),
            ),
          ),
          'isPdf': false,
        },
      {
        'title': 'Daily Production Report',
        'icon': Icons.precision_manufacturing_rounded,
        'subtitle': 'View daily manufacturing totals',
        'onTap': _generateDailyProductionReport,
        'isPdf': true,
      },
      {
        'title': 'Order Completion Report',
        'icon': Icons.receipt_long_rounded,
        'subtitle': 'View sales orders by delivery date',
        'onTap': _generateOrderCompletionReport,
        'isPdf': true,
      },
      {
        'title': 'Sales Delivery Report',
        'icon': Icons.local_shipping_outlined,
        'subtitle': 'View shipment details by delivery date',
        'onTap': _generateSalesDeliveryReport,
        'isPdf': true,
      },
    ];

    return IndustrialModuleLayout(
      title: 'Reports Dashboard',
      body: Stack(
        children: [
          ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: reportItems.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final report = reportItems[index];
              final isPdf = report['isPdf'] as bool? ?? true;
              
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
                  trailing: isPdf ? Icon(
                    Icons.picture_as_pdf_rounded,
                    size: 20,
                    color: theme.primaryColor,
                  ) : Icon(
                    Icons.chevron_right_rounded,
                    size: 24,
                    color: theme.primaryColor,
                  ),
                  onTap: report['onTap'] as VoidCallback,
                ),
              );
            },
          ),
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}
