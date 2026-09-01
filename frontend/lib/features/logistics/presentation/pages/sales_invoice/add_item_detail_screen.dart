import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../../core/widgets/industrial_module_layout.dart';
import '../../../data/models/sales_invoice_product_model.dart';
import '../../bloc/sales_invoice_cart_cubit.dart';
import '../../../data/models/sales_invoice_item_stock_model.dart';
import '../../../data/local/local_database_helper.dart';
import '../../../data/repositories/sales_invoice_product_repository.dart';
import '../../../../../core/network_service.dart';
import '../../../domain/services/vat_calculator_service.dart';
import '../../../domain/services/pricing_engine_service.dart';
import 'lot_selection_screen.dart';

class AddItemDetailScreen extends StatefulWidget {
  final SalesInvoiceProductModel product;
  final CartItem? existingItem;
  final int? editingIndex;
  final bool fromProductSelection;

  const AddItemDetailScreen({
    super.key,
    required this.product,
    this.existingItem,
    this.editingIndex,
    this.fromProductSelection = false,
  });

  @override
  State<AddItemDetailScreen> createState() => _AddItemDetailScreenState();
}

class _AddItemDetailScreenState extends State<AddItemDetailScreen> {
  final _currencyFormat = NumberFormat.currency(
    customPattern: "'Rs ' #,##0.00",
    decimalDigits: 2,
  );

  int _quantity = 1;
  final TextEditingController _qtyController = TextEditingController(text: '1');

  final TextEditingController _basePriceController = TextEditingController();
  double get _basePrice => double.tryParse(_basePriceController.text) ?? 0.0;

  double _discountPercent = 0.0;
  final TextEditingController _discountController = TextEditingController(
    text: '0.00',
  );

  double _vatRatePercent = 0.0; // Automatically resolved via VAT Matrix
  String _taxRuleCode = ''; // Tax Code resolved from Matrix
  String _itemTaxLevel = ''; // Stored from stock/product
  final VatCalculatorService _vatCalculator = VatCalculatorService();

  bool _isResolvingPrice = false;
  String _priceSource = '';

  String _lotNumber = ''; // dynamically loaded
  String _warehouse = 'Main (WH-01)';
  String _warehouseName = '';
  String _location = 'A4-S2-B12';
  String _locationType = 'Standard Storage (Pickable)';
  double _lotTotalQty = 0.0;

  bool _hasFoc = false;
  double _focQuantity = 0.0;
  String _focItemSku = '';

  @override
  void initState() {
    super.initState();
    _warehouse = widget.product.warehouse.isNotEmpty
        ? widget.product.warehouse
        : 'Main (WH-01)';
    if (widget.existingItem != null) {
      _quantity = widget.existingItem!.quantity;
      _qtyController.text = _quantity.toString();
      _basePriceController.text = widget.existingItem!.basePrice
          .toStringAsFixed(2);
      _discountPercent = widget.existingItem!.discountPercent;
      _discountController.text = _discountPercent.toString();
      _lotNumber = widget.existingItem!.lotNumber;
      _warehouse = widget.existingItem!.warehouse.isNotEmpty
          ? widget.existingItem!.warehouse
          : _warehouse;
      _warehouseName = widget.existingItem!.warehouseName;
      _location = widget.existingItem!.location.isNotEmpty
          ? widget.existingItem!.location
          : _location;
      _locationType = widget.existingItem!.locationType.isNotEmpty
          ? widget.existingItem!.locationType
          : _locationType;
      _loadSpecificLotStock();
    } else {
      _loadItemStocks().then((_) => _resolvePrice());
    }
  }

