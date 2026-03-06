import 'package:flutter/material.dart';
import 'package:enterprise_auth_mobile/core/widgets/industrial_module_layout.dart';

class PickingScreen extends StatefulWidget {
  const PickingScreen({super.key});

  @override
  State<PickingScreen> createState() => _PickingScreenState();
}

class _PickingScreenState extends State<PickingScreen> {
  final _searchController = TextEditingController();
  final List<PickItem> _items = [
    PickItem(
      id: 'SKU-001',
      name: 'Aluminium Plate 5mm',
      location: 'A-12-01',
      qty: 50,
    ),
    PickItem(
      id: 'SKU-005',
      name: 'Steel Bolt M8',
      location: 'B-04-22',
      qty: 200,
    ),
    PickItem(
      id: 'SKU-102',
      name: 'Nylon Bushing 10mm',
      location: 'C-01-05',
      qty: 15,
    ),
    PickItem(
      id: 'SKU-089',
      name: 'Copper Coil 2.5mm',
      location: 'A-03-10',
      qty: 12,
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
    final filtered = _items
        .where(
          (i) =>
              i.id.toLowerCase().contains(query) ||
              i.name.toLowerCase().contains(query),
        )
        .toList();

    return IndustrialModuleLayout(
      title: 'PICKING LIST',
      body: Column(
        children: [
          _buildSearchHeader(),
          _buildProgressIndicator(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filtered.length,
              itemBuilder: (context, index) => _buildPickCard(filtered[index]),
            ),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildSearchHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(bottom: BorderSide(color: Color(0xFF2C2C2E))),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search SKU or Item Name...',
          hintStyle: const TextStyle(color: Colors.white38),
          prefixIcon: const Icon(Icons.search, color: Colors.white38),
          border: InputBorder.none,
          suffixIcon: IconButton(
            icon: const Icon(Icons.qr_code_scanner, color: Color(0xFFFF9800)),
            onPressed: () {},
          ),
        ),
      ),
    );
  }

  Widget _buildProgressIndicator() {
    final pickedCount = _items.where((i) => i.isPicked).length;
    final progress = _items.isEmpty ? 0.0 : pickedCount / _items.length;

    return LinearProgressIndicator(
      value: progress,
      backgroundColor: Colors.white10,
      color: const Color(0xFFFF9800),
      minHeight: 2,
    );
  }

  Widget _buildPickCard(PickItem item) {
    return Card(
      color: item.isPicked ? const Color(0xFF1B2E1E) : const Color(0xFF252528),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: item.isPicked
              ? Colors.green.withOpacity(0.3)
              : Colors.transparent,
        ),
      ),
      child: InkWell(
        onTap: () => setState(() => item.isPicked = !item.isPicked),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
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
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
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
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Icon(
                          Icons.inventory_2_outlined,
                          size: 14,
                          color: Colors.white38,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Qty: ${item.qty}',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Checkbox(
                value: item.isPicked,
                onChanged: (val) => setState(() => item.isPicked = val!),
                activeColor: Colors.green,
                checkColor: Colors.white,
                side: const BorderSide(color: Colors.white24, width: 2),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    final pickedCount = _items.where((i) => i.isPicked).length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(top: BorderSide(color: Color(0xFF2C2C2E))),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: pickedCount == _items.length ? () {} : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2C2C2E),
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.white.withOpacity(0.05),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
          ),
          child: Text('COMPLETE PICKING ($pickedCount/${_items.length})'),
        ),
      ),
    );
  }
}

class PickItem {
  final String id;
  final String name;
  final String location;
  final double qty;
  bool isPicked;

  PickItem({
    required this.id,
    required this.name,
    required this.location,
    required this.qty,
    this.isPicked = false,
  });
}
