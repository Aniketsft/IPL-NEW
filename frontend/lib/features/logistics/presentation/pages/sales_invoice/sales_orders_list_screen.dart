import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:enterprise_auth_mobile/core/widgets/industrial_module_layout.dart';
import 'package:enterprise_auth_mobile/core/app_theme.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/si_sales_order_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_bloc.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_state.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_event.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_cart_cubit.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/sales_invoice_product_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'package:go_router/go_router.dart';
import 'package:enterprise_auth_mobile/core/navigation/app_routes.dart';
import 'package:enterprise_auth_mobile/core/utils/currency_formatter.dart';

class SalesOrdersListScreen extends StatefulWidget {
  final String? customerCode;
  final String? customerName;

  const SalesOrdersListScreen({
    super.key,
    this.customerCode,
    this.customerName,
  });

  @override
  State<SalesOrdersListScreen> createState() => _SalesOrdersListScreenState();
}

class _SalesOrdersListScreenState extends State<SalesOrdersListScreen> {
  final SISalesOrderService _service = SISalesOrderService();
  List<Map<String, dynamic>> _orders = [];
  bool _isLoading = true;

  String? _effectiveCustomerCode;
  String? _effectiveCustomerName;

  @override
  void initState() {
    super.initState();
    _effectiveCustomerCode = widget.customerCode;
    _effectiveCustomerName = widget.customerName;
    if (_effectiveCustomerCode == null || _effectiveCustomerCode!.isEmpty) {
      try {
        final blocState = context.read<SalesInvoiceBloc>().state;
        if (blocState is SalesInvoiceLoaded && blocState.customer != null) {
          _effectiveCustomerCode = blocState.customer!['code']?.toString() ??
              blocState.customer!['customerCode']?.toString() ??
              blocState.customer!['CustomerNo']?.toString();
          _effectiveCustomerName = blocState.customer!['name']?.toString() ??
              blocState.customer!['customerName']?.toString();
        }
      } catch (_) {}
    }
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() => _isLoading = true);
    try {
      await _service.ensureHardcodedSalesOrderSeeded();
      final orders = await _service.getSalesOrders(customerCode: _effectiveCustomerCode);
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
      title: _effectiveCustomerName != null && _effectiveCustomerName!.isNotEmpty
          ? 'Sales Orders [$_effectiveCustomerCode]'
          : 'Sales Orders',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _orders.isEmpty
              ? Center(
                  child: Text(
                    _effectiveCustomerName != null
                        ? 'No sales orders found for $_effectiveCustomerName.'
                        : 'No sales orders found.',
                    style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.black54,
                      fontSize: 14,
                    ),
                  ),
                )
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
                        onTap: () async {
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (ctx) => const Center(child: CircularProgressIndicator()),
                          );
                          try {
                            final details = await _service.getSalesOrderDetails(order['id'] as int);
                            if (context.mounted) {
                              Navigator.pop(context); // Close loading dialog
                              
                              final bloc = context.read<SalesInvoiceBloc>();
                              bloc.add(ClearCart());
                              
                              // Set transaction type for viewing
                              bloc.add(InitializeTransaction(
                                transactionType: 'VIEW_SI_SALES_ORDER',
                                originalDocumentId: order['id'].toString(),
                              ));
                              
                              bloc.add(SetCustomer({
                                'code': order['customerCode'],
                                'name': order['customerName'],
                              }));

                              if (order['deliveryDate'] != null) {
                                final dt = DateTime.tryParse(order['deliveryDate'].toString());
                                if (dt != null) {
                                  bloc.add(SetDeliveryDate(dt));
                                }
                              }

                              for (final detail in details) {
                                bloc.add(AddCartItem(
                                  CartItem(
                                    product: SalesInvoiceProductModel(
                                      sku: detail['productCode'],
                                      name: detail['productName'],
                                      stockQty: 0,
                                      warehouse: detail['warehouse'] ?? '',
                                      salesUnit: detail['salesUnit'] ?? '',
                                    ),
                                    quantity: detail['quantity'] as double,
                                    basePrice: detail['basePrice'] as double,
                                    discountAmountFlat: detail['discountAmount'] as double,
                                    vatRatePercent: 0,
                                    taxRule: detail['taxRule'] ?? '',
                                    lotNumber: detail['lotNumber'] ?? '',
                                    warehouse: detail['warehouse'] ?? '',
                                    location: detail['location'] ?? '',
                                  )
                                ));
                              }

                              context.push(AppRoutes.orderSummary).then((_) => _loadOrders());
                            }
                          } catch (e) {
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error loading details: $e')),
                              );
                            }
                          }
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
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Total: ',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: isDark ? Colors.white70 : Colors.black87,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    CurrencyFormatter.format((order['totalAmount'] as num?)?.toDouble() ?? 0.0),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: isDark ? AppTheme.primaryAmber : Colors.black87,
                                    ),
                                    textAlign: TextAlign.right,
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
        onPressed: () async {
          final bloc = context.read<SalesInvoiceBloc>();
          bloc.add(ClearCart());
          bloc.add(const InitializeTransaction(
            transactionType: 'SI_SALES_ORDER',
            originalDocumentId: null,
          ));

          if (_effectiveCustomerCode != null && _effectiveCustomerCode!.isNotEmpty) {
            final cust = await LocalDatabaseHelper.instance.getSalesInvoiceCustomerByCode(_effectiveCustomerCode!);
            bloc.add(SetCustomer(cust ?? {
              'code': _effectiveCustomerCode,
              'name': _effectiveCustomerName ?? _effectiveCustomerCode,
              'statusFlag': '1',
              'creditLimit': '0',
              'outstandingBalance': '0',
            }));
            if (context.mounted) {
              await context.push(AppRoutes.orderSummary);
              _loadOrders();
            }
          } else {
            context.push(AppRoutes.customerSelection).then((_) => _loadOrders());
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('New Order'),
      ),
    );
  }
}
