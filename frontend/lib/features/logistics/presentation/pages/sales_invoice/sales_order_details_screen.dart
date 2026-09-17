import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../../../core/widgets/industrial_module_layout.dart';
import 'package:enterprise_auth_mobile/core/app_theme.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/si_sales_order_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_cart_cubit.dart';
import 'order_summary_screen.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/sales_invoice_product_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/sales_invoice_product_repository.dart';
import 'package:enterprise_auth_mobile/core/network_service.dart';

class SalesOrderDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> order;

  const SalesOrderDetailsScreen({super.key, required this.order});

  @override
  State<SalesOrderDetailsScreen> createState() => _SalesOrderDetailsScreenState();
}

class _SalesOrderDetailsScreenState extends State<SalesOrderDetailsScreen> {
  final SISalesOrderService _service = SISalesOrderService();
  List<Map<String, dynamic>> _details = [];
  bool _isLoading = true;
  String? _currentDeliveryDate;

  @override
  void initState() {
    super.initState();
    _currentDeliveryDate = widget.order['deliveryDate'] as String?;
    _loadDetails();
  }

  Future<void> _editDeliveryDate() async {
    if (widget.order['status'] == 'Converted') return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime initial = today;
    if (_currentDeliveryDate != null) {
      final parsed = DateTime.tryParse(_currentDeliveryDate!);
      if (parsed != null && !parsed.isBefore(today)) {
        initial = parsed;
      }
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      helpText: 'UPDATE DELIVERY DATE',
      confirmText: 'UPDATE',
    );

    if (picked != null && mounted) {
      final formattedIso = picked.toIso8601String();
      try {
        await _service.updateDeliveryDate(widget.order['id'] as int, formattedIso);
        setState(() {
          _currentDeliveryDate = formattedIso;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Delivery date updated to ${DateFormat('dd MMM yyyy').format(picked)}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update delivery date: $e')),
          );
        }
      }
    }
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final order = widget.order;
    final isConverted = order['status'] == 'Converted';
    final date = DateTime.tryParse(order['createdAt'] ?? '') ?? DateTime.now();
    final orderNumber = (order['orderNumber'] as String?)?.isNotEmpty == true
        ? order['orderNumber'] as String
        : 'SO-#${order['id']}';

    final subtotal = _details.fold<double>(
      0.0,
      (sum, item) => sum + (((item['basePrice'] as num?)?.toDouble() ?? 0.0) * ((item['quantity'] as num?)?.toDouble() ?? 0.0)),
    );
    final totalVat = _details.fold<double>(
      0.0,
      (sum, item) => sum + ((item['vatAmount'] as num?)?.toDouble() ?? 0.0),
    );

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
                      color: isConverted
                          ? Colors.green.withValues(alpha: 0.3)
                          : Colors.orange.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Sales Order Number & Status
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                                    size: 16, 
                                    color: isDark ? Colors.cyan.shade300 : Colors.blueGrey,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    orderNumber,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: isDark ? Colors.cyan.shade200 : Colors.blueGrey,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                        const SizedBox(height: 12),
                        // Customer Name
                        Text(
                          order['customerName'] ?? 'Unknown Customer',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
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
                        Text(
                          'Order Date: ${DateFormat('dd MMM yyyy, HH:mm').format(date)}',
                          style: TextStyle(
                            fontSize: 13, 
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Builder(
                          builder: (context) {
                            final deliveryDt = _currentDeliveryDate != null 
                                ? DateTime.tryParse(_currentDeliveryDate!) 
                                : null;
                            return InkWell(
                              onTap: isConverted ? null : _editDeliveryDate,
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.teal.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.teal.withValues(alpha: 0.25)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.local_shipping_outlined, 
                                      size: 16, 
                                      color: isDark ? Colors.teal.shade300 : Colors.teal,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      deliveryDt != null 
                                          ? 'Delivery: ${DateFormat('EEE, dd MMM yyyy').format(deliveryDt)}'
                                          : 'Delivery: Not set',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        color: isDark ? Colors.teal.shade300 : Colors.teal.shade800,
                                      ),
                                    ),
                                    if (!isConverted) ...[
                                      const SizedBox(width: 6),
                                      Icon(
                                        Icons.edit, 
                                        size: 13, 
                                        color: isDark ? Colors.teal.shade300 : Colors.teal,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
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
                            final qty = (detail['quantity'] as num?)?.toDouble() ?? 0.0;
                            final unit = (detail['salesUnit'] as String?)?.trim().isNotEmpty == true
                                ? detail['salesUnit'] as String
                                : 'EA';
                            final price = (detail['basePrice'] as num?)?.toDouble() ?? 0.0;
                            final lineTotal = (detail['total'] as num?)?.toDouble() ?? (qty * price);
                            
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                title: Text(
                                  detail['productName'] ?? 'Unknown Product',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  'SKU: ${detail['productCode']} • Qty: ${qty.toStringAsFixed(0)} $unit @ Rs ${price.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark ? Colors.white70 : Colors.black54,
                                  ),
                                ),
                                trailing: Text(
                                  'Rs ${lineTotal.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold, 
                                    fontSize: 14,
                                    color: isDark ? AppTheme.primaryAmber : Colors.black87,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                
                // Total Summary Card (Dark Theme Industrial Surface)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.grey.shade300,
                    ),
                  ),
                  child: Column(
                    children: [
                      if (totalVat > 0) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Excl. Tax:', 
                              style: TextStyle(
                                color: isDark ? Colors.white70 : Colors.black54, 
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              'Rs ${subtotal.toStringAsFixed(2)}', 
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'VAT:', 
                              style: TextStyle(
                                color: isDark ? Colors.white70 : Colors.black54, 
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              'Rs ${totalVat.toStringAsFixed(2)}', 
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        Divider(
                          height: 16, 
                          color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade300,
                        ),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total Amount:',
                            style: TextStyle(
                              fontSize: 16, 
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          Text(
                            'Rs ${(order['totalAmount'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                            style: TextStyle(
                              fontSize: 18, 
                              fontWeight: FontWeight.bold, 
                              color: isDark ? AppTheme.primaryAmber : Colors.blueGrey,
                            ),
                          ),
                        ],
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
