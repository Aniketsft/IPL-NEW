import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart' as intl;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:enterprise_auth_mobile/core/widgets/industrial_module_layout.dart';


import 'package:enterprise_auth_mobile/features/logistics/data/repositories/delivery_repository.dart';
import 'package:enterprise_auth_mobile/core/utils/barcode_scanner/product_scan_bottom_sheet.dart';


class NewCutsBulkScreen extends StatefulWidget {
  const NewCutsBulkScreen({super.key});

  @override
  State<NewCutsBulkScreen> createState() => _NewCutsBulkScreenState();
}

class _NewCutsBulkScreenState extends State<NewCutsBulkScreen> {
  String _mode = 'cuts'; // 'cuts' or 'bulks'
  DateTime? _date = DateTime.now();
  bool _isNewSO = true; // Toggle: new SO vs existing SO
  bool _soDetailsExpanded = true;
  bool _productsExpanded = true;


  String? _selectedCustomerCode;
  String? _selectedSM1Code;
  String? _selectedSM2Code;
  String? _selectedExistingSO;
  List<Map<String, dynamic>> _selectedProducts = [];
  final TextEditingController _poController = TextEditingController();

  List<Map<String, String>> _customersList = [];
  List<Map<String, String>> _salesRepsList = [];
  List<Map<String, String>> _productsList = [];
  List<Map<String, String>> _existingSOsList = [];
  bool _isLoadingSOs = false;


  


  @override
  void initState() {
    super.initState();
    _loadLookups();

  }

  @override
  void dispose() {
    _poController.dispose();
    super.dispose();
  }

  Future<void> _loadLookups() async {
    try {
      final repository = context.read<DeliveryRepository>();
      final customers = await repository.getCustomers();
      final reps = await repository.getSalesReps();
      final products = await repository.getProducts();
      setState(() => _isLoadingSOs = true);
      final existingSOs = await repository.getExistingCutBulkSOs();

      setState(() {
        _customersList = customers
            .map((c) => {'code': c.code, 'name': c.name})
            .toList();
        _salesRepsList = reps
            .map((r) => {'code': r.code, 'name': r.name})
            .toList();
        _productsList = products;
        _existingSOsList = existingSOs;
        _isLoadingSOs = false;
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

    if (_isNewSO) {
      // New SO: require customer
      if (_selectedCustomerCode == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a customer')),
        );
        return;
      }
    } else {
      // Existing SO: require SO selection
      if (_selectedExistingSO == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select an existing SO')),
        );
        return;
      }
    }

    final customer = _isNewSO
        ? _customersList.firstWhere(
            (c) => c['code'] == _selectedCustomerCode,
          )
        : <String, String>{};

    final entry = {
      'type': _mode == 'cuts' ? 'Cuts' : 'Bulks',
      'products': _selectedProducts,
      if (_isNewSO) ...{
        'customerCode': _selectedCustomerCode,
        'customerName': customer['name'],
        'date': _date?.toIso8601String(),
        'salesman1Code': _selectedSM1Code,
        'salesman2Code': _selectedSM2Code,
      },
      if (!_isNewSO) 'existingSoNumber': _selectedExistingSO,
      'poNumber': _poController.text,
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
      title: 'LOGISTICS | BULK SCAN',
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildModeToggle(orange),
                const SizedBox(height: 24),
                _buildSOToggle(orange),
                const SizedBox(height: 32),

                // SO Details Section
                Theme(
                  data: Theme.of(context).copyWith(
                    dividerColor: Colors.transparent,
                    splashColor: Colors.transparent,
                    highlightColor: Colors.transparent,
                  ),
                  child: ExpansionTile(
                    initiallyExpanded: _soDetailsExpanded,
                    onExpansionChanged: (expanded) => setState(() => _soDetailsExpanded = expanded),
                    tilePadding: EdgeInsets.zero,
                    title: Row(
                      children: [
                        Icon(_isNewSO ? Icons.assignment_outlined : Icons.inventory_2_outlined, color: Colors.grey, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          _isNewSO ? 'SO DETAILS' : 'SELECT EXISTING SO',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                    children: [
                      const SizedBox(height: 16),
                      if (_isNewSO) ...[
                        _buildLabel('Customer'),
                        _buildDropdownTile(
                          'Customer',
                          _selectedCustomerCode,
                          _customersList,
                          (val) => setState(() => _selectedCustomerCode = val),
                        ),
                        const SizedBox(height: 16),
                        _buildLabel('Date'),
                        _buildDatePicker(),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildLabel('Salesman 1'),
                                  _buildDropdownTile(
                                    'Salesman 1',
                                    _selectedSM1Code,
                                    _salesRepsList,
                                    (val) => setState(() => _selectedSM1Code = val),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildLabel('Salesman 2'),
                                  _buildDropdownTile(
                                    'Salesman 2',
                                    _selectedSM2Code,
                                    _salesRepsList,
                                    (val) => setState(() => _selectedSM2Code = val),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildLabel('PO Number'),
                        _buildPOField(),
                      ] else ...[
                        _buildLabel('Existing SO'),
                        _buildDropdownTile(
                          'Existing SO',
                          _selectedExistingSO,
                          _existingSOsList,
                          (val) => setState(() => _selectedExistingSO = val),
                          isLoading: _isLoadingSOs,
                        ),
                      ],
                    ],
                  ),
                ),
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
                   Center(
                     child: TextButton.icon(
                       onPressed: _addProduct,
                       icon: const Icon(Icons.add, color: Color(0xFFFF9800)),
                       label: const Text('Add Product', style: TextStyle(color: Color(0xFFFF9800))),
                     ),
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
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _buildToggleButton('cuts', 'Cuts', orange),
          _buildToggleButton('bulks', 'Bulks', orange),
        ],
      ),
    );
  }

  Widget _buildSOToggle(Color orange) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _buildSOToggleButton(true, 'New SO', orange),
          _buildSOToggleButton(false, 'Existing SO', orange),
        ],
      ),
    );
  }

  Widget _buildToggleButton(String key, String label, Color orange) {
    final isSelected = _mode == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mode = key),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF2C2C2E) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? orange : Colors.white38,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSOToggleButton(bool isNew, String label, Color orange) {
    final isSelected = _isNewSO == isNew;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _isNewSO = isNew;
          // Reset selection when toggling
          if (isNew) {
            _selectedExistingSO = null;
          } else {
            _selectedCustomerCode = null;
            _selectedSM1Code = null;
            _selectedSM2Code = null;
          }
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF2C2C2E) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? orange : Colors.white38,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
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
    String? displayName;
    if (value != null && items.isNotEmpty) {
      try {
        final item = items.firstWhere((it) => it['code'] == value);
        displayName = item['name'] ?? value;
      } catch (_) {
        displayName = value;
      }
    }

