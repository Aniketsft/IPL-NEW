import 'package:flutter/material.dart';
import 'package:enterprise_auth_mobile/core/widgets/standard_filter.dart';
import '../../../../core/widgets/industrial_module_layout.dart';
import 'package:enterprise_auth_mobile/core/widgets/filter_input_widgets.dart';


class StockControlScreen extends StatefulWidget {
  const StockControlScreen({super.key});

  @override
  State<StockControlScreen> createState() => _StockControlScreenState();
}

class _StockControlScreenState extends State<StockControlScreen> {
  final _searchController = TextEditingController();
  final List<StockItem> _stock = [
    StockItem(
      id: 'SKU-001',
      name: 'Aluminium Plate 5mm',
      location: 'WH-A1',
      qty: 1250,
      unit: 'PCS',
    ),
    StockItem(
      id: 'SKU-002',
      name: 'Steel Sheet 2mm',
      location: 'WH-B2',
      qty: 85,
      unit: 'KG',
    ),
    StockItem(
      id: 'SKU-005',
      name: 'Steel Bolt M8',
      location: 'WH-A2',
      qty: 5400,
      unit: 'PCS',
    ),
    StockItem(
      id: 'SKU-102',
      name: 'Nylon Bushing 10mm',
      location: 'WH-C1',
      qty: 12,
      unit: 'PCS',
    ),
    StockItem(
      id: 'SKU-089',
      name: 'Copper Coil 2.5mm',
      location: 'WH-A1',
      qty: 450,
      unit: 'M',
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.toLowerCase();
    final filtered = _stock
        .where(
          (s) =>
              s.id.toLowerCase().contains(query) ||
              s.name.toLowerCase().contains(query),
        )
        .toList();

    return IndustrialModuleLayout(
      title: 'STOCK CONTROL',
      body: Column(
        children: [
          StandardFilter(
            onApply: () => setState(() {}),
            searchController: _searchController,
            onSearchChanged: (_) => setState(() {}),
            onReset: () {
              _searchController.clear();
              setState(() {});
            },
            child: Column(
              children: [
                FilterDropdown(
                  label: 'Warehouse',
                  value: 'All Warehouses',
                  options: const ['All Warehouses', 'WH-A1', 'WH-B2', 'WH-C1'],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filtered.length,
              itemBuilder: (context, index) => _buildStockCard(filtered[index]),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildStockCard(StockItem item) {
    final bool isLowStock = item.qty < 50;

    return Card(
      color: const Color(0xFF252528),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.id,
                      style: const TextStyle(
                        color: Color(0xFFFF9800),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                _buildQuantityBadge(item.qty, item.unit, isLowStock),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 14,
                  color: Colors.white38,
                ),
                const SizedBox(width: 4),
                Text(
                  item.location,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
                const Spacer(),
                const Text(
                  'Last Updated: 2m ago',
                  style: TextStyle(color: Colors.white24, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuantityBadge(double qty, String unit, bool isLow) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isLow
            ? Colors.red.withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isLow ? Colors.red.withValues(alpha: 0.3) : Colors.white12,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            qty.toStringAsFixed(0),
            style: TextStyle(
              color: isLow ? Colors.red : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            unit,
            style: TextStyle(
              color: isLow ? Colors.red.withValues(alpha: 0.7) : Colors.white38,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class StockItem {
  final String id;
  final String name;
  final String location;
  final double qty;
  final String unit;

  StockItem({
    required this.id,
    required this.name,
    required this.location,
    required this.qty,
    required this.unit,
  });
}
