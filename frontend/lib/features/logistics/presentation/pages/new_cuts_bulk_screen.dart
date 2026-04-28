import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart' as intl;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:enterprise_auth_mobile/core/widgets/industrial_module_layout.dart';


import 'package:enterprise_auth_mobile/features/logistics/data/repositories/delivery_repository.dart';
import 'package:enterprise_auth_mobile/features/settings/data/models/app_settings.dart';
import 'package:enterprise_auth_mobile/core/utils/barcode_scanner/product_scan_floating_screen.dart';
import 'package:enterprise_auth_mobile/core/utils/barcode_scanner/barcode_scanner_widget.dart';
import 'package:enterprise_auth_mobile/core/utils/barcode_scanner/offline_barcode_processor.dart';


class NewCutsBulkScreen extends StatefulWidget {
  const NewCutsBulkScreen({super.key});

  @override
  State<NewCutsBulkScreen> createState() => _NewCutsBulkScreenState();
}

class _NewCutsBulkScreenState extends State<NewCutsBulkScreen> {
  String _mode = 'cuts'; // 'cuts', 'bulks', or 'frozen'
  DateTime? _date = DateTime.now();
  bool _isNewSO = true; // Toggle: new SO vs existing SO
  bool _soDetailsExpanded = false;
  bool _productsExpanded = true;


  String? _selectedCustomerCode;
  String? _selectedSalesmanCode;
  String? _selectedExistingSO;
  List<Map<String, dynamic>> _selectedProducts = [];
  // Removed _poController as per request

  List<Map<String, String>> _customersList = [];
  List<Map<String, String>> _salesRepsList = [];
  List<Map<String, String>> _productsList = [];
  AppSettings? _settings;


  


  @override
  void initState() {
    super.initState();
    _loadLookups();

  }

  @override
  void dispose() {
    // Removed _poController.dispose();
    super.dispose();
  }

  Future<void> _loadLookups() async {
    try {
      final repository = context.read<DeliveryRepository>();
      final customers = await repository.getCustomers();
      final reps = await repository.getSalesReps();
      final products = await repository.getProducts();
      final settings = await repository.getAppSettings();

      setState(() {
        _customersList = customers
            .map((c) => {'code': c.code, 'name': c.name})
            .toList();
        _salesRepsList = reps
            .map((r) => {'code': r.code, 'name': r.name})
            .toList();
        _productsList = products;
        _settings = settings;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading lookups: $e')));
      }
    }
  }



  double get _totalWeight {
    double total = 0;
    for (var product in _selectedProducts) {
      final scans = product['scans'] as List<dynamic>? ?? [];
      for (var scan in scans) {
        total += (scan['weight'] as num?)?.toDouble() ?? 0.0;
      }
    }
    return total;
  }

  String _formatQuantity(double qty, String unit) {
    final u = unit.toUpperCase();
    if (u == 'EA' || u == 'PCS') {
      // For piece count, use 2 decimal places if fractional, or integer if whole
      if (qty == qty.toInt().toDouble()) {
        return qty.toInt().toString();
      }
      return qty.toStringAsFixed(2);
    }
    return qty.toStringAsFixed(3);
  }

  // Total weight is calculated via getter _totalWeight

  Future<void> _handleSave() async {
    if (_selectedProducts.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please add at least one product')));
      return;
    }

    final amount = _totalWeight;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please scan or add at least one item')),
      );
      return;
    }