    return InkWell(
      onTap: isLoading ? null : () => _showSearchPicker(label, items, onSelected),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF9800)),
                    )
                  : Text(
                      displayName ?? 'Select $label...',
                      style: TextStyle(
                        color: displayName == null ? Colors.white24 : Colors.white,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
            const Icon(Icons.arrow_drop_down, color: Colors.white38, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildPOField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: TextFormField(
        controller: _poController,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Enter PO Number',
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 14),
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }


  void _addProduct() {
    _showSearchPicker('Product', _productsList, (code) {
      if (code != null) {
        final product = _productsList.firstWhere((p) => p['code'] == code);
        setState(() {
          _selectedProducts.add({
            'code': product['code'],
            'name': product['name'],
            'sku': 'SKU-${product['code']}', // Placeholder
            'qty': 0.0,
            'scans': [],
          });
        });
      }
    });
  }

  Future<void> _navigateToScan(Map<String, dynamic> product, int index) async {
    final scans = List<Map<String, dynamic>>.from(product['scans'] ?? []);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ProductScanBottomSheet(
        product: product,
        initialScans: scans,
        onConfirm: (result) {
          setState(() {
            _selectedProducts[index]['scans'] = result;
            // Update total weight if needed, though _totalWeight getter handles it
          });
        },
      ),
    );
  }

  Widget _buildProductItemCard(Map<String, dynamic> product, int index) {
    final String code = product['code'] ?? '';
    final String name = product['name'] ?? '';
    final String sku = product['sku'] ?? 'N/A';
    final int scanCount = (product['scans'] as List?)?.length ?? 0;
    
    // Calculate total scanned weight for this product
    double scannedWeight = 0;
    final scans = product['scans'] as List<dynamic>? ?? [];
    for (var scan in scans) {
      scannedWeight += (scan['weight'] as num?)?.toDouble() ?? 0.0;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scanCount > 0 ? const Color(0xFFFF9800).withValues(alpha: 0.3) : Colors.white10,
        ),
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
                    color: Colors.black.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildMiniInfo('SCANS', scanCount.toString()),
                      _buildMiniInfo('WEIGHT', '${scannedWeight.toStringAsFixed(2)} KG'),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.3),
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


  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white70, fontSize: 13),
      ),
    );
  }

  Widget _buildDatePicker() {
    const orange = Color(0xFFFF9800);
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _date ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2101),
          builder: (context, child) => Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.dark(
                primary: orange,
                onSurface: Colors.white,
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
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _date == null
                  ? 'dd/mm/yyyy'
                  : intl.DateFormat('dd/MM/yyyy').format(_date!),
              style: TextStyle(
                color: _date == null ? Colors.white24 : Colors.white,
                fontSize: 14,
              ),
            ),
            const Icon(
              Icons.calendar_today_outlined,
              size: 18,
              color: Colors.white38,
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121212),
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
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
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
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Select ${widget.title}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            onChanged: _filter,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search...',
              hintStyle: const TextStyle(color: Colors.white24),
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              filled: true,
              fillColor: const Color(0xFF2C2C2E),
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
                  title: Text(
                    item['code'] ?? '',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    item['name'] ?? '',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
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


