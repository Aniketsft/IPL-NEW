import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:enterprise_auth_mobile/core/utils/currency_formatter.dart';
import '../../../../../core/widgets/industrial_module_layout.dart';
import '../../../../../core/utils/barcode_scanner/hardware_scanner_mixin.dart';
import '../../../../../core/utils/barcode_scanner/offline_barcode_processor.dart';
import '../../../../../core/network_service.dart';
import '../../../data/repositories/sales_invoice_product_repository.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/si_sales_order_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_bloc.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_state.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_event.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_cart_cubit.dart';
import '../../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../../auth/presentation/bloc/auth_state.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/sales_invoice_product_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/navigation/app_routes.dart';
import 'sales_invoice_product_selection_screen.dart';
import 'add_item_detail_screen.dart';
import 'invoice_preview_screen.dart';
import '../../../domain/models/transaction_config.dart';
import '../../../data/repositories/transaction_history_repository.dart';

class OrderSummaryScreen extends StatefulWidget {
  const OrderSummaryScreen({super.key});

  @override
  State<OrderSummaryScreen> createState() => _OrderSummaryScreenState();
}

class _OrderSummaryScreenState extends State<OrderSummaryScreen> with HardwareScannerMixin {
  final _currencyFormat = CurrencyFormatter.currencyFormat;

  bool _isProcessingScan = false;
  final Map<int, double> _selectedReversalQuantities = {};

  List<Map<String, dynamic>> _linkedCreditNotes = [];
  Map<String, dynamic>? _invoiceRecord;
  String? _creditNoteReason;
  bool _isLoadingReversals = false;
  String? _checkedDocId;

  void _checkReversalStatus(String? docId) {
    if (docId == null || docId.isEmpty || _checkedDocId == docId || _isLoadingReversals) return;
    _isLoadingReversals = true;
    _checkedDocId = docId;
    Future.wait([
      LocalDatabaseHelper.instance.getLinkedCreditNotes(docId),
      LocalDatabaseHelper.instance.getSalesInvoiceById(docId),
      LocalDatabaseHelper.instance.getCreditNoteById(docId),
    ]).then((results) {
      if (mounted) {
        setState(() {
          _linkedCreditNotes = results[0] as List<Map<String, dynamic>>;
          _invoiceRecord = results[1] as Map<String, dynamic>?;
          final cn = results[2] as Map<String, dynamic>?;
          if (cn != null && cn['reason'] != null) {
            _creditNoteReason = cn['reason'] as String?;
          }
          _isLoadingReversals = false;
        });
      }
    }).catchError((_) {
      if (mounted) {
        setState(() {
          _isLoadingReversals = false;
        });
      }
    });
  }

