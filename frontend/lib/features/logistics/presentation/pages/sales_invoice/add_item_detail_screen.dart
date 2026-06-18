import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../../core/widgets/industrial_module_layout.dart';
import '../../../data/models/sales_invoice_product_model.dart';
import '../../bloc/sales_invoice_cart_cubit.dart';
import '../../../data/models/sales_invoice_item_stock_model.dart';
import '../../../data/local/local_database_helper.dart';
import '../../../domain/services/vat_calculator_service.dart';
import 'lot_selection_screen.dart';

class AddItemDetailScreen extends StatefulWidget {
  final SalesInvoiceProductModel product;
  final CartItem? existingItem;
  final int? editingIndex;

  const AddItemDetailScreen({
    super.key,
    required this.product,
    this.existingItem,
    this.editingIndex,
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

  final TextEditingController _basePriceController = TextEditingController(
    text: '1250.00',
  );
  double get _basePrice => double.tryParse(_basePriceController.text) ?? 0.0;

  double _discountPercent = 0.0;
  final TextEditingController _discountController = TextEditingController(
    text: '0.00',
  );

  double _vatRatePercent = 0.0; // Automatically resolved via VAT Matrix
  String _itemTaxLevel = ''; // Stored from stock/product
  final VatCalculatorService _vatCalculator = VatCalculatorService();

  String _lotNumber = 'LOT-2023-11-892'; // default fallback
  String _warehouse = 'Main (WH-01)';
  String _warehouseName = '';
  String _location = 'A4-S2-B12';
  String _locationType = 'Standard Storage (Pickable)';
  double _lotTotalQty = 0.0;

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
      _loadItemStocks();
    }
  }

  Future<void> _loadSpecificLotStock() async {
    final db = await LocalDatabaseHelper.instance.database;
    final result = await db.query(
      LocalDatabaseHelper.tableSalesInvoiceItemStockDetails,
      where:
          'itemCode = ? AND lotNumber = ? AND location = ? AND warehouse = ?',
      whereArgs: [widget.product.sku, _lotNumber, _location, _warehouse],
    );
    if (result.isNotEmpty) {
      final stock = SalesInvoiceItemStockModel.fromSqlMap(result.first);
      if (mounted) {
        setState(() {
          _lotTotalQty = stock.totalQty;
          _itemTaxLevel = stock.taxLevel;
        });
        _calculateVatRate();
      }
    }
  }

  Future<void> _loadItemStocks() async {
    final db = await LocalDatabaseHelper.instance.database;
    final result = await db.query(
      LocalDatabaseHelper.tableSalesInvoiceItemStockDetails,
      where: 'itemCode = ?',
      whereArgs: [widget.product.sku],
    );
    final stocks = result
        .map((e) => SalesInvoiceItemStockModel.fromSqlMap(e))
        .toList();
    if (mounted && stocks.isNotEmpty) {
      setState(() {
        _lotNumber = stocks.first.lotNumber.isNotEmpty
            ? stocks.first.lotNumber
            : _lotNumber;
        _warehouse = stocks.first.warehouse.isNotEmpty
            ? stocks.first.warehouse
            : _warehouse;
        _warehouseName = stocks.first.warehouseName;
        _location = stocks.first.location.isNotEmpty
            ? stocks.first.location
            : _location;
        _locationType = stocks.first.locationType.isNotEmpty
            ? stocks.first.locationType
            : _locationType;
        _lotTotalQty = stocks.first.totalQty;
        _itemTaxLevel = stocks.first.taxLevel;
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

    final vatRate = await _vatCalculator.resolveVatPercentage(
      customerRule,
      _itemTaxLevel,
    );
    debugPrint('VAT Calc: Resulting Rate=$vatRate');

    if (mounted) {
      setState(() {
        _vatRatePercent = vatRate;
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

  void _updateQuantity(int delta) {
    setState(() {
      int newQty = _quantity + delta;
      if (newQty < 1) newQty = 1;

      // Strict validation against lot quantity
      if (_lotTotalQty > 0 && newQty > _lotTotalQty) {
        newQty = _lotTotalQty.toInt();
        _showStockErrorDialog('Cannot exceed available stock in this lot ($newQty).');
      }

      _quantity = newQty;
      _qtyController.text = _quantity.toString();
    });
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
                                'Total: ${widget.product.stockQty.toInt()} | Lot: ${_lotTotalQty.toInt()}',
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

                  const SizedBox(height: 24),

                  // Dynamic Math Fields
                  Row(
                    children: [
                      Expanded(
                        child: _buildInputField(
                          'Discount %',
                          _discountController,
                          isDark,
                          suffixText: '%',
                          onChanged: (val) {
                            final parsed = double.tryParse(val);
                            if (parsed != null) {
                              setState(() => _discountPercent = parsed);
                            }
                          },
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
                    Text(
                      'Quantity',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[800] : Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          _buildStepperButton(
                            Icons.remove,
                            () => _updateQuantity(-1),
                            isDark,
                          ),
                          Container(
                            width: 48,
                            alignment: Alignment.center,
                            child: TextField(
                              controller: _qtyController,
                              textAlign: TextAlign.center,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              onChanged: (val) {
                                final parsed = int.tryParse(val);
                                if (parsed != null && parsed > 0) {
                                  int updatedQty = parsed;
                                  if (_lotTotalQty > 0 &&
                                      updatedQty > _lotTotalQty) {
                                    _showStockErrorDialog(
                                      'Insufficient stock in this lot (${_lotTotalQty.toInt()} available). Please adjust.',
                                    );
                                  }
                                  setState(() => _quantity = updatedQty);
                                }
                              },
                            ),
                          ),
                          _buildStepperButton(
                            Icons.add,
                            () => _updateQuantity(1),
                            isDark,
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
                          onPressed: () {
                            if (_lotTotalQty > 0 && _quantity > _lotTotalQty) {
                              _showStockErrorDialog(
                                'Cannot proceed: Insufficient stock in this lot (${_lotTotalQty.toInt()} available).',
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
                            );

                            if (widget.editingIndex != null) {
                              context.read<SalesInvoiceCartCubit>().updateItem(
                                widget.editingIndex!,
                                item,
                              );
                              Navigator.of(context).pop();
                            } else {
                              context.read<SalesInvoiceCartCubit>().addItem(
                                item,
                              );
                              // Pop twice (Add Item Screen -> Product Selection Screen -> Order Summary)
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
                          onPressed: () => Navigator.of(context).pop(),
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
    VoidCallback onPressed,
    bool isDark,
  ) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[800] : Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: isDark ? Colors.white : Colors.black87),
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
