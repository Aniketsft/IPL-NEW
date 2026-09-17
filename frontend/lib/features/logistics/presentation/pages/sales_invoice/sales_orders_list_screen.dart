import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../../../core/widgets/industrial_module_layout.dart';
import 'package:enterprise_auth_mobile/core/app_theme.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/si_sales_order_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_cart_cubit.dart';
import 'customer_selection_screen.dart';
import 'sales_order_details_screen.dart';

class SalesOrdersListScreen extends StatefulWidget {
  const SalesOrdersListScreen({super.key});

  @override
  State<SalesOrdersListScreen> createState() => _SalesOrdersListScreenState();
}

class _SalesOrdersListScreenState extends State<SalesOrdersListScreen> {
  final SISalesOrderService _service = SISalesOrderService();
  List<Map<String, dynamic>> _orders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() => _isLoading = true);
    try {
      await _service.ensureHardcodedSalesOrderSeeded();
      final orders = await _service.getSalesOrders();
      setState(() {
        _orders = orders;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading orders: $e')),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return IndustrialModuleLayout(
      title: 'Sales Orders',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _orders.isEmpty
              ? const Center(child: Text('No Sales Orders found.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _orders.length,
                  itemBuilder: (context, index) {
                    final order = _orders[index];
                    final isConverted = order['status'] == 'Converted';
                    final date = DateTime.tryParse(order['createdAt'] ?? '') ?? DateTime.now();
                    final orderNumber = (order['orderNumber'] as String?)?.isNotEmpty == true
                        ? order['orderNumber'] as String
                        : 'SO-#${order['id']}';
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isConverted
                              ? Colors.green.withValues(alpha: 0.3)
                              : Colors.orange.withValues(alpha: 0.3),
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SalesOrderDetailsScreen(order: order),
                            ),
                          ).then((_) => _loadOrders()); // Reload on return in case it was converted
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Top Row: Sales Number & Status badge
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? Colors.blueGrey.withValues(alpha: 0.25)
                                          : Colors.blueGrey.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isDark
                                            ? Colors.cyan.withValues(alpha: 0.35)
                                            : Colors.blueGrey.withValues(alpha: 0.25),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.receipt_long, 
                                          size: 14, 
                                          color: isDark ? Colors.cyan.shade300 : Colors.blueGrey,
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          orderNumber,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                            color: isDark ? Colors.cyan.shade200 : Colors.blueGrey,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isConverted
                                          ? Colors.green.withValues(alpha: 0.12)
                                          : Colors.orange.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      order['status'] ?? 'Open',
                                      style: TextStyle(
                                        color: isConverted ? Colors.green.shade700 : Colors.orange.shade800,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              // Customer Name
                              Text(
                                order['customerName'] ?? 'Unknown Customer',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(height: 4),
                              // Customer Code
                              Row(
                                children: [
                                  Text(
                                    'Customer Code: ', 
                                    style: TextStyle(color: isDark ? Colors.white60 : Colors.grey, fontSize: 13),
                                  ),
                                  Text(
                                    order['customerCode'] ?? '-',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600, 
                                      fontSize: 13,
                                      color: isDark ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              // Total Amount (Theme-aware with amber highlight)
                              Row(
                                children: [
                                  Text(
                                    'Total: ',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: isDark ? Colors.white70 : Colors.black87,
                                    ),
                                  ),
                                  Text(
                                    'Rs ${(order['totalAmount'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: isDark ? AppTheme.primaryAmber : Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              // Order Date (Theme-aware contrast)
                              Text(
                                'Order Date: ${DateFormat('dd MMM yyyy, HH:mm').format(date)}',
                                style: TextStyle(
                                  fontSize: 12, 
                                  color: isDark ? Colors.white60 : Colors.black54,
                                ),
                              ),
                              // Delivery Date
                              Builder(
                                builder: (context) {
                                  final rawDelivery = order['deliveryDate'] as String?;
                                  final deliveryDt = rawDelivery != null ? DateTime.tryParse(rawDelivery) : null;
                                  if (deliveryDt == null) return const SizedBox.shrink();
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.local_shipping_outlined,
                                          size: 15,
                                          color: isDark ? Colors.teal.shade300 : Colors.teal,
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          'Delivery: ${DateFormat('dd MMM yyyy').format(deliveryDt)}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                            color: isDark ? Colors.teal.shade300 : Colors.teal.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          context.read<SalesInvoiceCartCubit>().clearCart(transactionType: 'SI_SALES_ORDER');
          Navigator.push(
            context,
            MaterialPageRoute(
              settings: const RouteSettings(name: 'CustomerSelectionScreen'),
              builder: (_) => const CustomerSelectionScreen(),
            ),
          ).then((_) => _loadOrders()); // Reload list when returning
        },
        icon: const Icon(Icons.add),
        label: const Text('New Order'),
      ),
    );
  }
}
