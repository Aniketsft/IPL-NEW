import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:enterprise_auth_mobile/features/manufacturing/bloc/manufacturing_bloc.dart';
import 'package:enterprise_auth_mobile/features/manufacturing/bloc/manufacturing_event.dart';
import 'package:enterprise_auth_mobile/features/manufacturing/bloc/manufacturing_state.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/delivery_repository.dart';
import 'production_tracking_screen.dart';
import '../../domain/entities/sales_order.dart';

class ProductionTrackingListScreen extends StatefulWidget {
  const ProductionTrackingListScreen({super.key});

  @override
  State<ProductionTrackingListScreen> createState() =>
      _ProductionTrackingListScreenState();
}

class _ProductionTrackingListScreenState
    extends State<ProductionTrackingListScreen> {
  String? _selectedLocation;
  List<Map<String, String>> _locations = [];
  bool _isLoadingLocations = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchLocations();
    context.read<ManufacturingBloc>().add(
      const LoadProductionTrackingRequested(),
    );
  }

  Future<void> _fetchLocations() async {
    setState(() => _isLoadingLocations = true);
    try {
      final repository = context.read<DeliveryRepository>();
      // Using 'IPL' as default site for lookup if not provided
      final locs = await repository.getLocations('IPL');
      setState(() => _locations = locs);
    } catch (e) {
      debugPrint('Error fetching locations: $e');
    } finally {
      setState(() => _isLoadingLocations = false);
    }
  }

  void _applyFilters() {
    context.read<ManufacturingBloc>().add(
      LoadProductionTrackingRequested(location: _selectedLocation),
    );
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF9800);
    const dark800 = Color(0xFF1E1E1E);
    const dark900 = Color(0xFF0D0D0D);

    return Scaffold(
      backgroundColor: dark900,
      appBar: AppBar(
        title: const Text(
          'Production Tracking List',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                'IPL - Main Plant',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(dark800, orange),
          Expanded(
            child: BlocBuilder<ManufacturingBloc, ManufacturingState>(
              builder: (context, state) {
                if (state is ManufacturingLoadInProgress) {
                  return const Center(
                    child: CircularProgressIndicator(color: orange),
                  );
                }
                if (state is ManufacturingFailure) {
                  return Center(
                    child: Text(
                      state.message,
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }
                if (state is ProductionTrackingLoaded) {
                  final filteredItems = state.items.where((it) {
                    final code = it.productCode.toLowerCase();
                    final desc = it.productDescription.toLowerCase();
                    return code.contains(_searchQuery.toLowerCase()) ||
                        desc.contains(_searchQuery.toLowerCase());
                  }).toList();

                  if (filteredItems.isEmpty) {
                    return const Center(
                      child: Text(
                        'No items found',
                        style: TextStyle(color: Colors.grey),
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: filteredItems.length,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemBuilder: (context, index) {
                      final item = filteredItems[index];
                      return _buildProductCard(item, dark800, orange);
                    },
                  );
                }
                return const Center(
                  child: Text(
                    'Initialize tracking...',
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(Color dark, Color orange) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => _searchQuery = val),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search Product...',
              hintStyle: const TextStyle(color: Colors.white24, fontSize: 14),
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
          Row(
            children: [
              Expanded(
                child: _buildPickerTile(
                  'Location',
                  _selectedLocation,
                  _locations
                      .map(
                        (l) => {
                          'code': l['location'] ?? '',
                          'name':
                              '${l['warehouse'] ?? ""} - ${l['type'] ?? ""}',
                        },
                      )
                      .toList(),
                  (code) => setState(() => _selectedLocation = code),
                  orange,
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _applyFilters,
                style: ElevatedButton.styleFrom(
                  backgroundColor: orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Filter',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPickerTile(
    String label,
    String? currentValue,
    List<Map<String, String>> items,
    Function(String?) onSelected,
    Color orange,
  ) {
    final valueText = currentValue ?? 'All Locations';

    return InkWell(
      onTap: () => _showSearchPicker(label, items, onSelected),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.location_on_outlined,
              color: Colors.grey,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                valueText,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: Colors.grey, size: 20),
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
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _SearchPickerSheet(
        title: title,
        items: items,
        onSelected: (code) {
          onSelected(code);
          _applyFilters();
        },
      ),
    );
  }

  Widget _buildProductCard(dynamic item, Color dark, Color orange) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: dark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(
          item.productCode,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              item.productDescription,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStat('Ordered', item.orderedQuantity.toStringAsFixed(0)),
                _buildStat(
                  'Remaining',
                  item.remainingQuantity.toStringAsFixed(0),
                ),
                _buildStat(
                  'Produced',
                  item.manufacturedQuantity.toStringAsFixed(0),
                  color: orange,
                ),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: () {
          // Since we don't have the full SalesOrder object here easily without joining,
          // we'll pass a dummy header or handle it appropriately.
          // For now, navigating to detail is fine if we can reconstruct the entity.
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProductionTrackingScreen(
                order: SalesOrder(
                  id: item.soNumber,
                  orderNumber: item.soNumber,
                  customerCode: item.customerCode ?? 'N/A',
                  customerName: item.customerName ?? 'N/A',
                  deliveryDate: '',
                  date: DateTime.now(),
                  salesManCode1: '',
                  salesManCode2: '',
                  site: item.site,
                ),
                product: item,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStat(
    String label,
    String value, {
    Color color = Colors.white70,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ],
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
                    itemCount: _filteredItems.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return ListTile(
                          title: const Text(
                            'All Locations',
                            style: TextStyle(color: Colors.orange),
                          ),
                          onTap: () {
                            widget.onSelected(null);
                            Navigator.pop(context);
                          },
                        );
                      }
                      final item = _filteredItems[index - 1];
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
