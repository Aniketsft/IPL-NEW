import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:enterprise_auth_mobile/core/widgets/industrial_module_layout.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/delivery_repository.dart';

class NewCutsBulkScreen extends StatefulWidget {
  const NewCutsBulkScreen({super.key});

  @override
  State<NewCutsBulkScreen> createState() => _NewCutsBulkScreenState();
}

class _NewCutsBulkScreenState extends State<NewCutsBulkScreen> {
  String _mode = 'cuts'; // 'cuts' or 'bulks'
  DateTime? _date = DateTime.now();
  bool _isNewSO = true; // Toggle: new SO vs existing SO

  String? _selectedCustomerCode;
  String? _selectedSM1Code;
  String? _selectedSM2Code;
  String? _selectedProductCode;
  String? _selectedProductName;
  String? _selectedExistingSO;
  // Amount is always 0 for Cut/Bulk — not user-editable

  List<Map<String, String>> _customersList = [];
  List<Map<String, String>> _salesRepsList = [];
  List<Map<String, String>> _productsList = [];
  List<Map<String, String>> _existingSOsList = [];

  @override
  void initState() {
    super.initState();
    _loadLookups();
  }

  Future<void> _loadLookups() async {
    try {
      final repository = context.read<DeliveryRepository>();
      final customers = await repository.getCustomers();
      final reps = await repository.getSalesReps();
      final products = await repository.getProducts();
      final existingSOs = await repository.getExistingCutBulkSOs();

      setState(() {
        _customersList = customers;
        _salesRepsList = reps;
        _productsList = products;
        _existingSOsList = existingSOs;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading lookups: $e')));
      }
    }
  }

  Future<void> _handleSave() async {
    if (_selectedProductCode == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a product')));
      return;
    }

    const amount = 0.0; // Cut/Bulk always starts at zero

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
      'productCode': _selectedProductCode,
      'productName': _selectedProductName,
      if (_isNewSO) ...{
        'customerCode': _selectedCustomerCode,
        'customerName': customer['name'],
        'date': _date?.toIso8601String(),
        'salesman1Code': _selectedSM1Code,
        'salesman2Code': _selectedSM2Code,
      },
      if (!_isNewSO) 'existingSoNumber': _selectedExistingSO,
      'amount': amount,
      'amountKg': amount,
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
      title: 'New Cuts / Bulk',
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildModeToggle(orange),
                const SizedBox(height: 24),
                _buildSOToggle(orange),
                const SizedBox(height: 24),
                _buildSectionHeader('Details', Icons.keyboard_arrow_up),
                const SizedBox(height: 16),
                if (!_isNewSO) ...[
                  _buildLabel('Select Existing SO *'),
                  _buildPickerTile(
                    'Existing SO',
                    _selectedExistingSO,
                    _existingSOsList,
                    (val) => setState(() => _selectedExistingSO = val),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_isNewSO) ...[
                  _buildLabel('Customer *'),
                  _buildPickerTile(
                    'Customer',
                    _selectedCustomerCode,
                    _customersList,
                    (val) => setState(() => _selectedCustomerCode = val),
                  ),
                  const SizedBox(height: 16),
                  _buildLabel('Date'),
                  _buildDatePicker(orange),
                  const SizedBox(height: 16),
                ],
                _buildLabel('Product *'),
                _buildPickerTile(
                  'Product',
                  _selectedProductCode,
                  _productsList,
                  (val) {
                    final product = _productsList.firstWhere(
                      (p) => p['code'] == val,
                      orElse: () => {},
                    );
                    setState(() {
                      _selectedProductCode = val;
                      _selectedProductName = product['name'];
                    });
                  },
                ),
                if (_isNewSO) ...[
                  const SizedBox(height: 16),
                  _buildLabel('Salesman 1'),
                  _buildPickerTile(
                    'Salesman 1',
                    _selectedSM1Code,
                    _salesRepsList,
                    (val) => setState(() => _selectedSM1Code = val),
                  ),
                  const SizedBox(height: 16),
                  _buildLabel('Salesman 2'),
                  _buildPickerTile(
                    'Salesman 2',
                    _selectedSM2Code,
                    _salesRepsList,
                    (val) => setState(() => _selectedSM2Code = val),
                  ),
                ],
                const SizedBox(height: 16),
                _buildLabel('Amount (Kg)'),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: const Text(
                    '0.00',
                    style: TextStyle(color: Colors.white38, fontSize: 14),
                  ),
                ),
                const SizedBox(height: 100), // Space for bottom bar
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

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Icon(icon, color: Colors.white38, size: 20),
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

  Widget _buildDatePicker(Color orange) {
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
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _date == null
                  ? 'dd/mm/yyyy'
                  : DateFormat('dd/MM/yyyy').format(_date!),
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

  Widget _buildPickerTile(
    String label,
    String? currentValue,
    List<Map<String, String>> items,
    Function(String?) onSelected,
  ) {
    final currentItem = items.firstWhere(
      (it) => it['code'] == currentValue,
      orElse: () => {},
    );
    final valueText = currentItem.isNotEmpty
        ? '${currentItem['code']} - ${currentItem['name']}'
        : 'Select a ${label.toLowerCase()}...';

    return InkWell(
      onTap: () => _showSearchPicker(label, items, onSelected),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                valueText,
                style: TextStyle(
                  color: currentValue == null ? Colors.white24 : Colors.white,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: Colors.white38),
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
            top: BorderSide(color: Colors.white.withOpacity(0.05)),
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
