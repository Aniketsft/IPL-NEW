import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:enterprise_auth_mobile/features/manufacturing/bloc/manufacturing_bloc.dart';
import 'package:enterprise_auth_mobile/features/manufacturing/bloc/manufacturing_event.dart';
import 'package:enterprise_auth_mobile/features/manufacturing/bloc/manufacturing_state.dart';
import '../../domain/entities/sales_order_detail.dart';
import 'production_tracking_so_breakdown_screen.dart';

class ProductionTrackingProductListScreen extends StatefulWidget {
  const ProductionTrackingProductListScreen({super.key});

  @override
  State<ProductionTrackingProductListScreen> createState() =>
      _ProductionTrackingProductListScreenState();
}

class _ProductionTrackingProductListScreenState
    extends State<ProductionTrackingProductListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    context.read<ManufacturingBloc>().add(const LoadProductionTrackingRequested());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Group flat list of SalesOrderDetail by itemCode
  Map<String, List<SalesOrderDetail>> _groupByProduct(
      List<SalesOrderDetail> items) {
    final Map<String, List<SalesOrderDetail>> grouped = {};
    for (final item in items) {
      grouped.putIfAbsent(item.itemCode, () => []).add(item);
    }
    return grouped;
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
          'Production Tracking',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: dark800,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Search by product code or name...',
                hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                prefixIcon: Icon(Icons.search, color: Colors.grey),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),
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
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  );
                }
                if (state is ProductionTrackingLoaded) {
                  final grouped = _groupByProduct(state.items);

                  // Filter by search query
                  final filteredKeys = grouped.keys.where((code) {
                    final desc =
                        grouped[code]!.first.description.toLowerCase();
                    return code.toLowerCase().contains(
                              _searchQuery.toLowerCase(),
                            ) ||
                        desc.contains(_searchQuery.toLowerCase());
                  }).toList()
                    ..sort();

                  if (filteredKeys.isEmpty) {
                    return const Center(
                      child: Text(
                        'No products found',
                        style: TextStyle(color: Colors.grey),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    itemCount: filteredKeys.length,
                    itemBuilder: (context, index) {
                      final code = filteredKeys[index];
                      final soItems = grouped[code]!;
                      return _buildProductCard(
                          context, code, soItems, dark800, orange);
                    },
                  );
                }
                return const Center(
                  child: Text(
                    'Loading production data...',
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

  Widget _buildProductCard(
    BuildContext context,
    String itemCode,
    List<SalesOrderDetail> soItems,
    Color dark,
    Color orange,
  ) {
    final description = soItems.first.description;
    final totalOrdered = soItems.fold<double>(0, (s, i) => s + i.quantity);
    final totalManufactured =
        soItems.fold<double>(0, (s, i) => s + i.manufacturedQuantity);
    final aggProgress = totalOrdered > 0
        ? (totalManufactured / totalOrdered).clamp(0.0, 1.0)
        : (totalManufactured > 0 ? 1.0 : 0.0);
    final soCount = soItems.length;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProductionTrackingSoBreakdownScreen(
              itemCode: itemCode,
              description: description,
              soItems: soItems,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: dark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        itemCode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$soCount SO${soCount != 1 ? 's' : ''}',
                    style: const TextStyle(
                      color: Color(0xFFFF9800),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: aggProgress,
                backgroundColor: Colors.white10,
                valueColor: AlwaysStoppedAnimation<Color>(orange),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 10),
            // Stats row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStat(
                    'Ordered', totalOrdered.toStringAsFixed(0), Colors.white70),
                _buildStat(
                    'Produced',
                    totalManufactured.toStringAsFixed(0),
                    orange),
                _buildStat(
                    'Progress',
                    '${(aggProgress * 100).toStringAsFixed(1)}%',
                    aggProgress >= 1.0 ? Colors.greenAccent : Colors.white70),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 2),
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
