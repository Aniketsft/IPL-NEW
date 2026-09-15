import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../../../core/widgets/industrial_module_layout.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/si_sales_order_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_cart_cubit.dart';
import 'customer_selection_screen.dart';
import 'sales_order_details_screen.dart';
import 'order_summary_screen.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/sales_invoice_product_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/sales_invoice_product_repository.dart';
import 'package:enterprise_auth_mobile/core/network_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
class SalesOrdersListScreen extends StatefulWidget {
  const SalesOrdersListScreen({Key? key}) : super(key: key);

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
                    final date = DateTime.parse(order['createdAt']);
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isConverted ? Colors.green.withOpacity(0.3) : Colors.orange.withOpacity(0.3),
                        )
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        title: Text(
                          order['customerName'] ?? 'Unknown Customer',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),
                            Text('Code: ${order['customerCode']}'),
                            Text('Total: Rs ${order['totalAmount'].toStringAsFixed(2)}'),
                            Text('Date: ${DateFormat('dd MMM yyyy, HH:mm').format(date)}'),
                          ],
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isConverted ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            order['status'],
                            style: TextStyle(
                              color: isConverted ? Colors.green : Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SalesOrderDetailsScreen(order: order),
                            ),
                          ).then((_) => _loadOrders()); // Reload on return in case it was converted
                        },
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          context.read<SalesInvoiceCartCubit>().clearCart(transactionType: 'SI_SALES_ORDER');
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CustomerSelectionScreen()),
          ).then((_) => _loadOrders()); // Reload list when returning
        },
        icon: const Icon(Icons.add),
        label: const Text('New Order'),
      ),
    );
  }
}
