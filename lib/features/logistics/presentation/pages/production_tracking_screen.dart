import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../domain/entities/sales_order.dart';
import '../../domain/entities/sales_order_detail.dart';
import '../../data/repositories/delivery_repository.dart';
import '../../domain/entities/location_lookup.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart';

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
  List<LocationLookup> _locations = [];
  LocationLookup? _selectedLocation;
  MobileScannerController? _scannerController;
  bool _isScannerVisible = false;

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    super.dispose();
  }

  Future<void> _fetchInitialData() async {
    try {
      final repository = context.read<DeliveryRepository>();
      final site = widget.product.site ?? 'IPL';
      final locations = await repository.getLocationLookups(site);
      final prefs = await SharedPreferences.getInstance();
      final lastLocation = prefs.getString('last_selected_location');

      if (mounted) {
        setState(() {
          _locations = locations;
          if (lastLocation != null) {
            _selectedLocation = _locations.firstWhereOrNull((l) => l.location == lastLocation);
          }
          _selectedLocation ??= _locations.firstWhereOrNull((l) => l.warehouseName == 'Main Warehouse');
          // If main warehouse not found, default to first available
          _selectedLocation ??= _locations.isNotEmpty ? _locations.first : null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading locations: $e')));
      }
    }
  }

  Future<void> _saveLastLocation(String location) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_selected_location', location);
  }

  Future<void> _toggleScanner() async {
    if (_isScannerVisible) {
      setState(() => _isScannerVisible = false);
      _scannerController?.stop();
    } else {
      final status = await Permission.camera.request();
      if (status.isGranted) {
        setState(() {
          _isScannerVisible = true;
          _scannerController ??= MobileScannerController();
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Camera permission is required to scan barcodes')),
          );
        }
      }
    }
  }

  Future<void> _handleScan(String barcode) async {
    if (barcode.isEmpty) return;

    try {
      final repository = context.read<DeliveryRepository>();
      final decoded = await repository.decodeBarcode(barcode);

      if (mounted) {
        if (decoded != null) {
          final productCode = decoded['productCode'] as String;
          final weight = decoded['weight'] as double;

          // RULE 1: ITEM MATCH
          if (productCode != widget.product.itemCode) {
            _showErrorDialog(
              'Wrong Product',
              'Scanned: $productCode\nExpected: ${widget.product.itemCode}',
            );
            return;
          }

          // RULE 2: RECONCILIATION / OVER-SCAN (Zero-Tolerance)
          // CB (Cut/Bulk) orders have no ordered quantity limit — manufactured can exceed ordered
          final isCutBulkOrder = widget.order.orderNumber.startsWith('CB-');
          if (!isCutBulkOrder) {
            final remaining = widget.product.quantity - widget.product.manufacturedQuantity - _cumulativeQty;
            if (weight > remaining + 0.001) { // Strict zero-tolerance
              _showErrorDialog(
                'Limit Exceeded',
                'Scanning ${weight.toStringAsFixed(2)} KG would exceed the remaining order quantity of ${remaining.toStringAsFixed(2)} KG.',
              );
              return;
            }
          }

          setState(() {
            _pendingScan = {
              'barcode': barcode,
              'productCode': productCode,
              'weight': weight,
              'timestamp': DateTime.now().toIso8601String(),
            };
          });
          _scannerController?.stop();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Detected: $weight KG. Click SAVE SCAN to log.'),
              backgroundColor: orange,
              duration: const Duration(seconds: 2),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid barcode format'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan error: $e')),
        );
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
      };

      await repository.saveProductionScan(payload);

      if (mounted) {
        final isPartial = (_cumulativeQty + widget.product.manufacturedQuantity - widget.product.quantity).abs() > 0.001;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isPartial 
                ? 'Partial progress saved successfully' 
                : 'Production log completed and saved'),
            backgroundColor: isPartial ? Colors.blue : Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save log: $e')),
        );
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
        title: const Text('Production Scan', style: TextStyle(fontWeight: FontWeight.bold)),
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
      decoration: BoxDecoration(color: dark800, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.order.customerName, style: const TextStyle(color: orange, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(widget.product.description, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
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
      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
    );
  }

  Widget _buildLocationSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: dark800, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Target Inventory Location', style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => _showLocationPicker(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(color: darkBorder, borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  const Icon(Icons.location_on_outlined, color: orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedLocation?.fullInfo ?? 'Select Location...',
                      style: TextStyle(color: _selectedLocation == null ? Colors.grey : Colors.white),
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
      decoration: BoxDecoration(color: dark800, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _statItem('Order Qty', '${widget.product.quantity} KG'),
              _statItem('Already Done', '${widget.product.manufacturedQuantity} KG'),
              _statItem('Remaining', '${(widget.product.quantity - widget.product.manufacturedQuantity).toStringAsFixed(2)} KG'),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white10),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Production Status', style: TextStyle(color: Colors.grey)),
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
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _statusToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: darkBorder, borderRadius: BorderRadius.circular(8)),
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
      final remaining = widget.product.quantity - widget.product.manufacturedQuantity - _cumulativeQty;
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
        'barcode': 'MANUAL-${DateTime.now().millisecondsSinceEpoch}',
        'productCode': widget.product.itemCode,
        'weight': 1.0,
        'timestamp': DateTime.now().toIso8601String(),
        'isManual': true,
      };
      _scans.add(manualScan);
      _cumulativeQty += 1.0;
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
      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12), border: Border.all(color: orange, width: 2)),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: MobileScanner(
              controller: _scannerController!,
              onDetect: (capture) {
                if (_pendingScan != null) return;
                final List<Barcode> barcodes = capture.barcodes;
                if (barcodes.isNotEmpty) {
                  final String? code = barcodes.first.rawValue;
                  if (code != null) {
                    _handleScan(code);
                  }
                }
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
                      const Text('Scan Detected', style: TextStyle(color: orange, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Text(
                        '${_pendingScan!['weight'].toStringAsFixed(2)} KG',
                        style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(_pendingScan!['barcode'], style: const TextStyle(color: Colors.grey, fontSize: 10)),
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
                          _scannerController?.start();
                        }),
                        child: const Text('Discard', style: TextStyle(color: Colors.red)),
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
      decoration: BoxDecoration(color: dark800, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          const Text('Scan Quantity', style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _cumulativeQty.toStringAsFixed(2),
                style: const TextStyle(color: orange, fontSize: 48, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              const Text('KG', style: TextStyle(color: Colors.grey, fontSize: 20)),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
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
                  child: const Text('+ 1 KG', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => _showManualScanDialog(),
            child: const Text('Enter Barcode Manually', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Widget _buildActionFooter() {
    final isReconciled = (_cumulativeQty + widget.product.manufacturedQuantity - widget.product.quantity).abs() < 0.001;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.white10))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isReconciled)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Remaining: ${(widget.product.quantity - widget.product.manufacturedQuantity - _cumulativeQty).toStringAsFixed(2)} KG',
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: (_isSaving || _cumulativeQty <= 0) ? null : _saveAndUpload,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isReconciled ? orange : Colors.blueGrey,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  ),
                  child: _isSaving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          isReconciled ? 'Complete & Log Batch' : 'Save Progress & Continue',
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
      _scans.add(_pendingScan!);
      _cumulativeQty += _pendingScan!['weight'] as double;
      _pendingScan = null;
    });
    _scannerController?.start();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Scan saved'), backgroundColor: Colors.green, duration: Duration(seconds: 1)),
    );
  }

  Widget _buildScannedItemsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Individual Scans', style: TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 8),
        ..._scans.reversed.map((scan) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: dark800, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white10)),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_outlined, color: Colors.grey, size: 16),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(scan['barcode'], style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace')),
                        Text(scan['timestamp'].toString().substring(11, 16), style: const TextStyle(color: Colors.grey, fontSize: 10)),
                      ],
                    ),
                  ),
                  Text(
                    '${(scan['weight'] as double).toStringAsFixed(2)} KG',
                    style: const TextStyle(color: orange, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20),
                    onPressed: () {
                      setState(() {
                        _scans.remove(scan);
                        _cumulativeQty -= scan['weight'] as double;
                      });
                    },
                  ),
                ],
              ),
            )),
      ],
    );
  }

  void _showManualScanDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: dark800,
        title: const Text('Manual Entry', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'Paste barcode here', hintStyle: TextStyle(color: Colors.grey)),
          onSubmitted: (v) {
             Navigator.pop(context);
             _handleScan(v);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () {
            Navigator.pop(context);
            _handleScan(controller.text);
          }, child: const Text('Add')),
        ],
      ),
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
                        .where((l) =>
                            l.fullInfo.toLowerCase().contains(value.toLowerCase()))
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
                    final isSelected = _selectedLocation?.location == loc.location;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      title: Text(
                        loc.location ?? '',
                        style: TextStyle(
                          color: isSelected ? orange : Colors.white,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        '${loc.locationTypeName} - ${loc.warehouseName}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                      trailing: isSelected ? Icon(Icons.check, color: orange) : null,
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
