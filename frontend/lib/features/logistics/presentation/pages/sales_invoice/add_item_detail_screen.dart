import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../../core/widgets/industrial_module_layout.dart';
import '../../../data/models/sales_invoice_product_model.dart';
import '../../bloc/sales_invoice_cart_cubit.dart';
import '../../../data/models/sales_invoice_item_stock_model.dart';
import '../../../data/local/local_database_helper.dart';
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
  final _currencyFormat = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
  
  int _quantity = 1;
  final TextEditingController _qtyController = TextEditingController(text: '1');
  
  final double _basePrice = 1250.00; // Placeholder until real price API is available
  
  double _discountPercent = 0.0;
  final TextEditingController _discountController = TextEditingController(text: '0.00');
  
  double _vatRatePercent = 20.0; // Standard VAT

  String _lotNumber = 'LOT-2023-11-892'; // default fallback
  String _warehouse = 'Main (WH-01)';
  String _location = 'A4-S2-B12';

  @override
  void initState() {
    super.initState();
    _warehouse = widget.product.warehouse.isNotEmpty ? widget.product.warehouse : 'Main (WH-01)';
    if (widget.existingItem != null) {
      _quantity = widget.existingItem!.quantity;
      _qtyController.text = _quantity.toString();
      _discountPercent = widget.existingItem!.discountPercent;
      _discountController.text = _discountPercent.toString();
      _lotNumber = widget.existingItem!.lotNumber;
      _warehouse = widget.existingItem!.warehouse.isNotEmpty ? widget.existingItem!.warehouse : _warehouse;
      _location = widget.existingItem!.location.isNotEmpty ? widget.existingItem!.location : _location;
    } else {
      _loadItemStocks();
    }
  }

  Future<void> _loadItemStocks() async {
    final db = await LocalDatabaseHelper.instance.database;
    final result = await db.query(
      LocalDatabaseHelper.tableSalesInvoiceItemStockDetails,
      where: 'itemCode = ?',
      whereArgs: [widget.product.sku],
    );
    final stocks = result.map((e) => SalesInvoiceItemStockModel.fromSqlMap(e)).toList();
    if (mounted && stocks.isNotEmpty) {
      setState(() {
        _lotNumber = stocks.first.lotNumber.isNotEmpty ? stocks.first.lotNumber : _lotNumber;
        _warehouse = stocks.first.warehouse.isNotEmpty ? stocks.first.warehouse : _warehouse;
        _location = stocks.first.location.isNotEmpty ? stocks.first.location : _location;
      });
    }
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  void _updateQuantity(int delta) {
    setState(() {
      int newQty = _quantity + delta;
      if (newQty < 1) newQty = 1;
      _quantity = newQty;
      _qtyController.text = _quantity.toString();
    });
  }

  double get _discountAmount => _basePrice * _quantity * (_discountPercent / 100);
  double get _priceAfterDiscount => (_basePrice * _quantity) - _discountAmount;
  double get _vatAmount => _priceAfterDiscount * (_vatRatePercent / 100);

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
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: theme.primaryColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'In Stock: ${widget.product.stockQty.toInt()}',
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
                  const SizedBox(height: 24),
                  
                  // Quantity
                  Text(
                    'Quantity',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildStepperButton(Icons.remove, () => _updateQuantity(-1), isDark),
                      Container(
                        width: 80,
                        height: 48,
                        decoration: BoxDecoration(
                          border: Border.symmetric(
                            horizontal: BorderSide(color: Colors.grey.withOpacity(0.3)),
                          ),
                        ),
                        child: TextField(
                          controller: _qtyController,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            filled: false,
                          ),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                          onChanged: (val) {
                            final parsed = int.tryParse(val);
                            if (parsed != null && parsed > 0) {
                              setState(() => _quantity = parsed);
                            }
                          },
                        ),
                      ),
                      _buildStepperButton(Icons.add, () => _updateQuantity(1), isDark),
                    ],
                  ),
                  const SizedBox(height: 24),

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
                          builder: (context) => LotSelectionScreen(itemCode: widget.product.sku),
                        ),
                      );
                      if (selectedLot != null && selectedLot is SalesInvoiceItemStockModel) {
                        setState(() {
                          _lotNumber = selectedLot.lotNumber;
                          _warehouse = selectedLot.warehouse;
                          _location = selectedLot.location;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _buildReadOnlyField('Warehouse', _warehouse, isDark)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildReadOnlyField('Location', _location, isDark)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildReadOnlyField('Location Type', 'Standard Storage (Pickable)', isDark),
                  const SizedBox(height: 12),
                  _buildReadOnlyField('Base Price', _currencyFormat.format(_basePrice), isDark),
                  
                  const SizedBox(height: 24),

                  // Dynamic Math Fields
                  Row(
                    children: [
                      Expanded(
                        child: _buildInputField('Discount %', _discountController, isDark, suffixText: '%', onChanged: (val) {
                          final parsed = double.tryParse(val);
                          if (parsed != null) {
                            setState(() => _discountPercent = parsed);
                          }
                        }),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildReadOnlyField('Discount Amt', '-${_currencyFormat.format(_discountAmount)}', isDark, isRed: true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDropdownField('VAT Rate', '20.00% (Standard)', isDark),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildReadOnlyField('VAT Amt', '+${_currencyFormat.format(_vatAmount)}', isDark),
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
                )
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 1,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(color: Colors.grey.withOpacity(0.3)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
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
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () {
                      final item = CartItem(
                        product: widget.product,
                        quantity: _quantity,
                        lotNumber: _lotNumber,
                        warehouse: _warehouse,
                        location: _location,
                        basePrice: _basePrice,
                        discountPercent: _discountPercent,
                        vatRatePercent: _vatRatePercent,
                      );
                      
                      if (widget.editingIndex != null) {
                        context.read<SalesInvoiceCartCubit>().updateItem(widget.editingIndex!, item);
                        Navigator.of(context).pop();
                      } else {
                        context.read<SalesInvoiceCartCubit>().addItem(item);
                        // Pop twice (Add Item Screen -> Product Selection Screen -> Order Summary)
                        Navigator.of(context)..pop()..pop();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    child: Text(
                      widget.editingIndex != null ? 'Update Order' : 'Add to Order',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepperButton(IconData icon, VoidCallback onPressed, bool isDark) {
    return InkWell(
      onTap: onPressed,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.withOpacity(0.3)),
          borderRadius: BorderRadius.zero,
        ),
        child: Icon(icon, color: isDark ? Colors.white : Colors.black87),
      ),
    );
  }

  Widget _buildReadOnlyField(String label, String value, bool isDark, {bool isRed = false, IconData? trailingIcon, VoidCallback? onTap}) {
    Widget content = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isRed ? Colors.red[700] : (isDark ? Colors.white : Colors.black87),
                  ),
                  overflow: TextOverflow.ellipsis,
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
          borderRadius: BorderRadius.circular(4),
          child: Ink(
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[800] : Colors.grey[50],
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey.withOpacity(0.3)),
            ),
            child: content,
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.grey[50],
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
      ),
      child: content,
    );
  }

  Widget _buildInputField(String label, TextEditingController controller, bool isDark, {String? suffixText, Function(String)? onChanged}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4, right: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[500],
            ),
          ),
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
        color: isDark ? Colors.grey[800] : Colors.grey[50],
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[500],
            ),
          ),
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
              Icon(Icons.keyboard_arrow_down, color: Colors.grey[500], size: 20),
            ],
          ),
        ],
      ),
    );
  }
}
