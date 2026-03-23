import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:enterprise_auth_mobile/core/widgets/industrial_module_layout.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/delivery_repository.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/entities/location_lookup.dart';
import 'package:collection/collection.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/widgets/scan_item_card.dart';

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
  final TextEditingController _amountController = TextEditingController(text: '0.00');
  final TextEditingController _poController = TextEditingController();

  List<Map<String, String>> _customersList = [];
  List<Map<String, String>> _salesRepsList = [];
  List<Map<String, String>> _productsList = [];
  List<Map<String, String>> _existingSOsList = [];

  // Scanner & Site/Location State
  List<Map<String, dynamic>> _scans = [];
  bool _isScannerVisible = false;
  MobileScannerController? _scannerController;
  
  List<String> _sites = [];
  String? _selectedSite;
  List<LocationLookup> _locations = [];
  LocationLookup? _selectedLocation;
  
  bool _isLoadingSites = false;
  bool _isLoadingLocations = false;
  double _cumulativeWeight = 0.0;

  @override
  void initState() {
    super.initState();
    _loadLookups();
    _fetchInitialData();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _poController.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  Future<void> _loadLookups() async {
    try {
      final repository = context.read<DeliveryRepository>();
      final customers = await repository.getCustomers();
      final reps = await repository.getSalesReps();
      final products = await repository.getProducts();
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
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading lookups: $e')));
      }
    }
  }

  Future<void> _fetchInitialData() async {
    await _fetchProductionSites();
  }

  Future<void> _fetchProductionSites() async {
    setState(() => _isLoadingSites = true);
    try {
      final repository = context.read<DeliveryRepository>();
      final sites = await repository.getProductionSites();
      if (mounted) {
        setState(() {
          _sites = sites;
          if (_selectedSite == null || !_sites.contains(_selectedSite)) {
            _selectedSite = _sites.isNotEmpty ? _sites.first : null;
          }
          _isLoadingSites = false;
        });
        if (_selectedSite != null) {
          _fetchLocations();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingSites = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading sites: $e')),
        );
      }
    }
  }

  Future<void> _fetchLocations() async {
    if (_selectedSite == null) return;

    setState(() => _isLoadingLocations = true);
    try {
      final repository = context.read<DeliveryRepository>();
      final locations = await repository.getLocationLookups(_selectedSite!);
      final prefs = await SharedPreferences.getInstance();
      final lastLocation = prefs.getString('last_selected_location');

      if (mounted) {
        setState(() {
          _locations = locations;
          if (lastLocation != null) {
            _selectedLocation = _locations.firstWhereOrNull(
              (l) => l.location == lastLocation,
            );
          }
          _selectedLocation ??= _locations.firstWhereOrNull(
            (l) => l.warehouseName == 'Main Warehouse',
          );
          _selectedLocation ??= _locations.isNotEmpty ? _locations.first : null;
          _isLoadingLocations = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingLocations = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading locations: $e')),
        );
      }
    }
  }

  void _onSiteChanged(String? site) {
    if (site != null && site != _selectedSite) {
      setState(() {
        _selectedSite = site;
        _selectedLocation = null;
        _locations = [];
      });
      _fetchLocations();
    }
  }

  void _toggleScanner() async {
    if (!_isScannerVisible) {
      final status = await Permission.camera.request();
      if (status.isGranted) {
        setState(() {
          _isScannerVisible = true;
          _scannerController = MobileScannerController();
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Camera permission is required to scan')),
          );
        }
      }
    } else {
      setState(() {
        _isScannerVisible = false;
        _scannerController?.dispose();
        _scannerController = null;
      });
    }
  }

  Future<void> _handleScan(BarcodeCapture capture) async {
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final code = barcodes.first.rawValue;
    if (code == null) return;

    // Optional: add haptic feedback or sound

    try {
      final repository = context.read<DeliveryRepository>();
      final result = await repository.decodeBarcode(code);
      
      if (result != null && mounted) {
        final weight = result['weight'] as double;
        final productCode = result['productCode'] as String;
        
        setState(() {
          _scans.add({
            'barcode': code,
            'weight': weight,
            'productCode': productCode,
            'timestamp': DateTime.now().toIso8601String(),
          });
          _cumulativeWeight += weight;
          _amountController.text = _cumulativeWeight.toStringAsFixed(3);
        });
      }
    } catch (e) {
      debugPrint('Error decoding barcode: $e');
    }
  }

  Future<void> _handleSave() async {
    if (_selectedProductCode == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a product')));
      return;
    }

    final amount = double.tryParse(_amountController.text) ?? 0.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid weight')),
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
      'scans': _scans,
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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildModeToggle(orange),
                const SizedBox(height: 24),
                _buildSOToggle(orange),
                const SizedBox(height: 24),

                _buildSectionHeader('Details', Icons.edit_note),
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
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLabel('Salesman 1'),
                            _buildPickerTile(
                              'Salesman 1',
                              _selectedSM1Code,
                              _salesRepsList,
                              (val) => setState(() => _selectedSM1Code = val),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLabel('Salesman 2'),
                            _buildPickerTile(
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
                ],

                _buildLabel('Product *'),
                _buildPickerTile(
                  'Product',
                  _selectedProductCode,
                  _productsList,
                  (val) {
                    final product = _productsList.firstWhereOrNull((p) => p['code'] == val);
                    setState(() {
                      _selectedProductCode = val;
                      _selectedProductName = product?['name'];
                    });
                  },
                ),
                const SizedBox(height: 24),

                _buildSectionHeader('Scanning', Icons.qr_code_scanner),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildLabel('Production Site'),
                          _buildDropdownTile(
                            'Site',
                            _selectedSite,
                            _sites,
                            _onSiteChanged,
                            isLoading: _isLoadingSites,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildLabel('Location'),
                          _buildDropdownTile(
                            'Location',
                            _selectedLocation?.location,
                            _locations.where((l) => l.location != null).map((l) => l.location!).toList(),
                            (val) {
                              setState(() {
                                _selectedLocation = _locations.firstWhereOrNull((l) => l.location == val);
                              });
                            },
                            isLoading: _isLoadingLocations,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                if (_isScannerVisible)
                  _buildScannerView()
                else
                  _buildScannerToggle(),
                
                const SizedBox(height: 24),

                if (_scans.isNotEmpty) ...[
                  _buildSectionHeader('Scanned Items (${_scans.length})', Icons.list),
                  const SizedBox(height: 8),
                  ..._scans.reversed.map((scan) {
                    final index = _scans.indexOf(scan);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: ScanItemCard(
                        lineNumber: index + 1,
                        scan: {
                          ...scan,
                          'productName': _selectedProductName ?? 'Product ${_selectedProductCode ?? ""}',
                          'status': 'A',
                        },
                        onDelete: () {
                          setState(() {
                            _cumulativeWeight -= (scan['weight'] as num).toDouble();
                            _scans.removeAt(index);
                            _amountController.text = _cumulativeWeight.toStringAsFixed(3);
                          });
                        },
                      ),
                    );
                  }),
                  const SizedBox(height: 24),
                ],

                _buildLabel('Amount (Kg) *'),
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    hintText: '0.00',
                    hintStyle: const TextStyle(color: Colors.white24),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.05)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFFF9800)),
                    ),
                  ),
                ),
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
    List<String> items,
    Function(String?) onSelected, {
    bool isLoading = false,
  }) {
    return InkWell(
      onTap: isLoading ? null : () => _showSearchPicker(label, items.map((e) => {'code': e, 'name': e}).toList(), (val) => onSelected(val)),
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
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF9800)),
                    )
                  : Text(
                      value ?? 'Select $label...',
                      style: TextStyle(
                        color: value == null ? Colors.white24 : Colors.white,
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

  Widget _buildScannerToggle() {
    return Center(
      child: Column(
        children: [
          const Text(
            'Ready to scan barcodes',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _toggleScanner,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('OPEN SCANNER'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF9800),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerView() {
    return Container(
      height: 300,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFF9800)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          MobileScanner(
            controller: _scannerController!,
            onDetect: _handleScan,
          ),
          // Scanner Overlay
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFFF9800).withOpacity(0.5), width: 2),
            ),
            margin: const EdgeInsets.all(40),
          ),
          // Close button
          Positioned(
            top: 8,
            right: 8,
            child: CircleAvatar(
              backgroundColor: Colors.black54,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: _toggleScanner,
              ),
            ),
          ),
          // Instruction
          const Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Text(
              'Align barcode within frame',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
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