  Future<void> _openCreditNotePreview(BuildContext context, Map<String, dynamic> cnMap) async {
    final cnId = cnMap['creditNoteId']?.toString() ?? '';
    final grandTotal = (cnMap['grandTotal'] as num?)?.toDouble() ?? 0.0;
    final subtotal = (cnMap['subtotal'] as num?)?.toDouble() ?? grandTotal;
    final totalVat = (cnMap['totalVat'] as num?)?.toDouble() ?? 0.0;
    final totalDiscount = (cnMap['totalDiscount'] as num?)?.toDouble() ?? 0.0;
    final customerCode = cnMap['customerCode']?.toString() ?? '';
    final customerName = cnMap['customerName']?.toString() ?? '';
    final reason = cnMap['reason']?.toString() ?? '';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final repo = TransactionHistoryRepository();
      final lines = await repo.getTransactionLines(cnId);
      final customerMap = await LocalDatabaseHelper.instance.getSalesInvoiceCustomerByCode(customerCode);

      if (context.mounted) {
        Navigator.pop(context); // Dismiss loading
        final items = lines.map((item) {
          final originalQty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
          final basePrice = (item['basePrice'] as num?)?.toDouble() ?? ((item['total'] as num?)?.toDouble() ?? 0.0);
          return CartItem(
            product: SalesInvoiceProductModel(
              sku: item['sku'] ?? '',
              name: item['name'] ?? '',
              stockQty: 0.0,
              warehouse: item['warehouse'] ?? '',
              salesUnit: (item['salesUnit'] != null && (item['salesUnit'] as String).isNotEmpty)
                  ? item['salesUnit']
                  : 'EA',
            ),
            lotNumber: item['lotNumber'] ?? '',
            quantity: originalQty > 0 ? originalQty : 1.0,
            basePrice: basePrice,
            discountAmountFlat: (item['discountAmountFlat'] as num?)?.toDouble() ?? 0.0,
            taxRule: item['taxRule'] ?? '',
            vatRatePercent: 0.0,
          );
        }).toList();

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => InvoicePreviewScreen(
              invoiceId: cnId,
              customer: customerMap ?? {'code': customerCode, 'name': customerName},
              subtotal: subtotal,
              discountAmount: totalDiscount,
              vatAmount: totalVat,
              grandTotal: grandTotal,
              paymentMethod: 'CASH REFUND',
              paymentStatus: 'REFUNDED',
              items: items,
              isCreditNote: true,
              creditNoteReason: reason,
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load credit note: $e')),
        );
      }
    }
  }

  void _showLinkedCreditNotesModal(BuildContext context, List<Map<String, dynamic>> notes) {
    if (notes.isEmpty) return;
    if (notes.length == 1) {
      _openCreditNotePreview(context, notes.first);
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                child: Text(
                  'Linked Credit Notes',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: notes.length,
                  itemBuilder: (ctx, i) {
                    final note = notes[i];
                    final cnId = note['creditNoteId']?.toString() ?? '';
                    final total = (note['grandTotal'] as num?)?.toDouble() ?? 0.0;
                    final date = note['createdAt']?.toString() ?? '';
                    return ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.orange,
                        child: Icon(Icons.money_off, color: Colors.white, size: 20),
                      ),
                      title: Text(cnId, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(date.isNotEmpty ? (date.length > 16 ? date.substring(0, 16) : date) : ''),
                      trailing: Text(_currencyFormat.format(total), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                      onTap: () {
                        Navigator.pop(ctx);
                        _openCreditNotePreview(context, note);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _isPartialReversal(String originalDocId, List<CartItem> cartItems) async {
    try {
      final repo = TransactionHistoryRepository();
      final originalLines = await repo.getTransactionLines(originalDocId);
      if (originalLines.isEmpty) return false;

      // 1. If cart has fewer lines than original invoice -> Partial
      if (cartItems.length < originalLines.length) return true;

      // 2. If any original line was previously partially reversed -> Partial
      for (final orig in originalLines) {
        final reversedQty = (orig['reversedQty'] as num?)?.toDouble() ?? 0.0;
        if (reversedQty > 0) return true;
      }

      // 3. If any cart item quantity is less than original quantity -> Partial
      for (final item in cartItems) {
        final match = originalLines.where((l) => (l['sku'] ?? '') == item.product.sku).firstOrNull;
        if (match != null) {
          final origQty = (match['quantity'] as num?)?.toDouble() ?? 0.0;
          if (item.quantity < origQty) return true;
        }
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  void _showQtyInputDialog(BuildContext context, int index, double maxQty) {
    final currentQty = _selectedReversalQuantities[index] ?? maxQty;
    final controller = TextEditingController(
      text: currentQty % 1 == 0 ? currentQty.toInt().toString() : currentQty.toStringAsFixed(2),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Adjust Reversal Quantity'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter quantity to reverse (Max: ${maxQty % 1 == 0 ? maxQty.toInt() : maxQty}):'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: 'Quantity',
                helperText: 'Must be between 1 and ${maxQty % 1 == 0 ? maxQty.toInt() : maxQty}',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () {
              final parsed = double.tryParse(controller.text.trim());
              if (parsed == null || parsed < 1 || parsed > maxQty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Please enter a valid quantity between 1 and ${maxQty % 1 == 0 ? maxQty.toInt() : maxQty}'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              setState(() {
                _selectedReversalQuantities[index] = parsed;
              });
              Navigator.pop(ctx);
            },
            child: const Text('SET QUANTITY'),
          ),
        ],
      ),
    );
  }

  @override
  void onHardwareScan(String data) async {
    if (_isProcessingScan || data.isEmpty) return;
    
    final currentState = context.read<SalesInvoiceBloc>().state;
    if (currentState is SalesInvoiceLoaded && currentState.transactionType == 'VIEW_SI_SALES_ORDER') {
      return; // Do not allow scanning in view mode
    }

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
      final currentState = context.read<SalesInvoiceBloc>().state;
      if (currentState is! SalesInvoiceLoaded) return;
      final cartItems = currentState.cartItems;
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

    return BlocBuilder<SalesInvoiceBloc, SalesInvoiceState>(
      builder: (context, state) {
        if (state is! SalesInvoiceLoaded) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final cartState = state;
        final isPreviewInvoice = cartState.transactionType == 'PREVIEW_INVOICE';
        final isPreviewCreditNote = cartState.transactionType == 'PREVIEW_CREDIT_NOTE' ||
            (cartState.config.mode.isCreditNote &&
                isPreviewInvoice == false &&
                cartState.originalDocumentId != null &&
                cartState.originalDocumentId!.isNotEmpty);

        if (cartState.originalDocumentId != null &&
            cartState.originalDocumentId!.isNotEmpty &&
            _checkedDocId != cartState.originalDocumentId &&
            !_isLoadingReversals) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _checkReversalStatus(cartState.originalDocumentId);
          });
        }

        // Calculate reversal metrics
        final double totalCreditedAmt = _linkedCreditNotes.fold<double>(
          0.0,
          (sum, cn) => sum + ((cn['grandTotal'] as num?)?.toDouble() ?? 0.0),
        );
        final bool isInvoiceFullyReversed = isPreviewInvoice && (
          (_invoiceRecord != null && (_invoiceRecord!['isReversed'] == 1 || _invoiceRecord!['status'] == 'REVERSED')) ||
          _linkedCreditNotes.any((cn) => (cn['isFullReversal'] == 1 || cn['isFullReversal'] == true)) ||
          (_linkedCreditNotes.isNotEmpty && totalCreditedAmt >= (cartState.grandTotal - 0.01))
        );
        final bool isInvoicePartiallyReversed = isPreviewInvoice && !isInvoiceFullyReversed && (
          (_invoiceRecord != null && _invoiceRecord!['isPartiallyReversed'] == 1) ||
          _linkedCreditNotes.isNotEmpty
        );
        final double remainingNetBalance = (cartState.grandTotal - totalCreditedAmt).clamp(0.0, double.infinity);

        final effectiveAbbreviation = (isPreviewInvoice && _selectedReversalQuantities.isNotEmpty)
            ? 'CN'
            : cartState.config.abbreviation;

        return IndustrialModuleLayout(
          title: 'Order Summary [$effectiveAbbreviation]',
          body: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (cartState.customer != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.grey.shade900 : Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isDark ? Colors.blueGrey.shade800 : Colors.blue.shade200,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: theme.primaryColor.withOpacity(0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.person_outline_rounded, color: theme.primaryColor, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (cartState.customer!['name'] ?? '').toString().trim(),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Code: ${(cartState.customer!['code'] ?? '').toString().trim()}  •  Terms: ${(cartState.customer!['paymentTerm'] ?? 'STD').toString().trim()}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark ? Colors.white60 : Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (isInvoiceFullyReversed) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.red.shade400, width: 1.5),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.cancel_outlined, color: Colors.red.shade700, size: 28),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'INVOICE FULLY REVERSED',
                                      style: TextStyle(
                                        color: Colors.red.shade900,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _linkedCreditNotes.isNotEmpty
                                          ? 'Reversed by ${_linkedCreditNotes.map((cn) => cn['creditNoteId']).join(', ')}'
                                          : 'This invoice has been settled and fully reversed.',
                                      style: TextStyle(
                                        color: Colors.red.shade800,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else if (isInvoicePartiallyReversed) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.orange.shade400, width: 1.5),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.pie_chart_outline_rounded, color: Colors.orange.shade800, size: 28),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'PARTIALLY REVERSED INVOICE',
                                      style: TextStyle(
                                        color: Colors.orange.shade900,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Credited: ${_currencyFormat.format(totalCreditedAmt)} • Remaining Balance: ${_currencyFormat.format(remainingNetBalance)}',
                                      style: TextStyle(
                                        color: Colors.orange.shade800,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (cartState.transactionType == 'SI_SALES_ORDER') ...[
                        _buildDeliveryDateCard(context, cartState, isDark),
                        const SizedBox(height: 16),
                      ],
                      Text(
                        'Line Items (${cartState.cartItems.length})',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 12),

                      if (cartState.transactionType == 'CREDIT_NOTE' &&
                          cartState.originalDocumentId != null &&
                          cartState.originalDocumentId!.isNotEmpty)
                        FutureBuilder<bool>(
                          future: _isPartialReversal(cartState.originalDocumentId!, cartState.cartItems),
                          builder: (context, snapshot) {
                            final isPartial = snapshot.data ?? false;
                            if (!isPartial) return const SizedBox.shrink();

                            return Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.orange),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'Converting to Partial Credit Note',
                                    style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                      // Line Items List
                      if (cartState.cartItems.isEmpty)
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
                          itemCount: cartState.cartItems.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = cartState.cartItems[index];
                            return _buildLineItemCard(
                              context,
                              item,
                              index,
                              isDark,
                              cartState,
                            );
                          },
                        ),

                      if (cartState.config.allowCatalogProductAddition) ...[
                        const SizedBox(height: 16),
                        Center(
                          child: TextButton.icon(
                            onPressed: () {
                              final authState = context.read<AuthBloc>().state;
                              final userSiteCode = (authState is Authenticated &&
                                      authState.siteCode != null &&
                                      authState.siteCode!.isNotEmpty &&
                                      authState.siteCode != 'ALL')
                                  ? authState.siteCode!
                                  : 'IPL';

                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      SalesInvoiceProductSelectionScreen(
                                        siteCode: userSiteCode,
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
                    ],
                  ),
                ),
              ),

              // Calculation Section Fixed at Bottom
              Container(
                color: isDark ? theme.colorScheme.surface : Colors.grey[50],
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: _buildCalculationCard(
                  cartState,
                  theme,
                  isDark,
                  isInvoicePartiallyReversed: isInvoicePartiallyReversed,
                  totalCreditedAmt: totalCreditedAmt,
                  remainingNetBalance: remainingNetBalance,
                ),
              ),

              // Action Buttons Container
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
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
                      Builder(
                        builder: (context) {
                          // CASE 1: Viewing a Credit Note (user shall ONLY be able to reprint the receipt)
                          if (isPreviewCreditNote) {
                            return SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => InvoicePreviewScreen(
                                        invoiceId: cartState.originalDocumentId ?? 'N/A',
                                        customer: cartState.customer ?? {},
                                        subtotal: cartState.subtotal,
                                        discountAmount: cartState.totalDiscount,
                                        vatAmount: cartState.totalVat,
                                        grandTotal: cartState.grandTotal,
                                        paymentMethod: 'CASH REFUND',
                                        paymentStatus: 'REFUNDED',
                                        items: cartState.cartItems,
                                        isCreditNote: true,
                                        creditNoteReason: _creditNoteReason,
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(
                                  Icons.print_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                label: const Text(
                                  'Reprint Credit Note Receipt',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange.shade800,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  elevation: 0,
                                ),
                              ),
                            );
                          }

                          // CASE 2: Viewing a Fully Reversed Invoice (user shall NOT reprint invoice, instead view credit note)
                          if (isInvoiceFullyReversed) {
                            return SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  if (_linkedCreditNotes.isNotEmpty) {
                                    _showLinkedCreditNotesModal(context, _linkedCreditNotes);
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('No linked credit note found locally for this reversed invoice.'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(
                                  Icons.receipt_long_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                label: Text(
                                  _linkedCreditNotes.length > 1
                                      ? 'View Linked Credit Notes (${_linkedCreditNotes.length})'
                                      : (_linkedCreditNotes.isNotEmpty
                                          ? 'View Linked Credit Note (${_linkedCreditNotes.first['creditNoteId']})'
                                          : 'View Linked Credit Note'),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange.shade800,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  elevation: 0,
                                ),
                              ),
                            );
                          }

                          // CASE 3: Viewing a Partially Reversed Invoice (dual actions when not actively selecting more items to reverse)
                          if (isInvoicePartiallyReversed && _selectedReversalQuantities.isEmpty) {
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_linkedCreditNotes.isNotEmpty) ...[
                                  SizedBox(
                                    width: double.infinity,
                                    height: 48,
                                    child: ElevatedButton.icon(
                                      onPressed: () => _showLinkedCreditNotesModal(context, _linkedCreditNotes),
                                      icon: const Icon(
                                        Icons.receipt_long_rounded,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                      label: Text(
                                        _linkedCreditNotes.length > 1
                                            ? 'View Credit Notes (${_linkedCreditNotes.length})'
                                            : 'View Credit Note (${_linkedCreditNotes.first['creditNoteId']})',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                          letterSpacing: 1.1,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.orange.shade800,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        elevation: 0,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => InvoicePreviewScreen(
                                            invoiceId: cartState.originalDocumentId ?? 'N/A',
                                            customer: cartState.customer ?? {},
                                            subtotal: cartState.subtotal,
                                            discountAmount: cartState.totalDiscount,
                                            vatAmount: cartState.totalVat,
                                            grandTotal: cartState.grandTotal,
                                            paymentMethod: 'INVOICE',
                                            paymentStatus: 'PAID (PARTIAL REV)',
                                            items: cartState.cartItems,
                                            isCreditNote: false,
                                            isPartiallyReversed: true,
                                            totalCreditedAmount: totalCreditedAmt,
                                            netBalanceDue: remainingNetBalance,
                                          ),
                                        ),
                                      );
                                    },
                                    icon: Icon(
                                      Icons.print_rounded,
                                      color: theme.primaryColor,
                                      size: 18,
                                    ),
                                    label: Text(
                                      'Reprint Invoice (Net ${_currencyFormat.format(remainingNetBalance)})',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: theme.primaryColor,
                                        letterSpacing: 1.1,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(color: theme.primaryColor),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }

                          // CASE 4: Standard Invoice / Credit Note Confirmation or Subsequent Reversal
                          final isCreditNote = cartState.config.mode.isCreditNote ||
                              cartState.config.isReturnOrCreditNote ||
                              cartState.transactionType == 'STANDALONE_CREDIT_NOTE' ||
                              cartState.transactionType == 'CREDIT_NOTE' ||
                              cartState.transactionType == 'RETURN' ||
                              cartState.transactionType == 'CUSTOMER_RETURN';
                          final isZeroAmount = cartState.grandTotal <= 0;
                          final bool showConfirmButton = !cartState.config.requireItemSelectionForAction || _selectedReversalQuantities.isNotEmpty;

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isZeroAmount && cartState.cartItems.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: Text(
                                    isCreditNote
                                        ? ((cartState.transactionType == 'RETURN' || cartState.transactionType == 'CUSTOMER_RETURN')
                                            ? 'Return refund amount must be greater than zero.'
                                            : 'Credit note amount must be greater than zero.')
                                        : 'Invoice amount must be greater than zero.',
                                    style: const TextStyle(
                                      color: Colors.red,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              if (showConfirmButton)
                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: ElevatedButton.icon(
                                    onPressed: (cartState.cartItems.isEmpty || isZeroAmount)
                                        ? null
                                        : () async {
                                        final missingLotItems = cartState.cartItems.where((i) => i.isFoc && i.lotNumber.isEmpty);
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

                                        if (cartState.config.requireItemSelectionForAction) {
                                          final selectedItems = _selectedReversalQuantities.entries.map((e) {
                                            final originalItem = cartState.cartItems[e.key];
                                            return CartItem(
                                              product: originalItem.product,
                                              lotNumber: originalItem.lotNumber,
                                              quantity: e.value,
                                              basePrice: originalItem.basePrice,
                                              discountAmountFlat: originalItem.discountAmountFlat,
                                              taxRule: originalItem.taxRule,
                                              vatRatePercent: originalItem.vatRatePercent,
                                              pricingSource: originalItem.pricingSource,
                                              isFoc: originalItem.isFoc,
                                              warehouse: originalItem.warehouse,
                                            );
                                          }).toList();

                                          final originalCartItems = List<CartItem>.from(cartState.cartItems);
                                          final originalTxType = cartState.transactionType;
                                          final originalConfig = cartState.config;
                                          final originalDocId = cartState.originalDocumentId;

                                          context.read<SalesInvoiceBloc>().add(PrepareReversalCreditNote(
                                            items: selectedItems,
                                            originalInvoiceId: cartState.originalDocumentId ?? '',
                                          ));

                                          await context.push(
                                            AppRoutes.paymentProcessing,
                                            extra: true, // isCreditNoteRefund
                                          );

                                          if (context.mounted) {
                                            final currentCart = context.read<SalesInvoiceBloc>().state;
                                            final bool isCartEmpty = currentCart is! SalesInvoiceLoaded || currentCart.cartItems.isEmpty;
                                            if (isCartEmpty) {
                                              if (Navigator.of(context).canPop()) {
                                                Navigator.of(context).pop(true);
                                              }
                                              return;
                                            }

                                            context.read<SalesInvoiceBloc>().add(RestoreOriginalInvoice(
                                              cartItems: originalCartItems,
                                              transactionType: originalTxType,
                                              config: originalConfig,
                                              originalDocumentId: originalDocId,
                                            ));
                                          }
                                          return;
                                        }

                                        if (cartState.transactionType == 'SI_SALES_ORDER') {
                                          _saveSalesOrder(context, cartState);
                                          return;
                                        }

                                        if (cartState.transactionType == 'VIEW_SI_SALES_ORDER') {
                                          _handleOrderConversion(context, cartState);
                                          return;
                                        }

                                        await context.push(
                                          AppRoutes.paymentProcessing,
                                          extra: isCreditNote,
                                        );
                                        if (context.mounted) {
                                          final currentCart = context.read<SalesInvoiceBloc>().state;
                                          final bool isCartEmpty = currentCart is! SalesInvoiceLoaded || currentCart.cartItems.isEmpty;
                                          if (isCartEmpty && Navigator.of(context).canPop()) {
                                            Navigator.of(context).pop(true);
                                          }
                                        }
                                      },
                                    icon: Icon(
                                      _getConfirmIcon(cartState.config),
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    label: Text(
                                      _getConfirmText(cartState.config, _selectedReversalQuantities.length),
                                      style: const TextStyle(
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
                              if (cartState.config.showReprintButton) ...[
                                if (showConfirmButton) const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      final isCn = (cartState.config.mode.isCreditNote ||
                                              cartState.transactionType == 'PREVIEW_CREDIT_NOTE') &&
                                          cartState.transactionType != 'PREVIEW_INVOICE';
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => InvoicePreviewScreen(
                                            invoiceId: cartState.originalDocumentId ?? 'N/A',
                                            customer: cartState.customer ?? {},
                                            subtotal: cartState.subtotal,
                                            discountAmount: cartState.totalDiscount,
                                            vatAmount: cartState.totalVat,
                                            grandTotal: cartState.grandTotal,
                                            paymentMethod: isCn ? 'CASH REFUND' : 'INVOICE',
                                            paymentStatus: isCn ? 'REFUNDED' : 'PAID',
                                            items: cartState.cartItems,
                                            isCreditNote: isCn,
                                          ),
                                        ),
                                      );
                                    },
                                    icon: Icon(
                                      Icons.print_rounded,
                                      color: theme.primaryColor,
                                      size: 18,
                                    ),
                                    label: Text(
                                      ((cartState.config.mode.isCreditNote ||
                                                  cartState.transactionType == 'PREVIEW_CREDIT_NOTE') &&
                                              cartState.transactionType != 'PREVIEW_INVOICE')
                                          ? 'Reprint Credit Note Receipt'
                                          : 'Reprint Invoice Receipt',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: theme.primaryColor,
                                        letterSpacing: 1.1,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(color: theme.primaryColor),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
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

  IconData _getConfirmIcon(TransactionConfig config) {
    return config.confirmIcon;
  }

  String _getConfirmText(TransactionConfig config, int selectedCount) {
    if (config.requireItemSelectionForAction && selectedCount > 0) {
      return 'Reverse Invoice ($selectedCount ${selectedCount == 1 ? "item" : "items"})';
    }
    return config.confirmButtonText;
  }

  Future<void> _saveSalesOrder(BuildContext context, SalesInvoiceLoaded cartState) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final deliveryDate = cartState.deliveryDate ?? today;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final service = SISalesOrderService();
      await service.saveSalesOrder(
        customer: cartState.customer!,
        items: cartState.cartItems,
        totalAmount: cartState.grandTotal,
        deliveryDate: deliveryDate.toIso8601String(),
      );

      if (context.mounted) {
        Navigator.pop(context); // close dialog
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sales Order saved successfully.'),
            backgroundColor: Colors.green,
          ),
        );
        
        context.read<SalesInvoiceBloc>().add(ClearCart());
        Navigator.pop(context, true); // return true so CustomerSelectionScreen pops back to SalesOrdersListScreen
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // close dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save Sales Order: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleOrderConversion(BuildContext context, SalesInvoiceLoaded cartState) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    // Provide a small delay to simulate processing or allow future stock check API integration
    await Future.delayed(const Duration(milliseconds: 500));

    if (!context.mounted) return;
    Navigator.pop(context);

    // Convert to INVOICE
    context.read<SalesInvoiceBloc>().add(InitializeTransaction(
      transactionType: 'INVOICE',
      originalDocumentId: cartState.originalDocumentId,
    ));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Order converted to Invoice. Please proceed to payment.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Widget _buildDeliveryDateCard(
    BuildContext context,
    SalesInvoiceLoaded cartState,
    bool isDark,
  ) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final deliveryDate = cartState.deliveryDate ?? today;

    final bool isToday = deliveryDate.year == today.year &&
        deliveryDate.month == today.month &&
        deliveryDate.day == today.day;
    final bool isTomorrow = deliveryDate.year == today.add(const Duration(days: 1)).year &&
        deliveryDate.month == today.add(const Duration(days: 1)).month &&
        deliveryDate.day == today.add(const Duration(days: 1)).day;

    String dateSuffix = '';
    if (isToday) {
      dateSuffix = ' (Today)';
    } else if (isTomorrow) {
      dateSuffix = ' (Tomorrow)';
    }

    final formattedDate = '${DateFormat('EEE, dd MMM yyyy').format(deliveryDate)}$dateSuffix';

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.primaryColor.withOpacity(0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _pickDeliveryDate(context, cartState),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.local_shipping_outlined,
                    color: theme.primaryColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DELIVERY DATE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        formattedDate,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[800] : Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.black12,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_month_outlined,
                        size: 16,
                        color: theme.primaryColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Change',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDeliveryDate(BuildContext context, SalesInvoiceLoaded cartState) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final currentSelected = cartState.deliveryDate ?? today;
    final initial = currentSelected.isBefore(today) ? today : currentSelected;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      helpText: 'SELECT DELIVERY DATE',
      confirmText: 'SET DATE',
    );

    if (picked != null && context.mounted) {
      context.read<SalesInvoiceBloc>().add(SetDeliveryDate(picked));
    }
  }

  Widget _buildLineItemCard(
    BuildContext context,
    CartItem item,
    int index,
    bool isDark,
    SalesInvoiceLoaded cartState,
  ) {
    final theme = Theme.of(context);
    final config = cartState.config;
    final isFocMissingLot = item.isFoc && item.lotNumber.isEmpty;
    final isSelected = _selectedReversalQuantities.containsKey(index);
    final selectedQty = _selectedReversalQuantities[index] ?? item.quantity;
    final isViewOnly = !config.canRemoveItems;

    return Material(
      color: isSelected
          ? (isDark ? theme.primaryColor.withOpacity(0.15) : theme.primaryColor.withOpacity(0.06))
          : (isDark ? Colors.grey[900] : Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected ? theme.primaryColor : Colors.grey.withOpacity(0.2),
          width: isSelected ? 2 : 1,
        ),
      ),
      elevation: isDark ? 0 : 0.5,
      shadowColor: Colors.black.withOpacity(0.05),
      child: InkWell(
        onTap: config.requireItemSelectionForAction
            ? () {
                if (isSelected) {
                  _showQtyInputDialog(context, index, item.quantity);
                } else {
                  setState(() {
                    _selectedReversalQuantities[index] = item.quantity;
                  });
                }
              }
            : (isViewOnly
                ? null
                : () {
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
                  }),
        onLongPress: config.requireItemSelectionForAction
            ? () {
                setState(() {
                  if (_selectedReversalQuantities.containsKey(index)) {
                    _selectedReversalQuantities.remove(index);
                  } else {
                    _selectedReversalQuantities[index] = item.quantity;
                  }
                });
              }
            : (isViewOnly
                ? null
                : () {
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
                              context.read<SalesInvoiceBloc>().add(RemoveCartItem(index));
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
                  }),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isSelected)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: theme.primaryColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check, size: 12, color: Colors.white),
                            SizedBox(width: 4),
                            Text(
                              'Selected for Reversal',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'Tap to edit qty',
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: theme.primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
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
              if (config.requireItemSelectionForAction && isSelected) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Qty: ',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, size: 20),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            color: selectedQty > 1 ? theme.primaryColor : Colors.grey,
                            onPressed: selectedQty > 1
                                ? () {
                                    setState(() {
                                      _selectedReversalQuantities[index] = selectedQty - 1;
                                    });
                                  }
                                : null,
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () => _showQtyInputDialog(context, index, item.quantity),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                border: Border.all(color: theme.primaryColor),
                                borderRadius: BorderRadius.circular(4),
                                color: theme.primaryColor.withOpacity(0.12),
                              ),
                              child: Text(
                                selectedQty % 1 == 0 ? selectedQty.toInt().toString() : selectedQty.toStringAsFixed(2),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: theme.primaryColor,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, size: 20),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            color: selectedQty < item.quantity ? theme.primaryColor : Colors.grey,
                            onPressed: selectedQty < item.quantity
                                ? () {
                                    setState(() {
                                      _selectedReversalQuantities[index] = selectedQty + 1;
                                    });
                                  }
                                : null,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '(Max: ${item.quantity % 1 == 0 ? item.quantity.toInt() : item.quantity})',
                            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: 'Total: ',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                          TextSpan(
                            text: _currencyFormat.format(item.basePrice * selectedQty),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: theme.primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ] else ...[
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCalculationCard(
    SalesInvoiceLoaded cart,
    ThemeData theme,
    bool isDark, {
    bool isInvoicePartiallyReversed = false,
    double totalCreditedAmt = 0.0,
    double remainingNetBalance = 0.0,
  }) {
    if (cart.config.requireItemSelectionForAction && _selectedReversalQuantities.isNotEmpty) {
      double revSubtotal = 0.0;
      double revDiscount = 0.0;
      double revVat = 0.0;
      for (final entry in _selectedReversalQuantities.entries) {
        if (entry.key < cart.cartItems.length) {
          final item = cart.cartItems[entry.key];
          final ratio = item.quantity > 0 ? entry.value / item.quantity : 1.0;
          revSubtotal += item.basePrice * entry.value;
          revDiscount += item.discountAmount * ratio;
          revVat += item.vatAmount * ratio;
        }
      }
      final revGrandTotal = revSubtotal - revDiscount + revVat;

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[900] : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.primaryColor.withOpacity(0.5)),
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
            Row(
              children: [
                Icon(Icons.assignment_return_rounded, size: 16, color: theme.primaryColor),
                const SizedBox(width: 6),
                Text(
                  'Reversal Summary (${_selectedReversalQuantities.length} selected)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: theme.primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _buildCalcRow(
              'Reversal Subtotal',
              _currencyFormat.format(revSubtotal),
              isDark: isDark,
            ),
            const SizedBox(height: 4),
            _buildCalcRow(
              'Reversal Discount',
              '-${_currencyFormat.format(revDiscount)}',
              isRed: true,
              isDark: isDark,
            ),
            const SizedBox(height: 4),
            _buildCalcRow(
              'Reversal VAT',
              _currencyFormat.format(revVat),
              isDark: isDark,
            ),
            const SizedBox(height: 6),
            Divider(color: Colors.grey.withOpacity(0.2), height: 1),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Reversal Total',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                Text(
                  _currencyFormat.format(revGrandTotal),
                  textAlign: TextAlign.right,
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
          if (isInvoicePartiallyReversed) ...[
            const SizedBox(height: 4),
            _buildCalcRow(
              'Total Credited',
              '-${_currencyFormat.format(totalCreditedAmt)}',
              isRed: true,
              isDark: isDark,
            ),
          ],
          const SizedBox(height: 8),
          Divider(color: Colors.grey.withOpacity(0.2), height: 1),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  isInvoicePartiallyReversed ? 'Net Balance Due' : 'Grand Total',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              Text(
                _currencyFormat.format(isInvoicePartiallyReversed ? remainingNetBalance : cart.grandTotal),
                textAlign: TextAlign.right,
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
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: isRed
                  ? Colors.red[700]
                  : (isDark ? Colors.grey[300] : Colors.grey[700]),
            ),
          ),
        ),
        Text(
          amount,
          textAlign: TextAlign.right,
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