    if (_settings?.excessDefaultCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Default Customer not set. Please update Logistics Settings.')),
      );
      return;
    }

    final customerCode = _settings!.excessDefaultCustomer!;
    final salesmanCode = _settings?.excessDefaultSalesman;
    final customerName = _customersList.firstWhere(
      (c) => c['code'] == customerCode,
      orElse: () => {'name': customerCode},
    )['name'];

    final entry = {
      'type': _mode == 'cuts' ? 'Cuts' : (_mode == 'bulks' ? 'Bulks' : 'Frozen'),
      'products': _selectedProducts,
      'customerCode': customerCode,
      'customerName': customerName,
      'date': _date?.toIso8601String(),
      'salesman1Code': salesmanCode,
      'salesman2Code': salesmanCode,
      // Removed poNumber as per request
      'amount': amount,
      'amountKg': amount,
      'scans': _selectedProducts.expand((p) => p['scans'] as List).toList(),
    };

    try {
      final repository = context.read<DeliveryRepository>();
      final entryNo = await repository.saveCutBulkEntry(entry);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved successfully! SO: $entryNo')),
        );
        Navigator.pop(context, true); // Return true to trigger refresh
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF9800);

    return IndustrialModuleLayout(
      title: 'LOGISTICS | EXCESS',
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildOrderTypeToggle(orange),
                const SizedBox(height: 16),
                _buildModeToggle(orange),
                const SizedBox(height: 24),
                
                if (!_isNewSO) ...[
                  _buildLabel('SELECT EXISTING SO'),
                  const SizedBox(height: 8),
                  _buildExistingSOPicker(orange),
                  const SizedBox(height: 24),
                ],

                // Defaults Info Banner
                _buildDefaultsBanner(orange),
                const SizedBox(height: 32),
                const SizedBox(height: 32),

                // Section Header: SCANNED PRODUCTS
                Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined, color: Colors.grey, size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      'SCANNED PRODUCTS',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                 if (_productsExpanded) ...[
                   for (int i = 0; i < _selectedProducts.length; i++)
                     _buildProductItemCard(_selectedProducts[i], i),
                   Row(
                     mainAxisAlignment: MainAxisAlignment.center,
                     children: [
                       TextButton.icon(
                         onPressed: _addProduct,
                         icon: const Icon(Icons.add, color: Color(0xFFFF9800)),
                         label: const Text('Add Product', style: TextStyle(color: Color(0xFFFF9800))),
                       ),
                       const SizedBox(width: 16),
                       TextButton.icon(
                         onPressed: _scanProduct,
                         icon: const Icon(Icons.qr_code_scanner, color: Color(0xFFFF9800)),
                         label: const Text('Scan Product', style: TextStyle(color: Color(0xFFFF9800))),
                       ),
                     ],
                   ),
                 ],
              ],
            ),
          ),
          _buildBottomBar(orange),
        ],
      ),
    );
  }

  Widget _buildModeToggle(Color orange) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          _buildToggleButton('cuts', 'Cuts', orange),
          _buildToggleButton('bulks', 'Bulks', orange),
        ],
      ),
    );
  }

  Widget _buildOrderTypeToggle(Color orange) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          _buildOrderTypeButton(true, 'New SO', orange),
          _buildOrderTypeButton(false, 'Existing SO', orange),
        ],
      ),
    );
  }

  Widget _buildOrderTypeButton(bool value, String label, Color orange) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isSelected = _isNewSO == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _isNewSO = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected 
                ? (isDark ? Colors.white.withValues(alpha: 0.05) : theme.primaryColor.withValues(alpha: 0.05)) 
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? orange : (isDark ? Colors.white38 : Colors.black38),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4),
      child: Text(
        text,
        style: TextStyle(
          color: isDark ? Colors.white38 : Colors.black38,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildExistingSOPicker(Color orange) {
    return _buildDropdownTile(
      'Existing SO',
      _selectedExistingSO,
      [], // We would need to fetch actual SOs here, but for now we'll allow manual entry or mock
      (val) => setState(() => _selectedExistingSO = val),
    );
  }

  Widget _buildToggleButton(String key, String label, Color orange) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isSelected = _mode == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mode = key),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected 
                ? (isDark ? Colors.white.withValues(alpha: 0.05) : theme.primaryColor.withValues(alpha: 0.05)) 
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? orange : (isDark ? Colors.white38 : Colors.black38),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultsBanner(Color orange) {
    if (_settings == null) return const SizedBox.shrink();
    
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final customerCode = _settings?.excessDefaultCustomer ?? 'NOT SET';
    final salesmanCode = _settings?.excessDefaultSalesman ?? 'NOT SET';
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
        boxShadow: isDark ? null : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: isDark ? Colors.white38 : Colors.black38, size: 16),
              const SizedBox(width: 8),
              Text(
                'USING GLOBAL DEFAULTS',
                style: TextStyle(
                  color: isDark ? Colors.white38 : Colors.black38, 
                  fontSize: 10, 
                  fontWeight: FontWeight.bold, 
                  letterSpacing: 1.1,
                ),
              ),
              const Spacer(),
              _buildDatePickerIcon(),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildMiniDefault('CUSTOMER', customerCode),
              const SizedBox(width: 16),
              _buildMiniDefault('SALESMAN', salesmanCode),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniDefault(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildDatePickerIcon() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _date ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2101),
          builder: (context, child) => Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.fromSeed(
                seedColor: orange,
                primary: orange,
                onPrimary: Colors.white,
                surface: isDark ? const Color(0xFF1E1E1E) : theme.cardColor,
                onSurface: isDark ? Colors.white : Colors.black87,
                brightness: isDark ? Brightness.dark : Brightness.light,
              ),
            ),
            child: child!,
          ),
        );
        if (picked != null) setState(() => _date = picked);
      },
      child: Row(
        children: [
          Text(intl.DateFormat('dd/MM').format(_date!), style: TextStyle(color: orange, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(width: 4),
          Icon(Icons.calendar_month, color: orange, size: 16),
        ],
      ),
    );
  }

  Widget _buildDropdownTile(
    String label,
    String? value,
    List<Map<String, String>> items,
    Function(String?) onSelected, {
    bool isLoading = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    String? displayName;
    if (value != null && value.isNotEmpty && items.isNotEmpty) {
      try {
        final item = items.firstWhere((it) => it['code'] == value);
        final name = item['name'];
        if (name != null && name.trim().isNotEmpty) {
          displayName = name;
        } else {
          displayName = value;
        }
      } catch (_) {
        displayName = value;
      }
    }

    return InkWell(
      onTap: isLoading ? null : () => _showSearchPicker(label, items, onSelected),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: isLoading
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: orange),
                    )
                  : Text(
                      displayName ?? 'Select $label...',
                      style: TextStyle(
                        color: displayName == null 
                            ? (isDark ? Colors.white24 : Colors.black26) 
                            : (isDark ? Colors.white : Colors.black87),
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
            Icon(Icons.arrow_drop_down, color: isDark ? Colors.white38 : Colors.black38, size: 20),
          ],
        ),
      ),
    );
  }

  // Removed _buildPOField as per request


  void _addProduct() {
    _showSearchPicker('Product', _productsList, (code) {
      if (code != null) {
        _processScannedProductCode(code);
      }
    });
  }

  void _scanProduct() {
     final theme = Theme.of(context);
     final isDark = theme.brightness == Brightness.dark;

     showModalBottomSheet(
      context: context,
      backgroundColor: theme.scaffoldBackgroundColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          top: 24,
          left: 16,
          right: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Scan Product Barcode/SKU', 
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87, 
                fontSize: 16, 
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            AppBarcodeScanner(
              height: 250,
              onScan: (code) {
                Navigator.pop(context);
                _processScannedProductCode(code);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _processScannedProductCode(String code) async {
    try {
      // Step 1: Decode barcode directly via our processor logic to extract the exact base item code
      final processor = OfflineBarcodeProcessor();
      final result = await processor.processBarcode(code);
      
      String targetItemCode = code;
      
      if (result != null && result.itemCode.isNotEmpty) {
        targetItemCode = result.itemCode;
      }
      
      // Step 2: Grab the matching UI dictionary product
      final product = _productsList.firstWhere(
        (p) => p['code'] == targetItemCode || 'SKU-${p['code']}' == targetItemCode,
        orElse: () => throw Exception('Product base code $targetItemCode not loaded in dropdowns'),
      );

      // Check if already added
      final exists = _selectedProducts.any((p) => p['code'] == product['code']);
      if (exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text('${product['name']} is already added'))
          );
        }
        return;
      }

      setState(() {
        _selectedProducts.add({
          'code': product['code'],
          'name': product['name'],
          'unit': product['unit'] ?? 'KG',
          'sku': 'SKU-${product['code']}',
          'qty': 0.0,
          'scans': [],
        });
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added: ${product['name']}'))
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Product not found in lookups'))
        );
      }
    }
  }

  Future<void> _navigateToScan(Map<String, dynamic> product, int index) async {
    final scans = List<Map<String, dynamic>>.from(product['scans'] ?? []);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => ProductScanFloatingScreen(
        product: product,
        initialScans: scans,
        initialLot: _settings?.dailyLotNumber,
        onConfirm: (result) {
          setState(() {
            _selectedProducts[index]['scans'] = result;
          });
        },
      ),
    );
  }

  Widget _buildProductItemCard(Map<String, dynamic> product, int index) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;
    final String code = product['code'] ?? '';
    final String name = product['name'] ?? '';
    final String sku = product['sku'] ?? 'N/A';
    final int scanCount = (product['scans'] as List?)?.length ?? 0;
    
    // Calculate total scanned quantity (EA count or KG weight) for this product
    double totalScannedQty = 0;
    final String unit = (product['unit'] ?? 'KG').toString().toUpperCase();
    final scans = product['scans'] as List<dynamic>? ?? [];
    for (var scan in scans) {
      // Use scannedQty for the QTY display (this is the piece count for EA)
      totalScannedQty += (scan['scannedQty'] as num?)?.toDouble() ?? 0.0;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scanCount > 0 ? orange.withValues(alpha: 0.3) : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
        ),
        boxShadow: isDark ? null : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _navigateToScan(product, index),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$code • $sku',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.white24, size: 20),
                    onPressed: () => setState(() => _selectedProducts.removeAt(index)),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              if (scanCount > 0) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black.withValues(alpha: 0.2) : theme.primaryColor.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildMiniInfo('SCANS', scanCount.toString()),
                      _buildMiniInfo('QTY', '${_formatQuantity(totalScannedQty, unit)} $unit'),
                    ],
                  ),
                ),
              ] else ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.qr_code_scanner, color: Colors.white24, size: 14),
                    const SizedBox(width: 8),
                    Text(
                      'TAP TO START SCANNING',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.2),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
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

  Widget _buildMiniInfo(String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.3),
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFFFF9800),
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }



  Widget _buildDatePicker() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _date ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2101),
          builder: (context, child) => Theme(
            data: theme.copyWith(
              colorScheme: theme.colorScheme.copyWith(
                primary: orange,
                onSurface: isDark ? Colors.white : Colors.black87,
              ),
            ),
            child: child!,
          ),
        );
        if (picked != null) setState(() => _date = picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _date == null
                  ? 'dd/mm/yyyy'
                  : intl.DateFormat('dd/MM/yyyy').format(_date!),
              style: TextStyle(
                color: _date == null ? (isDark ? Colors.white24 : Colors.black26) : (isDark ? Colors.white : Colors.black87),
                fontSize: 14,
              ),
            ),
            Icon(
              Icons.calendar_today_outlined,
              size: 18,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ],
        ),
      ),
    );
  }


  void _showSearchPicker(
    String title,
    List<Map<String, String>> items,
    Function(String?) onSelected,
  ) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _SearchPickerSheet(
        title: title,
        items: items,
        onSelected: onSelected,
      ),
    );
  }

  Widget _buildBottomBar(Color orange) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardColor,
          border: Border(
            top: BorderSide(color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
          ),
        ),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _handleSave,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: isDark ? 0 : 4,
            ),
            child: const Text(
              'Save',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchPickerSheet extends StatefulWidget {
  final String title;
  final List<Map<String, String>> items;
  final Function(String?) onSelected;

  const _SearchPickerSheet({
    required this.title,
    required this.items,
    required this.onSelected,
  });

  @override
  State<_SearchPickerSheet> createState() => _SearchPickerSheetState();
}

class _SearchPickerSheetState extends State<_SearchPickerSheet> {
  late List<Map<String, String>> _filteredItems;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.items;
  }

  void _filter(String query) {
    setState(() {
      _filteredItems = widget.items.where((it) {
        final code = (it['code'] ?? '').toLowerCase();
        final name = (it['name'] ?? '').toLowerCase();
        return code.contains(query.toLowerCase()) ||
            name.contains(query.toLowerCase());
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Select ${widget.title}',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            onChanged: _filter,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: 'Search...',
              hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.black38),
              prefixIcon: Icon(Icons.search, color: isDark ? Colors.grey : Colors.black38),
              filled: true,
              fillColor: isDark ? const Color(0xFF2C2C2E) : Colors.black.withValues(alpha: 0.03),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: _filteredItems.length,
              itemBuilder: (context, index) {
                final item = _filteredItems[index];
                return ListTile(
                  title: Row(
                    children: [
                      Text(
                        item['code'] ?? '',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (item['unit'] != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.primaryColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item['unit']!,
                            style: TextStyle(color: theme.primaryColor, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    item['name'] ?? '',
                    style: TextStyle(color: isDark ? Colors.grey : Colors.black54, fontSize: 12),
                  ),
                  onTap: () {
                    widget.onSelected(item['code']);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}


