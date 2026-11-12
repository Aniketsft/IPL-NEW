import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../../auth/presentation/bloc/auth_state.dart';
import 'package:intl/intl.dart';
import 'package:enterprise_auth_mobile/core/utils/currency_formatter.dart';
import 'dart:async';
import '../../../data/models/sales_invoice_product_model.dart';
import '../../bloc/sales_invoice_cart_cubit.dart'; // Keep for CartItem
import '../../bloc/sales_invoice_bloc.dart';
import '../../bloc/sales_invoice_event.dart';
import '../../bloc/sales_invoice_state.dart';
import '../../../data/models/sales_invoice_item_stock_model.dart';
import '../../../data/local/local_database_helper.dart';
import '../../../data/repositories/sales_invoice_product_repository.dart';
import '../../../../../core/network_service.dart';
import '../../../domain/services/vat_calculator_service.dart';
import '../../../domain/services/pricing_engine_service.dart';
import '../../../domain/models/transaction_config.dart';
import '../../../../../core/secure_storage_service.dart';
import '../../../../../core/services/device_info_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/widgets/industrial_numeric_keypad.dart';
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
  final _currencyFormat = CurrencyFormatter.currencyFormat;

  String _formatQty(num val) =>
      val % 1 == 0 ? val.toInt().toString() : val.toStringAsFixed(2);

  int _quantity = 0;
  final TextEditingController _qtyController = TextEditingController();
  final FocusNode _qtyFocusNode = FocusNode();

  final TextEditingController _basePriceController = TextEditingController();
  double get _basePrice => double.tryParse(_basePriceController.text) ?? 0.0;

  double _discountPercent = 0.0;
  final TextEditingController _discountController = TextEditingController(
    text: '0.00',
  );
  final TextEditingController _discountAmtController = TextEditingController(
    text: '0.00',
  );
  final FocusNode _discountFocusNode = FocusNode();
  final FocusNode _discountAmtFocusNode = FocusNode();
  bool _isManualDiscount = false;

  double _vatRatePercent = 0.0; // Automatically resolved via VAT Matrix
  String _taxRuleCode = ''; // Tax Code resolved from Matrix
  String _itemTaxLevel = ''; // Stored from stock/product
  final VatCalculatorService _vatCalculator = VatCalculatorService();

  bool _isResolvingPrice = false;
  String _priceSource = '';
  double _discountAmountFlat = 0.0;
  String _priceListCode = '';
  int _reasonType = 0;

  String _lotNumber = ''; // dynamically loaded
  String _warehouse = '';
  String _warehouseName = '';
  String _location = '';
  String _locationType = '';
  double _lotTotalQty = 0.0;

  bool _hasFoc = false;
  double _focQuantity = 0.0;
  String _focItemSku = '';

  Timer? _debounce;
  String? _cachedSiteCode;
  final PricingEngineService _pricingEngine = PricingEngineService();

  double _originalInvoicedQty = 0.0;
  bool _isKeypadExpanded = true;

  TransactionConfig get _txConfig {
    try {
      final state = context.read<SalesInvoiceBloc>().state;
      if (state is SalesInvoiceLoaded) {
        return state.config;
      }
    } catch (_) {}
    return TransactionConfig.forType('INVOICE');
  }

  bool get _isReturnMode => _txConfig.isReturnOrCreditNote;
  bool get _enforceLimit => _txConfig.enforceOriginalQtyLimit;

  @override
  void initState() {
    super.initState();
    _warehouse = widget.product.warehouse.isNotEmpty
        ? widget.product.warehouse
        : (DeviceInfoService.instance.assignedWarehouse ?? '');
    _location = DeviceInfoService.instance.assignedLocation ?? '';
    _isKeypadExpanded = widget.existingItem == null;
    if (widget.existingItem != null) {
      _quantity = widget.existingItem!.quantity.toInt();
      _originalInvoicedQty = widget.existingItem!.quantity;
      _qtyController.text = _formatQty(widget.existingItem!.quantity);
      _basePriceController.text = widget.existingItem!.basePrice
          .toStringAsFixed(2);
      _discountPercent = widget.existingItem!.discountPercent;
      _discountController.text = _discountPercent.toString();
      final initDiscAmt = widget.existingItem!.basePrice *
          widget.existingItem!.quantity *
          (_discountPercent / 100);
      _discountAmtController.text = initDiscAmt.toStringAsFixed(2);
      if (widget.existingItem!.pricingSource == 'MANUAL') {
        _isManualDiscount = true;
      }
      _vatRatePercent = widget.existingItem!.vatRatePercent;
      _taxRuleCode = widget.existingItem!.taxRule;
      _priceSource = widget.existingItem!.pricingSource;
      _priceListCode = widget.existingItem!.priceListCode;
      _discountAmountFlat = widget.existingItem!.discountAmountFlat;
      _reasonType = widget.existingItem!.reasonType;
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
      if (!_isReturnMode) {
        _loadSpecificLotStock();
      }
    } else {
      _quantity = 0;
      _qtyController.text = '';
      if (!_isReturnMode) {
        _loadItemStocks().then((_) => _resolvePrice());
      }
    }

    _discountFocusNode.addListener(() {
      if (_discountFocusNode.hasFocus) {
        _discountController.clear();
      } else {
        if (_discountController.text.trim().isEmpty) {
          _discountController.text = _discountPercent.toStringAsFixed(_discountPercent % 1 == 0 ? 0 : 2);
        }
      }
    });
    _discountAmtFocusNode.addListener(() {
      if (_discountAmtFocusNode.hasFocus) {
        _discountAmtController.clear();
      } else {
        if (_discountAmtController.text.trim().isEmpty) {
          final lineGross = _basePrice * _quantity;
          final amt = lineGross * (_discountPercent / 100.0);
          _discountAmtController.text = amt.toStringAsFixed(2);
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _qtyFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _qtyController.dispose();
    _qtyFocusNode.dispose();
    _basePriceController.dispose();
    _discountController.dispose();
    _discountAmtController.dispose();
    _discountFocusNode.dispose();
    _discountAmtFocusNode.dispose();
    PricingEngineService.clearCache();
    super.dispose();
  }

  Future<void> _resolvePrice({bool immediate = false, bool forceRefresh = false}) async {
    if (_isReturnMode) return;

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    if (immediate) {
      _resolvePriceNow(forceRefresh: forceRefresh);
    } else {
      _debounce = Timer(const Duration(milliseconds: 200), () => _resolvePriceNow(forceRefresh: forceRefresh));
    }
  }

  Future<void> _resolvePriceNow({bool forceRefresh = false}) async {
    final state = context.read<SalesInvoiceBloc>().state;
    final customer = state is SalesInvoiceLoaded ? state.customer : null;
    if (customer == null) return;

    if (mounted) {
      setState(() => _isResolvingPrice = true);
    }

    final customerCode = customer['code']?.toString() ?? '';
    final bcgcod = customer['bcgcod']?.toString() ?? '';
    final tsccod = customer['tsccod']?.toString() ?? '';
    final bpcsho = (customer['bpcsho'] ?? customer['Bpcsho'])?.toString() ?? '';
    final int? facilityFlag = customer['facilityFlag'] != null
        ? int.tryParse(customer['facilityFlag'].toString())
        : (customer['FacilityFlag'] != null
            ? int.tryParse(customer['FacilityFlag'].toString())
            : null);

    try {
      _cachedSiteCode ??= await SecureStorageService().getSiteCode();
      final siteCode = _cachedSiteCode;
      final result = await _pricingEngine.resolvePrice(
        customerCode: customerCode,
        bcgcod: bcgcod,
        tsccod: tsccod,
        bpcsho: bpcsho,
        facilityFlag: facilityFlag,
        sku: widget.product.sku,
        qty: _quantity > 0 ? _quantity.toDouble() : 1.0,
        siteCode: siteCode,
        forceRefresh: forceRefresh,
      );

      if (mounted) {
        final bool focTransitioned = (!_hasFoc && result.hasFoc) || (_focQuantity != result.focQuantity && result.hasFoc);
        setState(() {
          _basePriceController.text = result.basePrice.toStringAsFixed(2);
          if (!_isManualDiscount) {
            _discountPercent = result.discountPct.clamp(0.0, 5.0);
            _discountController.text = _discountPercent.toString();
            final initDiscAmt = result.basePrice * _quantity * (_discountPercent / 100);
            _discountAmtController.text = initDiscAmt.toStringAsFixed(2);
            _discountAmountFlat = result.discountAmountFlat;
            _priceSource = result.source;
          } else {
            if (_discountPercent > 5.0) {
              _discountPercent = 5.0;
              _discountController.text = '5.00';
            }
            final lineGross = result.basePrice * _quantity;
            final amt = lineGross * (_discountPercent / 100.0);
            _discountAmtController.text = amt.toStringAsFixed(2);
          }
          _priceListCode = result.priceListCode;
          _reasonType = result.reasonType;
          _isResolvingPrice = false;
          _hasFoc = result.hasFoc;
          _focQuantity = result.focQuantity;
          _focItemSku = result.focItemSku;
        });

        if (focTransitioned && result.focQuantity > 0) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'FOC applied: ${result.focQuantity} of ${result.focItemSku} will be added.',
              ),
              duration: const Duration(seconds: 2),
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

      final state = context.read<SalesInvoiceBloc>().state;
      final cartItems = state is SalesInvoiceLoaded ? state.cartItems : <CartItem>[];
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

      final state = context.read<SalesInvoiceBloc>().state;
      final cartItems = state is SalesInvoiceLoaded ? state.cartItems : <CartItem>[];
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
    } else if (mounted) {
      _calculateVatRate();
    }
  }

  Future<void> _calculateVatRate() async {
    final state = context.read<SalesInvoiceBloc>().state;
    final customer = state is SalesInvoiceLoaded ? state.customer : null;
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

  bool get _isSalesOrder {
    try {
      final state = context.read<SalesInvoiceBloc>().state;
      return state is SalesInvoiceLoaded && state.transactionType == 'SI_SALES_ORDER';
    } catch (_) {
      return false;
    }
  }

  double get _maxValidQty {
    if (_enforceLimit) return _originalInvoicedQty;

    double maxQty = _lotTotalQty;
    if (widget.existingItem != null &&
        widget.existingItem!.lotNumber == _lotNumber &&
        widget.existingItem!.warehouse == _warehouse &&
        widget.existingItem!.location == _location) {
      maxQty += widget.existingItem!.quantity;
    }
    return maxQty;
  }

  void _syncDiscountAmtFromPercent() {
    final lineGross = _basePrice * _quantity;
    if (_discountPercent > 5.0) {
      _discountPercent = 5.0;
      _discountController.text = '5.00';
    }
    final amt = lineGross * (_discountPercent / 100.0);
    _discountAmtController.text = amt.toStringAsFixed(2);
  }

  void _onDiscountPercentChanged(String val) {
    _isManualDiscount = true;
    final trimmed = val.trim();
    if (trimmed.isEmpty) {
      _discountPercent = 0.0;
      _discountAmtController.text = '';
      setState(() {});
      return;
    }
    final parsedPct = double.tryParse(trimmed);
    if (parsedPct == null) {
      _discountPercent = 0.0;
      _discountAmtController.text = '';
      setState(() {});
      return;
    }

    final lineGross = _basePrice * _quantity;
    if (parsedPct > 5.0) {
      _discountPercent = 5.0;
      _discountController.value = const TextEditingValue(
        text: '5.00',
        selection: TextSelection.collapsed(offset: 4),
      );
      final amt = lineGross * 0.05;
      _discountAmtController.text = amt.toStringAsFixed(2);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum discount allowed is 5%'),
          duration: Duration(seconds: 2),
        ),
      );
    } else if (parsedPct < 0.0) {
      _discountPercent = 0.0;
      _discountController.value = const TextEditingValue(
        text: '0.00',
        selection: TextSelection.collapsed(offset: 4),
      );
      _discountAmtController.text = '0.00';
    } else {
      _discountPercent = parsedPct;
      final amt = lineGross * (_discountPercent / 100.0);
      _discountAmtController.text = amt.toStringAsFixed(2);
    }
    setState(() {});
  }

  void _onDiscountAmtChanged(String val) {
    _isManualDiscount = true;
    final trimmed = val.trim();
    final lineGross = _basePrice * _quantity;
    if (trimmed.isEmpty || lineGross <= 0) {
      _discountPercent = 0.0;
      _discountController.text = '';
      setState(() {});
      return;
    }
    final parsedAmt = double.tryParse(trimmed);
    if (parsedAmt == null) {
      _discountPercent = 0.0;
      _discountController.text = '';
      setState(() {});
      return;
    }

    final maxAllowedAmt = double.parse((lineGross * 0.05).toStringAsFixed(2));
    if (parsedAmt > maxAllowedAmt) {
      _discountPercent = 5.0;
      _discountController.text = '5.00';
      final maxAmtStr = maxAllowedAmt.toStringAsFixed(2);
      _discountAmtController.value = TextEditingValue(
        text: maxAmtStr,
        selection: TextSelection.collapsed(offset: maxAmtStr.length),
      );
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Maximum discount allowed is 5% (Rs $maxAmtStr)'),
          duration: const Duration(seconds: 2),
        ),
      );
    } else if (parsedAmt < 0.0) {
      _discountPercent = 0.0;
      _discountController.text = '0.00';
      _discountAmtController.value = const TextEditingValue(
        text: '0.00',
        selection: TextSelection.collapsed(offset: 4),
      );
    } else {
      final pct = (parsedAmt / lineGross) * 100.0;
      _discountPercent = double.parse(pct.toStringAsFixed(2));
      _discountController.text = _discountPercent.toStringAsFixed(_discountPercent % 1 == 0 ? 0 : 2);
    }
    setState(() {});
  }

  void _updateQuantity(int change) {
    setState(() {
      int newQty = _quantity + change;
      if (newQty < 1) newQty = 1;

      // Strict validation against maximum valid quantity
      if (_enforceLimit) {
        if (newQty > _maxValidQty) {
          _showStockErrorDialog('Cannot exceed original invoiced quantity (${_formatQty(_maxValidQty)}).');
          return;
        }
      } else if (!_isSalesOrder && _maxValidQty > 0 && newQty > _maxValidQty) {
        _showStockErrorDialog(
          'Insufficient stock in this lot (${_formatQty(_maxValidQty)} available). Please adjust.',
        );
        return;
      }
      _quantity = newQty;
      _qtyController.text = _quantity.toString();
      _syncDiscountAmtFromPercent();
    });

    _resolvePrice(immediate: true);
  }

  void _handleQtyInput(String val) {
    final parsed = int.tryParse(val.trim());
    if (parsed != null && parsed > 0) {
      int updatedQty = parsed;
      if (_enforceLimit) {
        if (updatedQty > _maxValidQty) {
          _showStockErrorDialog('Cannot exceed original invoiced quantity (${_formatQty(_maxValidQty)}).');
          _qtyController.text = _quantity.toString();
          return;
        }
      } else if (!_isSalesOrder && _maxValidQty > 0 && updatedQty > _maxValidQty) {
        _showStockErrorDialog(
          'Insufficient stock in this lot (${_formatQty(_maxValidQty)} available). Please adjust.',
        );
        _qtyController.text = _quantity.toString();
        return;
      }
      setState(() => _quantity = updatedQty);
      _syncDiscountAmtFromPercent();
      _resolvePrice();
    } else {
      setState(() => _quantity = 0);
      _syncDiscountAmtFromPercent();
    }
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

    final state = context.watch<SalesInvoiceBloc>().state;
    final cartItems = state is SalesInvoiceLoaded ? state.cartItems : <CartItem>[];
    double totalCartQtyOfProduct = 0;
    for (var item in cartItems) {
      if (item.product.sku == widget.product.sku) {
        totalCartQtyOfProduct += item.quantity;
      }
    }

    final actualTotalStock = widget.product.stockQty - totalCartQtyOfProduct;

    final authState = context.watch<AuthBloc>().state;
    final perms = authState is Authenticated ? authState.permissions : <String>[];
    final bool canOverridePrice = perms.isEmpty ||
        perms.contains('logistics.sales.price_override.update') ||
        perms.contains('logistics.sales.price_override.create');

    final bool canOverrideDiscount = perms.contains('logistics.sales.discount_override.update') ||
        perms.contains('logistics.sales.discount_override.create') ||
        perms.contains('logistics.sales.discount_override') ||
        perms.any((p) => p.startsWith('logistics.sales.discount_override')) ||
        perms.contains('admin') ||
        perms.contains('*');

    return PopScope(
      canPop: !_isKeypadExpanded,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isKeypadExpanded) {
          setState(() => _isKeypadExpanded = false);
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: theme.colorScheme.surface,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: theme.primaryColor),
            onPressed: () {
              if (_isKeypadExpanded) {
                setState(() => _isKeypadExpanded = false);
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
        title: Text(
          widget.existingItem != null
              ? 'Edit Item [${_txConfig.abbreviation}]'
              : 'Add Item Detail [${_txConfig.abbreviation}]',
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
                                color: _txConfig.badgeColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _enforceLimit
                                    ? 'Original Qty: ${_formatQty(_originalInvoicedQty)}'
                                    : _isSalesOrder
                                        ? 'Stock: ${_formatQty(actualTotalStock)} | Order (No Limit)'
                                        : 'Total: ${_formatQty(actualTotalStock)} | Lot: ${_formatQty(_lotTotalQty)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _txConfig.badgeColor,
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
                    _lotNumber.isNotEmpty
                        ? _lotNumber
                        : (_isSalesOrder ? 'Not Assigned (Sales Order)' : 'None'),
                    isDark,
                    trailingIcon: Icons.chevron_right,
                    onTap: _isReturnMode ? null : () async {
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
                    alignRight: true,
                    enabled: !_isReturnMode && !isFocLocked && canOverridePrice,
                    onChanged: (val) {
                      _syncDiscountAmtFromPercent();
                      setState(() {});
                    },
                  ),
                  if (!isFocLocked && (_basePrice <= 0.0001 || (_priceAfterDiscount + _vatAmount) <= 0.0001))
                    const Padding(
                      padding: EdgeInsets.only(top: 4.0),
                      child: Text(
                        'Amount is 0.00 — Product cannot be added with zero amount',
                        style: TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.bold),
                      ),
                    ),
                  if (!canOverridePrice)
                    const Padding(
                      padding: EdgeInsets.only(top: 4.0),
                      child: Text(
                        'Base price editing locked (supervisor authorization required)',
                        style: TextStyle(fontSize: 11, color: Colors.orange),
                      ),
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

                  // Dynamic Math Fields - Editable when permitted
                  Row(
                    children: [
                      Expanded(
                        child: _buildInputField(
                          'Discount % (Max 5%)',
                          _discountController,
                          isDark,
                          focusNode: _discountFocusNode,
                          suffixText: '%',
                          hintText: '0',
                          enabled: !_isReturnMode && !isFocLocked && canOverrideDiscount,
                          onChanged: _onDiscountPercentChanged,
                          onTap: () {
                            _discountController.clear();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildInputField(
                          'Discount Amt (Max 5%)',
                          _discountAmtController,
                          isDark,
                          focusNode: _discountAmtFocusNode,
                          prefixText: 'Rs ',
                          cardAlignRight: true,
                          isRed: true,
                          hintText: '0.00',
                          enabled: !_isReturnMode && !isFocLocked && canOverrideDiscount,
                          onChanged: _onDiscountAmtChanged,
                          onTap: () {
                            _discountAmtController.clear();
                          },
                        ),
                      ),
                    ],
                  ),
                  if (!canOverrideDiscount)
                    const Padding(
                      padding: EdgeInsets.only(top: 4.0),
                      child: Text(
                        'Discount editing locked (discount authorization required)',
                        style: TextStyle(fontSize: 11, color: Colors.orange),
                      ),
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
                          CurrencyFormatter.format(_vatAmount, explicitSign: true),
                          isDark,
                          alignRight: true,
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left side: Quantity and Stepper
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'QUANTITY',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          height: 48,
                          width: 144,
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
                                onLongPress: isFocLocked ? null : () {
                                  setState(() {
                                    _quantity = 1;
                                    _qtyController.text = '1';
                                  });
                                  _resolvePrice(immediate: true);
                                },
                                disabled: isFocLocked,
                                isLeft: true,
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _qtyController,
                                  focusNode: _qtyFocusNode,
                                  autofocus: true,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _submitOrder(),
                                  textAlign: TextAlign.center,
                                  readOnly: true,
                                  showCursor: true,
                                  keyboardType: TextInputType.none,
                                  enabled: !isFocLocked,
                                  onTap: () {
                                    if (!_isKeypadExpanded) {
                                      setState(() => _isKeypadExpanded = true);
                                    }
                                  },
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    disabledBorder: InputBorder.none,
                                    isDense: true,
                                    filled: false,
                                    contentPadding: EdgeInsets.zero,
                                    hintText: '0',
                                    hintStyle: TextStyle(
                                      color: isDark ? Colors.white38 : Colors.black38,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: isFocLocked ? Colors.grey : (isDark ? Colors.white : Colors.black),
                                  ),
                                  onChanged: _handleQtyInput,
                                ),
                              ),
                              _buildStepperButton(
                                Icons.add,
                                isFocLocked ? null : () => _updateQuantity(1),
                                isDark,
                                onLongPress: isFocLocked ? null : () {
                                  if (_maxValidQty > 0) {
                                    setState(() {
                                      _quantity = _maxValidQty.toInt();
                                      _qtyController.text = _quantity.toString();
                                    });
                                    _syncDiscountAmtFromPercent();
                                    _resolvePrice();
                                  }
                                },
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
                              mainAxisSize: MainAxisSize.min,
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
                    
                    // Right side: Symmetrically aligned Total
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'ITEM TOTAL',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          height: 48,
                          alignment: Alignment.centerRight,
                          child: Text(
                            CurrencyFormatter.format((_priceAfterDiscount + _vatAmount)),
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: theme.primaryColor,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                if (_hasFoc && _focQuantity > 0 && !isFocLocked) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.withOpacity(0.6), width: 1.5),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.card_giftcard, color: Colors.green, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '🎁 FOC Promotion Qualified: ${_focQuantity % 1 == 0 ? _focQuantity.toInt() : _focQuantity}x ${_focItemSku.isEmpty ? widget.product.sku : _focItemSku} Free of Charge',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Large Industrial Numeric Keypad (Collapsible)
                IndustrialNumericKeypad(
                  isExpanded: _isKeypadExpanded,
                  onToggleExpanded: () {
                    setState(() {
                      _isKeypadExpanded = !_isKeypadExpanded;
                    });
                  },
                  onDigitPressed: (digit) {
                    String current = _qtyController.text.trim();
                    if (current == '0') current = '';
                    String next = current + digit;
                    _qtyController.text = next;
                    _handleQtyInput(next);
                  },
                  onClear: () {
                    _qtyController.text = '';
                    _handleQtyInput('');
                  },
                  onBackspace: () {
                    String current = _qtyController.text.trim();
                    if (current.isNotEmpty) {
                      String next = current.substring(0, current.length - 1);
                      _qtyController.text = next;
                      _handleQtyInput(next);
                    }
                  },
                ),
                const SizedBox(height: 8),

                // Giant ENTER / ADD Button
                SizedBox(
                  height: 60,
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _quantity > 0 ? _submitOrder : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: (!isFocLocked && (_basePrice <= 0.0001 || (_priceAfterDiscount + _vatAmount) <= 0.0001))
                          ? Colors.grey.shade700
                          : theme.primaryColor,
                      disabledBackgroundColor: isDark ? Colors.grey[850] : Colors.grey[300],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    icon: Icon(
                      (!isFocLocked && (_basePrice <= 0.0001 || (_priceAfterDiscount + _vatAmount) <= 0.0001))
                          ? Icons.block
                          : Icons.check_circle_rounded,
                      size: 24,
                      color: _quantity > 0 ? Colors.white : (isDark ? Colors.grey[600] : Colors.grey[400]),
                    ),
                    label: Text(
                      _quantity > 0
                          ? (!isFocLocked && (_basePrice <= 0.0001 || (_priceAfterDiscount + _vatAmount) <= 0.0001)
                              ? 'CANNOT ADD (ZERO AMOUNT)'
                              : (_isReturnMode
                                  ? 'CONFIRM RETURN ($_quantity)'
                                  : widget.editingIndex != null
                                      ? 'UPDATE ORDER (${CurrencyFormatter.format(_priceAfterDiscount + _vatAmount)})'
                                      : 'ADD TO ORDER (${CurrencyFormatter.format(_priceAfterDiscount + _vatAmount)})'))
                          : 'ENTER QUANTITY',
                      style: TextStyle(
                        color: _quantity > 0 ? Colors.white : (isDark ? Colors.grey[500] : Colors.grey[600]),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // Cancel Button
                SizedBox(
                  height: 36,
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
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
  );
}

  Future<void> _submitOrder() async {
    if (_quantity <= 0) {
      _showStockErrorDialog('Please enter a valid quantity.');
      return;
    }
    if (_debounce?.isActive == true || _isResolvingPrice) {
      _debounce?.cancel();
      await _resolvePriceNow();
    }
    if (!_isSalesOrder && _quantity > _maxValidQty) {
      _showStockErrorDialog(
        'Cannot proceed: Insufficient stock in this lot (${_formatQty(_maxValidQty)} available).',
      );
      return;
    }

    final bool isFocLocked = widget.existingItem?.isFoc == true;

    if (!isFocLocked && (_basePrice <= 0.0001 || (_priceAfterDiscount + _vatAmount) <= 0.0001)) {
      _showStockErrorDialog('Cannot add product with 0.00 amount. Product price must be greater than zero.');
      return;
    }

    if (!isFocLocked && _discountPercent > 5.0001) {
      _showStockErrorDialog('Discount cannot exceed 5%. Current discount: ${_discountPercent.toStringAsFixed(2)}%');
      return;
    }

    final item = CartItem(
      product: widget.product,
      quantity: _quantity.toDouble(),
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
      pricingSource: _isManualDiscount ? 'MANUAL' : _priceSource,
      discountAmountFlat: _discountAmountFlat,
      priceListCode: _priceListCode,
      reasonType: _reasonType,
    );

    CartItem? focItem;
    if (!isFocLocked && _hasFoc && _focQuantity > 0) {
      final bool isSameItem = _focItemSku.isEmpty || _focItemSku == widget.product.sku;
      final String targetFocSku = _focItemSku.isEmpty ? widget.product.sku : _focItemSku;
      
      String focName = '';
      String focLotNumber = '';
      String focWarehouse = '';
      String focWarehouseName = '';
      String focLocation = '';
      String focLocationType = '';
      String focSalesUnit = 'EA';
      double focTotalStock = 0.0;
      
      final db = await LocalDatabaseHelper.instance.database;

      final sumResult = await db.rawQuery(
        'SELECT SUM(totalQty) as total FROM ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails} WHERE itemCode = ? AND (stockStatus = "A" OR stockStatus IS NULL OR stockStatus = "")',
        [targetFocSku.trim()]
      );
      if (sumResult.isNotEmpty && sumResult.first['total'] != null) {
        focTotalStock = (sumResult.first['total'] as num).toDouble();
      }

      if (focTotalStock <= 0.0001) {
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('FOC Promotion Unavailable'),
              content: Text(
                'Purchasing ${widget.product.name} qualifies for free item ($targetFocSku), but $targetFocSku is currently out of stock in van inventory. It will not be added.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      } else {
        final sameLotMatches = await db.query(
          LocalDatabaseHelper.tableSalesInvoiceItemStockDetails,
          where: 'itemCode = ? AND lotNumber = ? AND totalQty > 0',
          whereArgs: [targetFocSku.trim(), _lotNumber],
          limit: 1,
        );
        
        if (sameLotMatches.isNotEmpty) {
          final r = sameLotMatches.first;
          focName = r['itemName']?.toString() ?? '';
          focSalesUnit = (r['salesUnit'] as String?)?.trim().isNotEmpty == true
              ? (r['salesUnit'] as String).trim()
              : 'EA';
          focLotNumber = r['lotNumber']?.toString() ?? '';
          focWarehouse = r['warehouse']?.toString() ?? '';
          focWarehouseName = r['warehouseName']?.toString() ?? '';
          focLocation = r['location']?.toString() ?? '';
          focLocationType = r['locationType']?.toString() ?? '';
        } else {
          final anyStockedLot = await db.query(
            LocalDatabaseHelper.tableSalesInvoiceItemStockDetails,
            where: 'itemCode = ? AND totalQty > 0',
            whereArgs: [targetFocSku.trim()],
            orderBy: 'totalQty DESC',
            limit: 1,
          );
          if (anyStockedLot.isNotEmpty) {
            final r = anyStockedLot.first;
            focName = r['itemName']?.toString() ?? '';
            focSalesUnit = (r['salesUnit'] as String?)?.trim().isNotEmpty == true
                ? (r['salesUnit'] as String).trim()
                : 'EA';
            focLotNumber = r['lotNumber']?.toString() ?? '';
            focWarehouse = r['warehouse']?.toString() ?? '';
            focWarehouseName = r['warehouseName']?.toString() ?? '';
            focLocation = r['location']?.toString() ?? '';
            focLocationType = r['locationType']?.toString() ?? '';
          }
        }

        if (focLotNumber.isEmpty) {
          final anyLot = await db.query(
            LocalDatabaseHelper.tableSalesInvoiceItemStockDetails,
            where: 'itemCode = ?',
            whereArgs: [targetFocSku.trim()],
            limit: 1,
          );
          if (anyLot.isNotEmpty) {
            final r = anyLot.first;
            focLotNumber = r['lotNumber']?.toString() ?? '';
            focWarehouse = r['warehouse']?.toString() ?? '';
            focWarehouseName = r['warehouseName']?.toString() ?? '';
            focLocation = r['location']?.toString() ?? '';
            focLocationType = r['locationType']?.toString() ?? '';
            if (focName.isEmpty) focName = r['itemName']?.toString() ?? '';
          }
        }

        final focProduct = isSameItem 
          ? widget.product 
          : SalesInvoiceProductModel(
              sku: targetFocSku,
              name: focName.isNotEmpty ? focName : targetFocSku,
              stockQty: focTotalStock,
              warehouse: focWarehouse,
              salesUnit: focSalesUnit,
              cce0: '',
            );

        focItem = CartItem(
          product: focProduct,
          quantity: _focQuantity,
          basePrice: 0.0,
          discountPercent: 100.0,
          lotNumber: focLotNumber,
          warehouse: focWarehouse,
          warehouseName: focWarehouseName,
          location: focLocation,
          locationType: focLocationType,
          vatRatePercent: _vatRatePercent,
          taxRule: _taxRuleCode,
          isFoc: true,
          mainItemSku: widget.product.sku,
          pricingSource: _priceSource,
          discountAmountFlat: 0.0,
          priceListCode: _priceListCode,
          reasonType: _reasonType,
        );
      }
    }

    if (!mounted) return;
    
    final bloc = context.read<SalesInvoiceBloc>();
    final state = bloc.state;
    if (state is! SalesInvoiceLoaded) return;

    if (widget.editingIndex != null) {
      bloc.add(UpdateCartItem(widget.editingIndex!, item));
      if (focItem == null) {
        bloc.add(RemoveLinkedFocItem(widget.product.sku));
      }
      if (_isReturnMode && state.transactionType == 'PREVIEW_INVOICE' && _quantity > 0) {
        bloc.add(ConvertToCreditNote());
      }
      
      if (focItem != null) {
        final cartItems = state.cartItems;
        int existingFocIndex = cartItems.indexWhere((i) => i.isFoc && (i.mainItemSku == widget.product.sku || i.product.sku == focItem!.product.sku));
        if (existingFocIndex != -1) {
          final existingFoc = cartItems[existingFocIndex];
          focItem = focItem!.copyWith(
            lotNumber: existingFoc.lotNumber, 
            location: existingFoc.location, 
            warehouse: existingFoc.warehouse,
            warehouseName: existingFoc.warehouseName,
            locationType: existingFoc.locationType
          );
          bloc.add(UpdateCartItem(existingFocIndex, focItem!));
        } else {
          bloc.add(AddCartItem(focItem!));
        }
      }
      Navigator.of(context).pop();
    } else {
      bloc.add(AddCartItem(item));
      if (focItem != null) {
        bloc.add(AddCartItem(focItem!));
      }
      Navigator.of(context).pop();
    }
  }

  Widget _buildStepperButton(
    IconData icon,
    VoidCallback? onPressed,
    bool isDark, {
    VoidCallback? onLongPress,
    bool disabled = false,
    bool isLeft = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: disabled ? null : onPressed,
        onLongPress: disabled ? null : onLongPress,
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
    bool alignRight = false,
  }) {
    Widget content = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      textAlign: alignRight ? TextAlign.right : TextAlign.left,
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
    String? hintText,
    FocusNode? focusNode,
    VoidCallback? onTap,
    Function(String)? onChanged,
    bool alignRight = false,
    bool cardAlignRight = false,
    bool isRed = false,
    bool enabled = true,
  }) {
    if (alignRight) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[850] : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.grey[300] : Colors.grey[700],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[800] : Colors.grey[100],
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (prefixText != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 2.0),
                      child: Text(
                        prefixText,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.grey[300] : Colors.grey[700],
                        ),
                      ),
                    ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 20),
                    child: IntrinsicWidth(
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        onTap: onTap,
                        enabled: enabled,
                        textAlign: TextAlign.left,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: onChanged,
                        style: TextStyle(
                          fontSize: 15,
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
                          hintText: hintText,
                          hintStyle: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: isDark ? Colors.white30 : Colors.black26,
                          ),
                          suffixText: suffixText,
                          suffixStyle: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
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

    final Color textColor = isRed
        ? (isDark ? const Color(0xFFEF5350) : const Color(0xFFD32F2F))
        : (isDark ? Colors.white : Colors.black87);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(left: 12, top: 8, bottom: 4, right: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: cardAlignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: cardAlignRight ? MainAxisAlignment.end : MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            ],
          ),
          const SizedBox(height: 2),
          TextField(
            controller: controller,
            focusNode: focusNode,
            onTap: onTap,
            enabled: enabled,
            textAlign: cardAlignRight ? TextAlign.right : TextAlign.left,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: onChanged,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: enabled ? textColor : Colors.grey,
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
              hintText: hintText,
              hintStyle: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isDark ? Colors.white30 : Colors.black26,
              ),
              prefixText: prefixText,
              prefixStyle: TextStyle(
                fontWeight: FontWeight.bold,
                color: enabled ? textColor : Colors.grey,
              ),
              suffixText: suffixText,
              suffixStyle: TextStyle(
                fontWeight: FontWeight.bold,
                color: enabled ? textColor : Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
