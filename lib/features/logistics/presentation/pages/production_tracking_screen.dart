import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';


import '../../../../core/utils/barcode_scanner/barcode_scanner_widget.dart';

import '../../domain/entities/sales_order.dart';
import '../../domain/entities/sales_order_detail.dart';
import '../../data/repositories/delivery_repository.dart';
import '../../domain/entities/location_lookup.dart';
import '../widgets/scan_item_card.dart';
import '../../data/local/local_database_helper.dart';
import '../../../../core/utils/barcode_scanner/barcode_processor.dart';

const Color orange = Color(0xFFFF9800);
const Color dark800 = Color(0xFF1E1E1E);
const Color dark900 = Color(0xFF0D0D0D);
const Color darkBorder = Color(0xFF2C2C2E);

class ProductionTrackingScreen extends StatefulWidget {
  final SalesOrder order;
  final SalesOrderDetail product;

  const ProductionTrackingScreen({
    super.key,
    required this.order,
    required this.product,
  });

  @override
  State<ProductionTrackingScreen> createState() =>
      _ProductionTrackingScreenState();
}

class _ProductionTrackingScreenState extends State<ProductionTrackingScreen> {
  String _status = 'A'; // A: Approved, Q: Quality, R: Rejected
  double _cumulativeQty = 0.0;
  List<Map<String, dynamic>> _scans = [];
  Map<String, dynamic>? _pendingScan;
  bool _isSaving = false;
  List<String> _sites = [];
  String? _selectedSite;
  List<String> _lots = [];
  String? _selectedLot;
  List<LocationLookup> _locations = [];
  LocationLookup? _selectedLocation;
  bool _isLoadingLocations = false;
  bool _isLoadingSites = false;
  bool _isLoadingLots = false;
  bool _isScannerVisible = false;


  @override
  void initState() {
    super.initState();
    _selectedSite = widget.product.site;
    _fetchInitialData();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _fetchInitialData() async {
    try {
      await _fetchProductionSites();
      await _fetchLocations();
      if (_selectedSite != null) {
        await _fetchLots();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading initial data: $e')),
        );
      }
    }
  }