  Future<void> _resolvePrice() async {
    final customer = context.read<SalesInvoiceCartCubit>().state.customer;
    if (customer == null) return;

    if (mounted) {
      setState(() => _isResolvingPrice = true);
    }

    final customerCode = customer['code']?.toString() ?? '';
    final bcgcod = customer['bcgcod']?.toString() ?? '';
    final tsccod = customer['tsccod']?.toString() ?? '';
    final facilityFlag = customer['facilityFlag'] != null ? int.tryParse(customer['facilityFlag'].toString()) : null;

    // D1: Defensive validation — log if key pricing dimensions are missing from the customer cache.
    // A missing TSCCOD or BCGCOD means entire categories of pricing rules will silently fail to match.
    if (bcgcod.isEmpty) debugPrint('⚠️ PricingEngine: bcgcod is EMPTY for customer $customerCode — BCGCOD-based rules will not apply.');
    if (tsccod.isEmpty) debugPrint('⚠️ PricingEngine: tsccod is EMPTY for customer $customerCode — TSCCOD-based rules will not apply.');

    try {
      final pricingEngine = PricingEngineService();
      final result = await pricingEngine.resolvePrice(
        customerCode: customerCode,
        bcgcod: bcgcod,
        tsccod: tsccod,
        facilityFlag: facilityFlag,
        sku: widget.product.sku,
        qty: _quantity.toDouble(),
      );

      if (mounted) {
        setState(() {
          // Only auto-fill price if the engine resolved a base price.
          // A result of 0.0 means only a discount rule matched — user must enter price manually.
          if (result.basePrice > 0) {
            _basePriceController.text = result.basePrice.toStringAsFixed(2);
          }
          _discountPercent = result.discountPct;
          _discountController.text = result.discountPct.toString();
          _priceSource = result.source;
          _isResolvingPrice = false;
          _hasFoc = result.hasFoc;
          _focQuantity = result.focQuantity;
          _focItemSku = result.focItemSku;
        });

        if (result.hasFoc && result.focQuantity > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'FOC applied: ${result.focQuantity.toInt()} of ${result.focItemSku} will be added.',
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error resolving price: $e');
      if (mounted) {
        setState(() => _isResolvingPrice = false);
      }
    }
  }

  Future<void> _loadSpecificLotStock() async {
    if (!mounted) return;
    final repository = SalesInvoiceProductRepository(
      context.read<NetworkService>(),
    );
    final stocks = await repository.getSalesInvoiceItemStockDetails(
      widget.product.sku,
    );

    try {
      final stock = stocks.firstWhere(
        (s) =>
            s.lotNumber == _lotNumber &&
            s.location == _location &&
            s.warehouse == _warehouse,
      );

      // Calculate cart deduction for this lot
      final cartItems = context.read<SalesInvoiceCartCubit>().state.items;
      double cartQty = 0;
      for (var item in cartItems) {
        if (item.product.sku == widget.product.sku &&
            item.lotNumber == _lotNumber &&
            item.location == _location &&
            item.warehouse == _warehouse) {
          cartQty += item.quantity;
        }
      }

      if (mounted) {
        setState(() {
          _lotTotalQty = stock.totalQty - cartQty;
          _itemTaxLevel = stock.taxLevel;
        });
        _calculateVatRate();
      }
    } catch (e) {
      debugPrint('Specific lot not found: $e');
    }
  }

  Future<void> _loadItemStocks() async {
    if (!mounted) return;
    final repository = SalesInvoiceProductRepository(
      context.read<NetworkService>(),
    );
    final stocks = await repository.getSalesInvoiceItemStockDetails(
      widget.product.sku,
    );

    if (mounted && stocks.isNotEmpty) {
      final firstStock = stocks.first;

      // Calculate cart deduction for this lot
      final cartItems = context.read<SalesInvoiceCartCubit>().state.items;
      double cartQty = 0;
      for (var item in cartItems) {
        if (item.product.sku == widget.product.sku &&
            item.lotNumber == firstStock.lotNumber &&
            item.location == firstStock.location &&
            item.warehouse == firstStock.warehouse) {
          cartQty += item.quantity;
        }
      }

      setState(() {
        _lotNumber = firstStock.lotNumber.isNotEmpty
            ? firstStock.lotNumber
            : _lotNumber;
        _warehouse = firstStock.warehouse.isNotEmpty
            ? firstStock.warehouse
            : _warehouse;
        _warehouseName = firstStock.warehouseName;
        _location = firstStock.location.isNotEmpty
            ? firstStock.location
            : _location;
        _locationType = firstStock.locationType.isNotEmpty
            ? firstStock.locationType
            : _locationType;
        _lotTotalQty = firstStock.totalQty - cartQty;
        _itemTaxLevel = firstStock.taxLevel;
      });
      _calculateVatRate();
    }
  }

  Future<void> _calculateVatRate() async {
    final customer = context.read<SalesInvoiceCartCubit>().state.customer;
    if (customer == null) {
      debugPrint('VAT Calc: No customer selected');
      return;
    }

    final customerRule = customer['taxRule']?.toString() ?? '';
    debugPrint('VAT Calc: Customer=$customerRule, Item=$_itemTaxLevel');

    final vatDetails = await _vatCalculator.resolveVatDetails(
      customerRule,
      _itemTaxLevel,
    );
    debugPrint(
      'VAT Calc: Resulting Rate=${vatDetails.rate}, Code=${vatDetails.code}',
    );

    if (mounted) {
      setState(() {
        _vatRatePercent = vatDetails.rate;
        _taxRuleCode = vatDetails.code;
      });
    }
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _discountController.dispose();
    _basePriceController.dispose();
    super.dispose();
  }

  double get _maxValidQty {
    double maxQty = _lotTotalQty;
    if (widget.existingItem != null &&
        widget.existingItem!.lotNumber == _lotNumber &&
        widget.existingItem!.warehouse == _warehouse &&
        widget.existingItem!.location == _location) {
      maxQty += widget.existingItem!.quantity;
    }
    return maxQty;
  }

  void _updateQuantity(int change) {
    setState(() {
      int newQty = _quantity + change;
      if (newQty < 1) newQty = 1;

      // Strict validation against maximum valid quantity
      if (_maxValidQty > 0 && newQty > _maxValidQty) {
        _showStockErrorDialog(
          'Insufficient stock in this lot (${_maxValidQty.toInt()} available). Please adjust.',
        );
        return;
      }
      _quantity = newQty;
      _qtyController.text = _quantity.toString();
    });
    _resolvePrice();
  }

  double get _discountAmount =>
      _basePrice * _quantity * (_discountPercent / 100);
  double get _priceAfterDiscount => (_basePrice * _quantity) - _discountAmount;
  double get _vatAmount => _priceAfterDiscount * (_vatRatePercent / 100);

  void _showStockErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stock Warning'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
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

    final bool isFocLocked = widget.existingItem?.isFoc == true;

    final cartItems = context.watch<SalesInvoiceCartCubit>().state.items;
    double totalCartQtyOfProduct = 0;
    for (var item in cartItems) {
      if (item.product.sku == widget.product.sku) {
        totalCartQtyOfProduct += item.quantity;
      }
    }

    final actualTotalStock = widget.product.stockQty - totalCartQtyOfProduct;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.primaryColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Add Item Detail',
          style: TextStyle(
            color: theme.primaryColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product Info Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[900] : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'SKU: ${widget.product.sku}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[500],
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: theme.primaryColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Total: ${actualTotalStock.toInt()} | Lot: ${_lotTotalQty.toInt()}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: theme.primaryColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.product.name,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Placeholder Fields
                  _buildReadOnlyField(
                    'Lot Number',
                    _lotNumber,
                    isDark,
                    trailingIcon: Icons.chevron_right,
                    onTap: () async {
                      final selectedLot = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => LotSelectionScreen(
                            itemCode: widget.product.sku,
                            salesUnit: widget.product.salesUnit,
                          ),
                        ),
                      );
                      if (selectedLot != null &&
                          selectedLot is SalesInvoiceItemStockModel) {
                        setState(() {
                          _lotNumber = selectedLot.lotNumber;
                          _warehouse = selectedLot.warehouse;
                          _warehouseName = selectedLot.warehouseName;
                          _location = selectedLot.location;
                          _locationType = selectedLot.locationType;
                          _lotTotalQty = selectedLot.totalQty;
                          _itemTaxLevel = selectedLot.taxLevel;
                        });
                        _calculateVatRate();
                        // Re-run pricing engine after lot change to keep qty-bracket
                        // and FOC rules consistent with the current quantity.
                        _resolvePrice();
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _buildReadOnlyField(
                            'Warehouse',
                            _warehouse,
                            isDark,
                            suffixText: _warehouseName,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildReadOnlyField(
                            'Location',
                            _location,
                            isDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildReadOnlyField(
                    'Location Type',
                    _locationType.isNotEmpty
                        ? _locationType
                        : 'Standard Storage (Pickable)',
                    isDark,
                  ),
                  const SizedBox(height: 12),
                  _buildInputField(
                    'Base Price',
                    _basePriceController,
                    isDark,
                    prefixText: 'Rs ',
                    onChanged: (val) {
                      setState(() {});
                    },
                  ),
                  if (_isResolvingPrice)
                    const Padding(
                      padding: EdgeInsets.only(top: 4.0),
                      child: Text(
                        'Resolving price...',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    )
                  else if (_priceSource.isNotEmpty && _priceSource != 'MANUAL')
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        'Price auto-filled from pricelist [$_priceSource]',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),

                  const SizedBox(height: 24),

                  // Dynamic Math Fields
                  Row(
                    children: [
                      Expanded(
                        child: _buildReadOnlyField(
                          'Discount %',
                          _discountPercent.toString(),
                          isDark,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildReadOnlyField(
                          'Discount Amt',
                          '-${_currencyFormat.format(_discountAmount)}',
                          isDark,
                          isRed: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildReadOnlyField(
                          'VAT Rate',
                          '${_vatRatePercent.toStringAsFixed(2)}%',
                          isDark,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildReadOnlyField(
                          'VAT Amt',
                          '+${_currencyFormat.format(_vatAmount)}',
                          isDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),

          // Footer Buttons
          Container(
            padding: const EdgeInsets.all(16),
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Quantity Stepper
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          'Total:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _currencyFormat.format((_priceAfterDiscount + _vatAmount)),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: theme.primaryColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Quantity',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.grey[300] : Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 48,
                      width: 144, // Fixed width for nice proportions
                      decoration: BoxDecoration(
                        color: isDark 
                            ? (isFocLocked ? Colors.grey[900]!.withOpacity(0.5) : Colors.grey[800]) 
                            : (isFocLocked ? Colors.grey[200] : Colors.grey[100]),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark 
                              ? (isFocLocked ? Colors.grey[850]! : Colors.grey[700]!) 
                              : (isFocLocked ? Colors.grey[300]! : Colors.grey[300]!),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          _buildStepperButton(
                            Icons.remove,
                            isFocLocked ? null : () => _updateQuantity(-1),
                            isDark,
                            disabled: isFocLocked,
                            isLeft: true,
                          ),
                          Expanded(
                            child: TextField(
                              controller: _qtyController,
                              textAlign: TextAlign.center,
                              keyboardType: TextInputType.number,
                              enabled: !isFocLocked,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                                isDense: true,
                                filled: false,
                                contentPadding: EdgeInsets.zero,
                              ),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: isFocLocked ? Colors.grey : (isDark ? Colors.white : Colors.black),
                              ),
                              onChanged: (val) {
                                final parsed = int.tryParse(val);
                                if (parsed != null && parsed > 0) {
                                  int updatedQty = parsed;
                                  if (_maxValidQty > 0 && updatedQty > _maxValidQty) {
                                    _showStockErrorDialog(
                                      'Insufficient stock in this lot (${_maxValidQty.toInt()} available). Please adjust.',
                                    );
                                  }
                                  setState(() => _quantity = updatedQty);
                                  _resolvePrice();
                                }
                              },
                            ),
                          ),
                          _buildStepperButton(
                            Icons.add,
                            isFocLocked ? null : () => _updateQuantity(1),
                            isDark,
                            disabled: isFocLocked,
                            isLeft: false,
                          ),
                        ],
                      ),
                    ),
                    if (isFocLocked)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Icon(Icons.lock_outline, size: 12, color: Colors.orange[400]),
                            const SizedBox(width: 4),
                            Text(
                              'FOC Locked',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange[400],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),

                // Add/Cancel Buttons
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () async {
                            if (_quantity > _maxValidQty) {
                              _showStockErrorDialog(
                                'Cannot proceed: Insufficient stock in this lot (${_maxValidQty.toInt()} available).',
                              );
                              return;
                            }

                            final item = CartItem(
                              product: widget.product,
                              quantity: _quantity,
                              lotNumber: _lotNumber,
                              warehouse: _warehouse,
                              warehouseName: _warehouseName,
                              location: _location,
                              locationType: _locationType,
                              basePrice: _basePrice,
                              discountPercent: _discountPercent,
                              vatRatePercent: _vatRatePercent,
                              taxRule: _taxRuleCode,
                              isFoc: isFocLocked,
                              pricingSource: _priceSource,
                            );

                            CartItem? focItem;
                            if (!isFocLocked && _hasFoc && _focQuantity > 0) {
                              final bool isSameItem = _focItemSku.isEmpty || _focItemSku == widget.product.sku;
                              
                              String focName = '';
                              String focSalesUnit = 'EA';
                              double focTotalStock = 0.0;
                              
                              if (!isSameItem && _focItemSku.isNotEmpty) {
                                final db = await LocalDatabaseHelper.instance.database;
                                final result = await db.query(
                                  LocalDatabaseHelper.tableSalesInvoiceItemStockDetails,
                                  where: 'itemCode = ?',
                                  whereArgs: [_focItemSku.trim()],
                                  limit: 1,
                                );
                                if (result.isNotEmpty) {
                                  final productRow = result.first;
                                  focName = productRow['itemName']?.toString() ?? '';
                                  focSalesUnit = 'EA';
                                }

                                final sumResult = await db.rawQuery(
                                  'SELECT SUM(totalQty) as total FROM ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails} WHERE itemCode = ?',
                                  [_focItemSku.trim()]
                                );
                                if (sumResult.isNotEmpty && sumResult.first['total'] != null) {
                                  focTotalStock = (sumResult.first['total'] as num).toDouble();
                                }
                              }

                              final focProduct = isSameItem 
                                ? widget.product 
                                : SalesInvoiceProductModel(
                                    sku: _focItemSku,
                                    name: focName,
                                    stockQty: focTotalStock,
                                    warehouse: '',
                                    salesUnit: focSalesUnit,
                                    cce0: '',
                                  );

                              focItem = CartItem(
                                product: focProduct,
                                quantity: _focQuantity.toInt(),
                                lotNumber: isSameItem ? _lotNumber : '',
                                warehouse: isSameItem ? _warehouse : '',
                                warehouseName: isSameItem ? _warehouseName : '',
                                location: isSameItem ? _location : '',
                                locationType: isSameItem ? _locationType : '',
                                basePrice: 0.0,
                                discountPercent: 0.0,
                                vatRatePercent: _vatRatePercent,
                                taxRule: _taxRuleCode,
                                isFoc: true,
                                mainItemSku: widget.product.sku,
                              );
                            }

                            if (!mounted) return;
                            
                            final cartCubit = context.read<SalesInvoiceCartCubit>();

                            if (widget.editingIndex != null) {
                              cartCubit.updateItem(widget.editingIndex!, item);
                              
                              if (focItem != null) {
                                final cartItems = cartCubit.state.items;
                                int existingFocIndex = cartItems.indexWhere((i) => i.isFoc && i.product.sku == focItem!.product.sku);
                                if (existingFocIndex != -1) {
                                  final existingFoc = cartItems[existingFocIndex];
                                  focItem = focItem.copyWith(
                                    lotNumber: existingFoc.lotNumber, 
                                    location: existingFoc.location, 
                                    warehouse: existingFoc.warehouse,
                                    warehouseName: existingFoc.warehouseName,
                                    locationType: existingFoc.locationType
                                  );
                                  cartCubit.updateItem(existingFocIndex, focItem);
                                } else {
                                  cartCubit.addItem(focItem);
                                }
                              }
                              if (widget.fromProductSelection) {
                                Navigator.of(context)..pop()..pop();
                              } else {
                                Navigator.of(context).pop();
                              }
                            } else {
                              cartCubit.addItem(item);
                              if (focItem != null) {
                                cartCubit.addItem(focItem);
                              }
                              Navigator.of(context)
                                ..pop()
                                ..pop();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.primaryColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            widget.editingIndex != null
                                ? 'Update Order'
                                : 'Add to Order',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () {
                            if (widget.editingIndex != null) {
                              Navigator.of(context).pop();
                            } else {
                              Navigator.of(context)
                                ..pop()
                                ..pop();
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: Colors.grey.withOpacity(0.3),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepperButton(
    IconData icon,
    VoidCallback? onPressed,
    bool isDark, {
    bool disabled = false,
    bool isLeft = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: disabled ? null : onPressed,
        borderRadius: BorderRadius.horizontal(
          left: isLeft ? const Radius.circular(11) : Radius.zero,
          right: !isLeft ? const Radius.circular(11) : Radius.zero,
        ),
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          child: Icon(
            icon, 
            color: disabled 
                ? (isDark ? Colors.grey[700] : Colors.grey[400]) 
                : (isDark ? Colors.white : Colors.black87),
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildReadOnlyField(
    String label,
    String value,
    bool isDark, {
    bool isRed = false,
    IconData? trailingIcon,
    VoidCallback? onTap,
    String? suffixText,
  }) {
    Widget content = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isRed
                            ? Colors.red[700]
                            : (isDark ? Colors.white : Colors.black87),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (suffixText != null && suffixText.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        suffixText,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.blueGrey[400],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailingIcon != null)
                Icon(trailingIcon, color: Colors.grey[500], size: 20),
            ],
          ),
        ],
      ),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Ink(
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[850] : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.withOpacity(0.2)),
            ),
            child: content,
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: content,
    );
  }

  Widget _buildInputField(
    String label,
    TextEditingController controller,
    bool isDark, {
    String? prefixText,
    String? suffixText,
    Function(String)? onChanged,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(left: 12, top: 8, bottom: 4, right: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: onChanged,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
            decoration: InputDecoration(
              filled: false,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              prefixText: prefixText,
              prefixStyle: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
              suffixText: suffixText,
              suffixStyle: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownField(String label, String value, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down,
                color: Colors.grey[500],
                size: 20,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
