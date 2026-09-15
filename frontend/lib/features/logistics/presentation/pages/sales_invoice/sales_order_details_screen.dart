import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../../../core/widgets/industrial_module_layout.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/si_sales_order_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_cart_cubit.dart';
import 'order_summary_screen.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/sales_invoice_product_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/sales_invoice_product_repository.dart';
import 'package:enterprise_auth_mobile/core/network_service.dart';

class SalesOrderDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> order;

  const SalesOrderDetailsScreen({Key? key, required this.order}) : super(key: key);

  @override
  State<SalesOrderDetailsScreen> createState() => _SalesOrderDetailsScreenState();
}

class _SalesOrderDetailsScreenState extends State<SalesOrderDetailsScreen> {
  final SISalesOrderService _service = SISalesOrderService();
  List<Map<String, dynamic>> _details = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() => _isLoading = true);
    try {
      final details = await _service.getSalesOrderDetails(widget.order['id'] as int);
      setState(() {
        _details = details;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading details: $e')),
      );
    }
  }

  Future<void> _handleOrderConversion() async {
    if (widget.order['status'] == 'Converted') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This order has already been converted.')),
      );
      return;
    }

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      // Stock Validation
      final List<String> outOfStockItems = [];
      for (final detail in _details) {
        final productCode = detail['productCode'] as String;
        final requiredQty = detail['quantity'] as double;
        
        final repo = SalesInvoiceProductRepository(context.read<NetworkService>());
        final product = await repo.getProductByItemCode(productCode);
        if (product != null) {
           if (product.stockQty < requiredQty) {
              outOfStockItems.add('${detail['productName']} (Need: $requiredQty, Have: ${product.stockQty})');
           }
        } else {
           outOfStockItems.add('${detail['productName']} (Product not found)');
        }
      }

      if (!mounted) return;
      Navigator.pop(context); // Close loading

      if (outOfStockItems.isNotEmpty) {
        final shouldContinue = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Insufficient Stock'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('The following items are out of stock or have insufficient quantity:'),
                const SizedBox(height: 8),
                ...outOfStockItems.map((e) => Text('• $e', style: const TextStyle(color: Colors.red))),
                const SizedBox(height: 16),
                const Text('Do you want to continue anyway?'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Continue Anyway'),
              ),
            ],
          ),
        );

        if (shouldContinue != true) {
          return;
        }
      }

      // Populate Cubit
      final cubit = context.read<SalesInvoiceCartCubit>();
      cubit.clearCart(
        transactionType: 'INVOICE', 
        sourceSalesOrderId: widget.order['id'] as int,
      );
      
      cubit.setCustomer({
        'code': widget.order['customerCode'],
        'name': widget.order['customerName'],
      });

      for (final detail in _details) {
        cubit.addItem(CartItem(
          product: SalesInvoiceProductModel(
            sku: detail['productCode'],
            name: detail['productName'],
            stockQty: 0, // Ignored in cart calculation
            warehouse: detail['warehouse'] ?? '',
            salesUnit: detail['salesUnit'] ?? '',
          ),
          quantity: detail['quantity'] as double,
          basePrice: detail['basePrice'] as double,
          discountAmountFlat: detail['discountAmount'] as double,
          vatRatePercent: 0, // Will need to be recalculated or loaded properly if tax matrix is used
          taxRule: detail['taxRule'] ?? '',
          lotNumber: detail['lotNumber'] ?? '',
          warehouse: detail['warehouse'] ?? '',
          location: detail['location'] ?? '',
        ));
      }

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const OrderSummaryScreen()),
      ).then((_) => Navigator.pop(context, true)); // Return true to signal list reload

    } catch (e) {
      if (mounted) Navigator.pop(context); // ensure loading is closed
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error preparing conversion: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final isConverted = order['status'] == 'Converted';
    final date = DateTime.parse(order['createdAt']);

    return IndustrialModuleLayout(
      title: 'Order Details',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header Card
                Card(
                  margin: const EdgeInsets.all(16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isConverted ? Colors.green.withOpacity(0.3) : Colors.orange.withOpacity(0.3),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order['customerName'] ?? 'Unknown Customer',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        const SizedBox(height: 8),
                        Text('Code: ${order['customerCode']}'),
                        Text('Date: ${DateFormat('dd MMM yyyy, HH:mm').format(date)}'),
                        const SizedBox(height: 8),
                        Container(
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
                      ],
                    ),
                  ),
                ),
                
                // Details List
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    'Products',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _details.isEmpty
                      ? const Center(child: Text('No products in this order.'))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _details.length,
                          itemBuilder: (context, index) {
                            final detail = _details[index];
                            return Card(
                              child: ListTile(
                                title: Text(detail['productName'] ?? 'Unknown'),
                                subtitle: Text('SKU: ${detail['productCode']} | Qty: ${detail['quantity']} ${detail['salesUnit']}'),
                                trailing: Text('Rs ${detail['total']?.toStringAsFixed(2) ?? '0.00'}'),
                              ),
                            );
                          },
                        ),
                ),
                
                // Total Row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total:',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Rs ${order['totalAmount'].toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                
                // Bottom Button
                if (!isConverted)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: ElevatedButton.icon(
                      onPressed: _handleOrderConversion,
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Convert to Invoice'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
