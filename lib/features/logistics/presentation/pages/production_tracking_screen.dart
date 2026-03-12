import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/sales_order.dart';
import '../../domain/entities/sales_order_detail.dart';
import '../../data/repositories/delivery_repository.dart';
import '../../domain/entities/location_lookup.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  String _status = 'A';
  double _currentScan = 0.0;
  double _cumulativeQty = 0.0;
  bool _isLoading = false;
  bool _isSaving = false;
  List<LocationLookup> _locations = [];
  LocationLookup? _selectedLocation;
  bool _loadingLocations = false;

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    setState(() => _loadingLocations = true);
    try {
      final repository = context.read<DeliveryRepository>();
      final site = widget.product.site ?? 'IPL';
      final locations = await repository.getLocationLookups(site);
      final prefs = await SharedPreferences.getInstance();
      final lastLocation = prefs.getString('last_selected_location');

      if (mounted) {
        setState(() {
          _locations = locations;
          // Priority: 1. Last used location, 2. Product's current location, 3. First in list
          if (lastLocation != null) {
            final found = _locations.where((l) => l.location == lastLocation);
            _selectedLocation = found.isNotEmpty ? found.first : _getDefaultLocation();
          } else {
            _selectedLocation = _getDefaultLocation();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading locations: $e')));
      }
    } finally {
      if (mounted) setState(() => _loadingLocations = false);
    }
  }

  LocationLookup? _getDefaultLocation() {
    if (widget.product.location != null) {
      return _locations.firstWhere(
        (l) => l.location == widget.product.location,
        orElse: () => _locations.first,
      );
    }
    return _locations.isNotEmpty ? _locations.first : null;
  }

  Future<void> _saveLastLocation(String location) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_selected_location', location);
  }

  Future<void> _showLocationPicker(Color orange) async {
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

  Future<void> _saveAndUpdate() async {
    if (_cumulativeQty <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please scan items first')));
      return;
    }

    setState(() => _isSaving = true);
    try {
      final repository = context.read<DeliveryRepository>();

      final payload = {
        'itemCode': widget.product.itemCode,
        'description': widget.product.description,
        'scanAmountKg': _cumulativeQty,
        'soNumber': widget.order.orderNumber,
        'customerId': widget.order.customerCode,
        'customerDescription': widget.order.customerName,
        'itemStatus': _status, // A, Q, or R
        'location': _selectedLocation?.location,
        'lot': _selectedLocation
            ?.warehouse, // Using warehouse as lot placeholder if needed, or keeping it separate
      };

      await repository.saveProductionScan(payload);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Production data saved successfully')),
        );
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving production data: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _showScanDialog(Color orange) async {
    final TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: dark800,
        title: const Text('Scan Barcode', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Enter or scan barcode',
            hintStyle: const TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: orange),
            ),
          ),
          autofocus: true,
          onSubmitted: (value) async {
            Navigator.pop(context);
            await _handleScan(value);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _handleScan(controller.text);
            },
            style: ElevatedButton.styleFrom(backgroundColor: orange),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>?> _decodeBarcode(String barcode) async {
    final repository = context.read<DeliveryRepository>();
    return await repository.decodeBarcode(barcode);
  }

  Future<void> _handleScan(String barcode) async {
    if (barcode.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final decoded = await _decodeBarcode(barcode);

      if (mounted) {
        if (decoded != null) {
          final productCode = decoded['productCode'] as String;
          final weight = decoded['weight'] as double;

          // Check if productCode matches current product
          if (productCode == widget.product.itemCode) {
            setState(() {
              _currentScan = weight;
              _cumulativeQty += weight;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    Text('Valid scan ($barcode): $weight KG added'),
                backgroundColor: Colors.green,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'WRONG PRODUCT SCANNED: $productCode (Expected: ${widget.product.itemCode})',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('INVALID BARCODE: $barcode'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Validation error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _simulateScan() {
    setState(() {
      _currentScan = 1.0;
      _cumulativeQty += 1.0;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'SIMULATED SCAN: 1.0 KG added for product ${widget.product.itemCode}',
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 1),
      ),
    );
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
          'Production Tracking',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Text(
                widget.product.site ?? 'Main Plant',
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              // Show scanning instructions
            },
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildHeaderCard(dark800),
                      const SizedBox(height: 16),
                      _buildLocationSelector(dark800, orange),
                      const SizedBox(height: 16),
                      _buildTrackingParamsCard(dark800, orange),
                      const SizedBox(height: 16),
                      _buildScanningCard(dark800, orange),
                    ],
                  ),
                ),
              ),
              _buildFooter(dark800, orange),
            ],
          ),
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: orange),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(Color dark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildInfoRow(
            'Customer:',
            '${widget.order.customerCode} - ${widget.order.customerName}',
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            'Product:',
            '${widget.product.itemCode} - ${widget.product.description}',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
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
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrackingParamsCard(Color dark, Color orange) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildFieldRow(
            'Order Qty:',
            widget.product.quantity.toStringAsFixed(2),
          ),
          const SizedBox(height: 12),
          _buildFieldRow(
            'Manufactured Qty:',
            widget.product.manufacturedQuantity.toStringAsFixed(2),
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                'Status',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const Spacer(),
              _buildStatusToggle(orange),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFieldRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 15)),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusToggle(Color orange) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2E),
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
                color: isSelected ? const Color(0xFF1E1E1E) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                s,
                style: TextStyle(
                  color: isSelected ? orange : Colors.grey,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildScanningCard(Color dark, Color orange) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: dark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Text(
            'Current Scan',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            _currentScan.toStringAsFixed(2),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 32,
            ),
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white10),
          const SizedBox(height: 16),
          const Text(
            'Cumulative Scanned Quantity',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 12),
          Text(
            _cumulativeQty.toStringAsFixed(2),
            style: TextStyle(
              color: orange,
              fontWeight: FontWeight.bold,
              fontSize: 48,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _showScanDialog(orange),
                  icon: const Icon(Icons.grid_view_rounded),
                  label: const Text(
                    'Scan Barcode',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: orange,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Material(
                color: const Color(0xFF2C2C2E),
                borderRadius: BorderRadius.circular(28),
                child: IconButton(
                  onPressed: _simulateScan,
                  icon: const Icon(Icons.add_task_rounded, color: Colors.green),
                  tooltip: 'Simulate 1.0kg Scan',
                  iconSize: 28,
                  padding: const EdgeInsets.all(14),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSelector(Color dark, Color orange) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Target Location',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 12),
          _loadingLocations
              ? const LinearProgressIndicator(color: Colors.orange)
              : InkWell(
                  onTap: () => _showLocationPicker(orange),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2C2C2E),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _selectedLocation?.fullInfo ?? 'Select Location',
                            style: TextStyle(
                              color: _selectedLocation == null
                                  ? Colors.grey
                                  : Colors.white,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Colors.grey,
                        ),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildFooter(Color dark, Color orange) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: ElevatedButton(
        onPressed: _isSaving ? null : _saveAndUpdate,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2C2C2E),
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        child: _isSaving
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Text(
                'Save & Update',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }
}
