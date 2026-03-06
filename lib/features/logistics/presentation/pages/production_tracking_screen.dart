import 'package:flutter/material.dart';
import '../../domain/entities/sales_order.dart';
import '../../domain/entities/sales_order_detail.dart';

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

  // Q = Quarantine, A = Approved, R = Rejected
  String _status = 'A';
  double _currentScan = 0.0;
  double _cumulativeQty = 0.0;

  String _selectedLocation = 'Warehouse A-2';
  String _selectedLot = 'LOT20240811A';

  final List<String> _locations = [
    'Warehouse A-2',
    'Main Floor',
    'Cold Storage',
    'Sector B-4',
    'Loading Dock',
  ];

  final List<String> _lots = [
    'LOT20240811A',
    'LOT20240811B',
    'LOT20240812A',
    'LOT20240901X',
    'LOT20240905Y',
  ];

  void _saveAndUpdate() {
    if (_cumulativeQty > 0) {
      // TODO: Replace with new Production Tracking feature
      // context.read<OrderBloc>().add(
      //   UpdateProductQty(...)
      // );
    }
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _lotDetailsController.dispose();
    super.dispose();
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
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              'Main Plant',
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildOrderInfoCard(dark800, orange),
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

  // ────────────────────────────────── Cards ──────────────────────────────────

  Widget _buildOrderInfoCard(Color dark800, Color orange) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark800,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
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
            style: TextStyle(color: Colors.grey[500], fontSize: 14),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrackingParamsCard(Color dark800, Color orange) {
    const dark700 = Color(0xFF2C2C2E);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark800,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Order Qty
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Order Qty:', style: TextStyle(color: Colors.grey[500])),
              Text(
                widget.product.orderedQuantity.toStringAsFixed(2),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Colors.white10),
          const SizedBox(height: 16),
          // Manufactured Qty
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Manufactured Qty:',
                style: TextStyle(color: Colors.grey[500]),
              ),
              Text(
                widget.product.manufacturedQuantity.toStringAsFixed(2),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Location picker
          _buildActionTile(
            'Location',
            _selectedLocation,
            onTap: () => _showSelectionSheet(
              context,
              'Select Location',
              _locations,
              _selectedLocation,
              (val) => setState(() => _selectedLocation = val),
              orange,
            ),
          ),
          const SizedBox(height: 16),
          // Lot picker
          _buildActionTile(
            'Lot',
            _selectedLot,
            onTap: () => _showSelectionSheet(
              context,
              'Select Lot',
              _lots,
              _selectedLot,
              (val) => setState(() => _selectedLot = val),
              orange,
            ),
          ),
          const SizedBox(height: 16),
          // Lot details text input
          Text(
            'Lot Details',
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: dark700,
              borderRadius: BorderRadius.circular(8),
            ),
            child: TextField(
              controller: _lotDetailsController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: const InputDecoration(border: InputBorder.none),
            ),
          ),
          const SizedBox(height: 24),
          // Status toggle Q / A / R
          Row(
            children: [
              Text(
                'Status',
                style: TextStyle(color: Colors.grey[500], fontSize: 14),
              ),
              const Spacer(),
              _buildStatusToggle(orange),
            ],
          ),
        ],
      ),
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
        Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 13)),
        const SizedBox(height: 4),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Colors.grey[600],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusToggle(Color orange) {
    const dark700 = Color(0xFF2C2C2E);
    return Container(
      decoration: BoxDecoration(
        color: dark700,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: ['Q', 'A', 'R'].map((s) {
          final isSelected = _status == s;
          return GestureDetector(
            onTap: () => setState(() => _status = s),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF1E1E1E)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: isSelected ? Border.all(color: Colors.white10) : null,
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

  Widget _buildScanningCard(Color dark800, Color orange) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: dark800,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            'Current Scan',
            style: TextStyle(color: Colors.grey[500], fontSize: 14),
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
          Text(
            'Cumulative Scanned Quantity',
            style: TextStyle(color: Colors.grey[500], fontSize: 14),
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
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _currentScan = 10;
                  _cumulativeQty += 10;
                });
              },
              icon: const Icon(Icons.grid_view_rounded),
              label: const Text(
                'Scan Quantity',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(Color dark800, Color orange) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D0D),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: ElevatedButton(
        onPressed: _saveAndUpdate,
        style: ElevatedButton.styleFrom(
          backgroundColor: dark800,
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

  // ─────────────────────────── Bottom Sheet Picker ──────────────────────────

  void _showSelectionSheet(
    BuildContext context,
    String title,
    List<String> options,
    String currentValue,
    Function(String) onSelect,
    Color orange,
  ) {
    String searchQuery = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final filteredOptions = options
              .where((o) => o.toLowerCase().contains(searchQuery.toLowerCase()))
              .toList();

          return Container(
            height: MediaQuery.of(context).size.height * 0.7,
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E1E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // Drag handle
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Title row
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                // Search
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    onChanged: (val) => setSheetState(() => searchQuery = val),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: Colors.white38,
                      ),
                      filled: true,
                      fillColor: const Color(0xFF2C2C2E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // List
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: filteredOptions.length,
                    itemBuilder: (context, index) {
                      final option = filteredOptions[index];
                      final isSelected = option == currentValue;
                      return ListTile(
                        onTap: () {
                          onSelect(option);
                          Navigator.pop(ctx);
                        },
                        title: Text(
                          option,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected ? orange : Colors.white,
                          ),
                        ),
                        trailing: isSelected
                            ? Icon(Icons.check, color: orange)
                            : null,
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
