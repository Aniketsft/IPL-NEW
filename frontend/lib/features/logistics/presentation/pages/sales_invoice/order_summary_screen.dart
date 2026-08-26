import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../../core/widgets/industrial_module_layout.dart';
import '../../../../../core/utils/barcode_scanner/hardware_scanner_mixin.dart';
import '../../../../../core/utils/barcode_scanner/offline_barcode_processor.dart';
import '../../../../../core/network_service.dart';
import '../../../data/repositories/sales_invoice_product_repository.dart';
import '../../bloc/sales_invoice_cart_cubit.dart';
import 'sales_invoice_product_selection_screen.dart';
import 'add_item_detail_screen.dart';
import 'payment_processing_screen.dart';
import 'invoice_preview_screen.dart';

class OrderSummaryScreen extends StatefulWidget {
  const OrderSummaryScreen({super.key});

  @override
  State<OrderSummaryScreen> createState() => _OrderSummaryScreenState();
}

class _OrderSummaryScreenState extends State<OrderSummaryScreen> with HardwareScannerMixin {
  final _currencyFormat = NumberFormat.currency(
    customPattern: "'Rs ' #,##0.00",
    decimalDigits: 2,
  );

  bool _isProcessingScan = false;

  @override
  void onHardwareScan(String data) async {
    if (_isProcessingScan || data.isEmpty) return;
    
    setState(() => _isProcessingScan = true);
    
    try {
      final processor = OfflineBarcodeProcessor();
      final scanResult = await processor.processBarcode(data);
      
      if (scanResult == null) {
        _showErrorDialog('Product Not Found', 'The scanned barcode could not be identified.');
        return;
      }
      
      final repository = SalesInvoiceProductRepository(context.read<NetworkService>());
      final product = await repository.getProductByItemCode(scanResult.itemCode);
      
      if (product == null) {
        _showErrorDialog('Product Not Found', 'The product is not available in the sales invoice catalog.');
        return;
      }

      // Check if product is already in the cart
      final cartItems = context.read<SalesInvoiceCartCubit>().state.items;
      CartItem? existingItem;
      int? editingIndex;
      for (int i = 0; i < cartItems.length; i++) {
        if (cartItems[i].product.sku == product.sku) {
          existingItem = cartItems[i];
          editingIndex = i;
          break;
        }
      }

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AddItemDetailScreen(
              product: product,
              existingItem: existingItem,
              editingIndex: editingIndex,
            ),
          ),
        );
      }
    } catch (e) {
      _showErrorDialog('Scan Error', 'An error occurred while processing the scan.');
    } finally {
      if (mounted) {
        setState(() => _isProcessingScan = false);
      }
    }
  }

  void _showErrorDialog(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return BlocBuilder<SalesInvoiceCartCubit, SalesInvoiceCartState>(
      builder: (context, cartState) {
        return IndustrialModuleLayout(
          title: 'Order Summary',
          body: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Line Items (${cartState.items.length})',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Line Items List
                      if (cartState.items.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Text(
                              'No items added yet.',
                              style: TextStyle(color: Colors.grey[500]),
                            ),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: cartState.items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final item = cartState.items[index];
                            return _buildLineItemCard(
                              context,
                              item,
                              index,
                              isDark,
                            );
                          },
                        ),

                      const SizedBox(height: 16),
                      Center(
                        child: TextButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const SalesInvoiceProductSelectionScreen(
                                      siteCode: 'IPL',
                                    ),
                              ),
                            );
                          },
                          icon: Icon(
                            Icons.add,
                            color: theme.primaryColor,
                            size: 20,
                          ),
                          label: Text(
                            'ADD PRODUCT',
                            style: TextStyle(
                              color: theme.primaryColor,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 24,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Calculation Section Fixed at Bottom
              Container(
                color: isDark ? theme.colorScheme.surface : Colors.grey[50],
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: _buildCalculationCard(cartState, theme, isDark),
              ),

              // Action Buttons Container
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                decoration: BoxDecoration(
                  color: isDark ? theme.colorScheme.surface : Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: cartState.items.isEmpty
                              ? null
                              : () {
                                  final missingLotItems = cartState.items.where((i) => i.isFoc && i.lotNumber.isEmpty);
                                  if (missingLotItems.isNotEmpty) {
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Missing Lot Number'),
                                        content: const Text('Please assign a lot number to all Free of Charge (FOC) items before confirming.'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx),
                                            child: const Text('OK'),
                                          ),
                                        ],
                                      ),
                                    );
                                    return;
                                  }

                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const PaymentProcessingScreen(),
                                    ),
                                  );
                                },
                          icon: const Icon(
                            Icons.check_circle,
                            color: Colors.white,
                            size: 18,
                          ),
                          label: const Text(
                            'Confirm',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 1.1,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.primaryColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLineItemCard(
    BuildContext context,
    CartItem item,
    int index,
    bool isDark,
  ) {
    final theme = Theme.of(context);
    final isFocMissingLot = item.isFoc && item.lotNumber.isEmpty;

    return Material(
      color: isDark ? Colors.grey[900] : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: Colors.grey.withOpacity(0.2),
          width: 1,
        ),
      ),
      elevation: isDark ? 0 : 0.5,
      shadowColor: Colors.black.withOpacity(0.05),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AddItemDetailScreen(
                product: item.product,
                existingItem: item,
                editingIndex: index,
              ),
            ),
          );
        },
        onLongPress: () {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Remove Product'),
              content: Text(
                'Are you sure you want to remove ${item.product.name} from the order?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('CANCEL'),
                ),
                TextButton(
                  onPressed: () {
                    context.read<SalesInvoiceCartCubit>().removeItem(index);
                    Navigator.pop(ctx);
                  },
                  child: const Text(
                    'REMOVE',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          );
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      item.product.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: _currencyFormat.format(item.basePrice),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        TextSpan(
                          text:
                              ' /${item.product.salesUnit.isNotEmpty ? item.product.salesUnit : 'ea'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'SKU: ${item.product.sku}',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
              if (item.isFoc)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isFocMissingLot ? Colors.orange.withOpacity(0.1) : Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: isFocMissingLot ? Colors.orange : Colors.green),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isFocMissingLot ? Icons.warning_amber_rounded : Icons.check_circle,
                          color: isFocMissingLot ? Colors.orange : Colors.green,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isFocMissingLot ? 'Missing Lot Number - Tap to assign' : 'FOC Applied',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isFocMissingLot ? Colors.orange : Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: 'Qty: ',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        TextSpan(
                          text: '${item.quantity}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: 'Total: ',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        TextSpan(
                          text: _currencyFormat.format(item.total),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: theme.primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCalculationCard(
    SalesInvoiceCartState cart,
    ThemeData theme,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCalcRow(
            'Subtotal',
            _currencyFormat.format(cart.subtotal),
            isDark: isDark,
          ),
          const SizedBox(height: 4),
          _buildCalcRow(
            'Total Discount',
            '-${_currencyFormat.format(cart.totalDiscount)}',
            isRed: true,
            isDark: isDark,
          ),
          const SizedBox(height: 4),
          _buildCalcRow(
            'Total VAT',
            _currencyFormat.format(cart.totalVat),
            isDark: isDark,
          ),
          const SizedBox(height: 8),
          Divider(color: Colors.grey.withOpacity(0.2), height: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Grand Total',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              Text(
                _currencyFormat.format(cart.grandTotal),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: theme.primaryColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCalcRow(
    String label,
    String amount, {
    bool isRed = false,
    required bool isDark,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: isRed
                ? Colors.red[700]
                : (isDark ? Colors.grey[300] : Colors.grey[700]),
          ),
        ),
        Text(
          amount,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isRed
                ? Colors.red[700]
                : (isDark ? Colors.white : Colors.black87),
          ),
        ),
      ],
    );
  }
}