  Future<void> _fetchLocations() async {
    if (_selectedSite == null) return;

    setState(() => _isLoadingLocations = true);
    try {
      final repository = context.read<DeliveryRepository>();
      final locations = await repository.getTargetLocations(
        _selectedSite!,
        widget.product.itemCode,
      );

      if (mounted) {
        setState(() {
          _locations = locations;
          // If main warehouse not found, default to first available
          _selectedLocation ??= _locations.isNotEmpty ? _locations.first : null;
          _isLoadingLocations = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingLocations = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading locations: $e')));
      }
    }
  }

  Future<void> _fetchProductionSites() async {
    setState(() => _isLoadingSites = true);
    try {
      final repository = context.read<DeliveryRepository>();
      final sites = await repository.getProductionSites();
      if (mounted) {
        setState(() {
          _sites = sites;
          // Always default to 'IPL' if it exists in the list
          if (_sites.contains('IPL')) {
            _selectedSite = 'IPL';
          } else if (_selectedSite == null || !_sites.contains(_selectedSite)) {
            _selectedSite = _sites.isNotEmpty ? _sites.first : null;
          }
          _isLoadingSites = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingSites = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading production sites: $e')),
        );
      }
    }
  }

  Future<void> _fetchLots() async {
    if (_selectedSite == null) return;
    setState(() => _isLoadingLots = true);
    try {
      final repository = context.read<DeliveryRepository>();
      final lots = await repository.getLots(
        widget.product.itemCode,
        _selectedSite!,
      );
      if (mounted) {
        setState(() {
          _lots = lots;
          if (_selectedLot == null || !_lots.contains(_selectedLot)) {
            _selectedLot = _lots.isNotEmpty ? _lots.first : null;
          }
          _isLoadingLots = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingLots = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading lots: $e')));
      }
    }
  }

  void _onSiteChanged(String? siteId) {
    if (siteId != null && siteId != _selectedSite) {
      setState(() {
        _selectedSite = siteId;
        _selectedLocation = null;
        _selectedLot = null;
      });
      _fetchLocations();
      _fetchLots();
    }
  }

  Future<void> _saveLastLocation(String location) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_selected_location', location);
  }

  Future<void> _toggleScanner() async {
    setState(() => _isScannerVisible = !_isScannerVisible);
  }


  Future<void> _handleScan(String barcode) async {
    if (barcode.isEmpty) return;

    try {
      final repository = context.read<DeliveryRepository>();
      
      // 1. Lookup Product by Barcode
      final matchedProduct = await repository.getProductByBarcode(barcode);
      
      String targetItemCode;
      String targetUnit;
      double targetStdWeight;

      if (matchedProduct != null) {
        targetItemCode = matchedProduct[LocalDatabaseHelper.colProdCode] ?? '';
        targetUnit = matchedProduct[LocalDatabaseHelper.colProdStu] ?? 'KG';
        targetStdWeight = (matchedProduct[LocalDatabaseHelper.colProdStandardWeight] as num?)?.toDouble() ?? 0.0;
      } else {
        // Fallback to current selected product metadata
        targetItemCode = widget.product.itemCode;
        targetUnit = widget.product.unit;
        targetStdWeight = 0.0; // Assume 0 if not in database
      }

      // 2. Process with specialised rule-set
      final result = BarcodeProcessor.process(
        barcode: barcode,
        itemCode: targetItemCode,
        unit: targetUnit,
        standardWeight: targetStdWeight,
      );

      if (mounted) {
        if (result.isValid) {
          // RULE 1: ITEM MATCH (Strict validation against current screen's product)
          if (result.itemCode != widget.product.itemCode) {
            _showErrorDialog(
              'Wrong Product',
              'Scanned: ${result.itemCode}\nExpected: ${widget.product.itemCode}',
            );
            return;
          }

          // RULE 2: RECONCILIATION / OVER-SCAN
          final isCutBulkOrder = widget.order.orderNumber.startsWith('CB-');
          if (!isCutBulkOrder && _status == 'A') {
            final remaining =
                widget.product.quantity -
                widget.product.manufacturedQuantity -
                _cumulativeQty;
            if (result.manufacturedQty > remaining + 0.001) {
              _showErrorDialog(
                'Limit Exceeded',
                'Scanning ${widget.product.formatQuantity(result.manufacturedQty)} ${widget.product.unit} would exceed the remaining order quantity.',
              );
              return;
            }
          }

          setState(() {
            _pendingScan = {
              'barcode': result.processedBarcode,
              'originalBarcode': result.originalBarcode,
              'productCode': result.itemCode,
              'scannedQty': result.scannedQty,
              'manufacturedQty': result.manufacturedQty,
              'weight': result.manufacturedQty, // Compatibility
              'timestamp': DateTime.now().toIso8601String(),
            };
          });

          if (!_isScannerVisible) {
            // Confirmation prompt for manual entry
            _showConfirmationPrompt(result);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Detected: ${widget.product.formatQuantity(result.manufacturedQty)} ${widget.product.unit}.'),
                backgroundColor: orange,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid barcode format'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Scan error: $e')));
      }
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: dark800,
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAndUpload() async {
    if (_cumulativeQty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No quantity scanned to save')),
      );
      return;
    }

    if (_selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a target location')),
      );
      return;
    }

    if (_selectedSite == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a production site')),
      );
      return;
    }

    if (_selectedLot == null && _lots.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a production lot')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final repository = context.read<DeliveryRepository>();

      // Production Scan Business Data
      final payload = {
        'batchId': DateTime.now().millisecondsSinceEpoch.toString(),
        'itemCode': widget.product.itemCode,
        'originalOrderQty': widget.product.quantity,
        'scanAmountKg': _cumulativeQty,
        'itemStatus': _status, // A, Q, or R
        'location': _selectedLocation?.location,
        'warehouse': _selectedLocation?.warehouse,
        'timestamp': DateTime.now().toIso8601String(),
        'soNumber': widget.order.orderNumber,
        'customerName': widget.order.customerName,
        'siteId': _selectedSite,
        'locationCode': _selectedLocation?.location,
        'lotNumber': _selectedLot,
      };

      await repository.saveProductionScan(payload);

      if (mounted) {
        final isPartial =
            (_cumulativeQty +
                    widget.product.manufacturedQuantity -
                    widget.product.quantity)
                .abs() >
            0.001;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isPartial
                  ? 'Partial progress saved successfully'
                  : 'Production scan completed and saved',
            ),
            backgroundColor: isPartial ? Colors.blue : Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save log: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: dark900,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Production Scan',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _buildHeaderCard(),
                  const SizedBox(height: 16),
                  _buildSiteSelector(),
                  const SizedBox(height: 12),
                  _buildLotSelector(),
                  const SizedBox(height: 12),
                  _buildLocationSelector(),
                  const SizedBox(height: 16),
                  _buildStatusAndOrderParams(),
                  const SizedBox(height: 16),
                  if (_isScannerVisible)
                    _buildScannerView()
                  else
                    _buildSummaryCard(),
                  if (_scans.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _buildScannedItemsList(),
                  ],
                ],
              ),
            ),
          ),
          _buildActionFooter(),
        ],
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark800,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.order.customerName,
            style: const TextStyle(color: orange, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            widget.product.description,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _infoChip('SKU: ${widget.product.itemCode}'),
              const SizedBox(width: 8),
              _infoChip('SO: ${widget.order.orderNumber}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.grey, fontSize: 11),
      ),
    );
  }

  Widget _buildSiteSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark800,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Production Site',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            dropdownColor: dark800,
            value: _selectedSite,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              filled: true,
              fillColor: darkBorder,
              prefixIcon: const Icon(Icons.business, color: orange, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 14,
              ),
              suffixIcon: _isLoadingSites
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: orange,
                        ),
                      ),
                    )
                  : null,
            ),
            items: _sites
                .map((site) => DropdownMenuItem(value: site, child: Text(site)))
                .toList(),
            onChanged: _onSiteChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildLotSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark800,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Production Lot (Search or Select)',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              if (_isLoadingLots)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: orange,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Autocomplete<String>(
            initialValue: TextEditingValue(text: _selectedLot ?? ''),
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (textEditingValue.text.isEmpty) {
                return _lots;
              }
              return _lots.where((String option) {
                return option.toLowerCase().contains(
                  textEditingValue.text.toLowerCase(),
                );
              });
            },
            onSelected: (String selection) {
              setState(() => _selectedLot = selection);
              FocusScope.of(context).unfocus();
            },
            fieldViewBuilder:
                (
                  BuildContext context,
                  TextEditingController textEditingController,
                  FocusNode focusNode,
                  VoidCallback onFieldSubmitted,
                ) {
                  return TextFormField(
                    controller: textEditingController,
                    focusNode: focusNode,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: darkBorder,
                      prefixIcon: const Icon(
                        Icons.layers,
                        color: orange,
                        size: 20,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      hintText: 'Type or tap to select lot',
                      hintStyle: const TextStyle(color: Colors.white38),
                    ),
                    onChanged: (value) {
                      setState(() => _selectedLot = value);
                    },
                  );
                },
            optionsViewBuilder:
                (
                  BuildContext context,
                  AutocompleteOnSelected<String> onSelected,
                  Iterable<String> options,
                ) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      color: dark800,
                      elevation: 4.0,
                      borderRadius: BorderRadius.circular(8),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: 250,
                          maxWidth: MediaQuery.of(context).size.width - 64,
                        ),
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (BuildContext context, int index) {
                            final String option = options.elementAt(index);
                            return InkWell(
                              onTap: () => onSelected(option),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(color: darkBorder),
                                  ),
                                ),
                                child: Text(
                                  option,
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark800,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Target Inventory Location',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _isLoadingLocations ? null : () => _showLocationPicker(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: darkBorder,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    color: orange,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _isLoadingLocations
                        ? const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: orange,
                              ),
                            ),
                          )
                        : Text(
                            _selectedLocation?.fullInfo ?? 'Select Location...',
                            style: TextStyle(
                              color: _selectedLocation == null
                                  ? Colors.grey
                                  : Colors.white,
                            ),
                          ),
                  ),
                  const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusAndOrderParams() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark800,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _statItem('Order Qty', '${widget.product.formatQuantity(widget.product.quantity)} ${widget.product.unit}'),
              _statItem(
                'Already Mfd',
                '${widget.product.formatQuantity(widget.product.manufacturedQuantity)} ${widget.product.unit}',
              ),
              _statItem(
                'Remaining',
                '${widget.product.formatQuantity(widget.product.quantity - widget.product.manufacturedQuantity)} ${widget.product.unit}',
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white10),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                'Production Status',
                style: TextStyle(color: Colors.grey),
              ),
              const Spacer(),
              _statusToggle(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _statusToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: darkBorder,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: ['Q', 'A', 'R'].map((s) {
          final isSelected = _status == s;
          return GestureDetector(
            onTap: () => setState(() => _status = s),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? dark800 : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                s,
                style: TextStyle(
                  color: isSelected ? _getStatusColor(s) : Colors.grey,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _getStatusColor(String s) {
    if (s == 'A') return Colors.green;
    if (s == 'Q') return Colors.blue;
    return Colors.red;
  }

  void _addManualOneKg() {
    // CB (Cut/Bulk) orders have no ordered quantity limit
    final isCutBulkOrder = widget.order.orderNumber.startsWith('CB-');
    if (!isCutBulkOrder) {
      final remaining =
          widget.product.quantity -
          widget.product.manufacturedQuantity -
          _cumulativeQty;
      if (1.0 > remaining + 0.001) {
        _showErrorDialog(
          'Limit Exceeded',
          'Adding 1.00 KG would exceed the remaining order quantity of ${remaining.toStringAsFixed(2)} KG.',
        );
        return;
      }
    }

    setState(() {
      final manualScan = {
        'barcode': 'MANUAL-1KG-${DateTime.now().millisecondsSinceEpoch}',
        'manufacturedQty': 1.0,
        'scannedQty': 1.0,
        'productCode': widget.product.itemCode,
        'status': _status,
        'siteId': _selectedSite,
        'locationCode': _selectedLocation?.location,
        'timestamp': DateTime.now().toIso8601String(),
      };
      _scans.add(manualScan);
      if (_status == 'A') {
        _cumulativeQty += 1.0;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Added 1.00 KG manually'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 1),
      ),
    );
  }

  Widget _buildScannerView() {
    return Container(
      height: 300,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: orange, width: 2),
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AppBarcodeScanner(
              onScan: (code) {
                if (_pendingScan != null) return;
                _handleScan(code);
              },
            ),
          ),
          if (_pendingScan != null)
            Container(
              color: Colors.black54,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  decoration: BoxDecoration(
                    color: dark800,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: orange),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Scan Detected',
                        style: TextStyle(
                          color: orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${widget.product.formatQuantity(_pendingScan!['manufacturedQty'])} ${widget.product.unit}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _pendingScan!['barcode'],
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _savePendingScan,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 48),
                        ),
                        child: const Text('SAVE SCAN'),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          _pendingScan = null;
                        }),

                        child: const Text(
                          'Discard',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            top: 10,
            right: 10,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: _toggleScanner,
            ),
          ),
          const Center(
            child: Icon(Icons.qr_code_scanner, color: Colors.white24, size: 80),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: dark800,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Text(
            'Manufactured Quantity',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.product.formatQuantity(_cumulativeQty),
                style: const TextStyle(
                  color: orange,
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                widget.product.unit,
                style: const TextStyle(color: Colors.grey, fontSize: 20),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _toggleScanner,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Scanner', style: TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: orange,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 1,
                child: ElevatedButton(
                  onPressed: _addManualOneKg,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white10,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                      side: const BorderSide(color: Colors.white24),
                    ),
                  ),
                  child: const Text(
                    'SCAN 1KG',
                    style: TextStyle(height: 1.1, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => _showManualScanDialog(),
            child: const Text(
              'Enter Barcode Manually',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionFooter() {
    final isReconciled =
        (_cumulativeQty +
                widget.product.manufacturedQuantity -
                widget.product.quantity)
            .abs() <
        0.001;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isReconciled)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Remaining: ${widget.product.formatQuantity(widget.product.quantity - widget.product.manufacturedQuantity - _cumulativeQty)} ${widget.product.unit}',
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: (_isSaving || _scans.isEmpty)
                      ? null
                      : _saveAndUpload,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isReconciled ? orange : Colors.blueGrey,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: _isSaving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          isReconciled
                              ? 'Complete & Log Batch'
                              : 'Save Progress & Continue',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _savePendingScan() {
    if (_pendingScan == null) return;
    setState(() {
      final scanWithMetadata = Map<String, dynamic>.from(_pendingScan!);
      scanWithMetadata['status'] = _status;
      scanWithMetadata['siteId'] = _selectedSite;
      scanWithMetadata['locationCode'] = _selectedLocation?.location;

      _scans.add(scanWithMetadata);
      if (_status == 'A') {
        _cumulativeQty += _pendingScan!['manufacturedQty'] as double;
      }
      _pendingScan = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Scan saved'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 1),
      ),
    );
  }

  Widget _buildScannedItemsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Individual Scans',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 12),
        ..._scans.indexed
            .map((indexedScan) {
              final index = indexedScan.$1;
              final scan = indexedScan.$2;
              return ScanItemCard(
                lineNumber: _scans.length - index,
                scan: scan,
                unit: widget.product.unit,
                onDelete: () {
                  setState(() {
                    _scans.removeAt(index);
                    if (scan['status'] == 'A') {
                      _cumulativeQty -= scan['weight'] as double;
                    }
                  });
                },
              );
            })
            .toList()
            .reversed,
      ],
    );
  }

  void _showManualScanDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: dark800,
        title: const Text(
          'Manual Entry',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: 'Enter barcode number',
            hintStyle: TextStyle(color: Colors.grey),
          ),
          onSubmitted: (v) {
            Navigator.pop(context);
            _handleScan(v);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _handleScan(controller.text);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showConfirmationPrompt(BarcodeModel result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: dark800,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: orange),
            const SizedBox(width: 8),
            const Text('Confirm Scan', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPromptRow('Product:', result.itemCode),
            const SizedBox(height: 8),
            _buildPromptRow('Barcode:', result.processedBarcode),
            const SizedBox(height: 8),
            _buildPromptRow(
              'Weight:',
              '${BarcodeProcessor.formatQuantity(result.manufacturedQty, widget.product.unit)} ${widget.product.unit}',
              isBold: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _pendingScan = null);
              Navigator.pop(context);
            },
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _savePendingScan();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Widget _buildPromptRow(String label, String value, {bool isBold = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: isBold ? orange : Colors.white,
              fontSize: 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showLocationPicker() async {
    // Re-use logic or similar modal as before
    // Simplified for this refactor to focus on scanner
    final TextEditingController searchController = TextEditingController();
    List<LocationLookup> filteredLocations = List.from(_locations);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: dark800,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.7,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Select Target Location',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: searchController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search locations...',
                  hintStyle: const TextStyle(color: Colors.grey),
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  filled: true,
                  fillColor: const Color(0xFF2C2C2E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (value) {
                  setModalState(() {
                    filteredLocations = _locations
                        .where(
                          (l) => l.fullInfo.toLowerCase().contains(
                            value.toLowerCase(),
                          ),
                        )
                        .toList();
                  });
                },
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: filteredLocations.length,
                  itemBuilder: (context, index) {
                    final loc = filteredLocations[index];
                    final isSelected =
                        _selectedLocation?.location == loc.location;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      title: Text(
                        loc.location ?? '',
                        style: TextStyle(
                          color: isSelected ? orange : Colors.white,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        '${loc.locationTypeName} - ${loc.warehouseName}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                      trailing: isSelected
                          ? Icon(Icons.check, color: orange)
                          : null,
                      onTap: () {
                        setState(() => _selectedLocation = loc);
                        _saveLastLocation(loc.location!);
                        Navigator.pop(context);
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
}
