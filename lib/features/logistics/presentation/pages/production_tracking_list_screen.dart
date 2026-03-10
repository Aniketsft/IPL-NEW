import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:enterprise_auth_mobile/features/manufacturing/bloc/manufacturing_bloc.dart';
import 'package:enterprise_auth_mobile/features/manufacturing/bloc/manufacturing_event.dart';
import 'package:enterprise_auth_mobile/features/manufacturing/bloc/manufacturing_state.dart';
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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    context.read<ManufacturingBloc>().add(
      const LoadProductionTrackingRequested(),
    );
  }

  void _applyFilters() {
    context.read<ManufacturingBloc>().add(
      const LoadProductionTrackingRequested(),
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
                    final code = it.itemCode.toLowerCase();
                    final desc = it.description.toLowerCase();
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
        ],
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
          item.itemCode,
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
              item.description,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStat('Ordered', item.quantity.toStringAsFixed(0)),
                _buildStat('Remaining', item.remaining.toStringAsFixed(0)),
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
        onTap: () async {
          // Since we don't have the full SalesOrder object here easily without joining,
          // we'll pass a dummy header or handle it appropriately.
          // For now, navigating to detail is fine if we can reconstruct the entity.
          final result = await Navigator.push(
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
          if (result == true) {
            _applyFilters();
          }
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
