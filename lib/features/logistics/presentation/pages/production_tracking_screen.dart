import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/sales_order.dart';
import '../../domain/entities/sales_order_detail.dart';
import '../../data/repositories/delivery_repository.dart';

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
  final TextEditingController _lotDetailsController = TextEditingController(
    text: 'test',
  );
  String _status = 'A';
  double _currentScan = 0.0;
  double _cumulativeQty = 0.0;
  String _selectedLocation = 'N/A';
  String _selectedLot = 'N/A';
  List<Map<String, String>> _locations = [];
  List<Map<String, String>> _lots = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.product.location ?? 'Select Location';
    _selectedLot = widget.product.lotNumber ?? 'Select Lot';
    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    setState(() => _isLoading = true);
    try {
      final repository = context.read<DeliveryRepository>();

      // Fetch Locations if site is available
      if (widget.product.site != null) {
        final locs = await repository.getLocations(widget.product.site!);
        setState(() => _locations = locs);
      }

      // Fetch Lots if product code and site are available
      if (widget.product.site != null) {
        await _fetchLots();
      }
    } catch (e) {
      debugPrint('Error fetching tracking data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchLots() async {
    try {
      final repository = context.read<DeliveryRepository>();
      final filteredLots = await repository.fetchLots(
        widget.product.site!,
        widget.product.productCode,
        location: _selectedLocation == 'Select Location'
            ? null
            : _selectedLocation,
      );
      setState(() => _lots = filteredLots);
    } catch (e) {
      debugPrint('Error fetching lots: $e');
    }
  }

  void _saveAndUpdate() {
    // Implement save logic here
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF9800);
    const dark800 = Color(0xFF1E1E1E);
    const dark900 = Color(0xFF0D0D0D);

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
          IconButton(onPressed: () {}, icon: const Icon(Icons.logout)),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: orange))
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildHeaderCard(dark800),
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
            '${widget.product.productCode} - ${widget.product.productDescription}',
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
            widget.product.orderedQuantity.toStringAsFixed(2),
          ),
          const SizedBox(height: 12),
          _buildFieldRow(
            'Manufactured Qty:',
            widget.product.manufacturedQuantity.toStringAsFixed(2),
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 16),
          _buildActionTile(
            'Location',
            _selectedLocation,
            onTap: _showLocationPicker,
          ),
          const SizedBox(height: 12),
          _buildActionTile('Lot', _selectedLot, onTap: _showLotPicker),
          const SizedBox(height: 16),
          _buildLotDetailsField(),
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

  Widget _buildActionTile(
    String label,
    String value, {
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLotDetailsField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Lot Details',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _lotDetailsController,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF2C2C2E),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
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
                color: isSelected
                    ? const Color(0xFF1E1E1E)
                    : Colors.transparent,
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
          ElevatedButton.icon(
            onPressed: () => setState(() {
              _currentScan = 10.0;
              _cumulativeQty += 10.0;
            }),
            icon: const Icon(Icons.grid_view_rounded),
            label: const Text(
              'Scan Quantity',
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
        onPressed: _saveAndUpdate,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2C2C2E),
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        child: const Text(
          'Save & Update',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  void _showLocationPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _SearchPickerSheet(
        title: 'Location',
        items: _locations
            .map(
              (l) => {
                'code': l['location'] ?? '',
                'name': '${l['warehouse'] ?? ""} - ${l['type'] ?? ""}',
              },
            )
            .toList(),
        onSelected: (code) {
          if (code != null) {
            setState(() {
              _selectedLocation = code;
              _selectedLot = 'Select Lot'; // Reset lot when location changes
            });
            _fetchLots();
          }
        },
      ),
    );
  }

  void _showLotPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _SearchPickerSheet(
        title: 'Lot',
        items: _lots
            .map(
              (l) => {
                'code': l['lot'] ?? '',
                'name':
                    '${l['description'] ?? ""} (Qty: ${l['quantity'] ?? "0"})',
              },
            )
            .toList(),
        onSelected: (code) {
          if (code != null) setState(() => _selectedLot = code);
        },
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
            child: _filteredItems.isEmpty
                ? const Center(
                    child: Text(
                      'No results found',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
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
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
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
