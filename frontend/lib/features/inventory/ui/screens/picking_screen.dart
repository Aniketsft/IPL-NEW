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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

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
          _buildSearchHeader(context, isDark, orange),
          _buildProgressIndicator(orange),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filtered.length,
              itemBuilder: (context, index) => _buildPickCard(context, filtered[index], isDark, orange),
            ),
          ),
          _buildFooter(context, isDark),
        ],
      ),
    );
  }

  Widget _buildSearchHeader(BuildContext context, bool isDark, Color orange) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(bottom: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05))),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (_) => setState(() {}),
        style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search SKU or Item Name...',
          hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
          prefixIcon: Icon(Icons.search, color: isDark ? Colors.white38 : Colors.black38),
          border: InputBorder.none,
          suffixIcon: IconButton(
            icon: Icon(Icons.qr_code_scanner, color: orange),
            onPressed: () {},
          ),
        ),
      ),
    );
  }

  Widget _buildProgressIndicator(Color orange) {
    final pickedCount = _items.where((i) => i.isPicked).length;
    final progress = _items.isEmpty ? 0.0 : pickedCount / _items.length;

    return LinearProgressIndicator(
      value: progress,
      backgroundColor: (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black).withValues(alpha: 0.1),
      color: orange,
      minHeight: 2,
    );
  }

  Widget _buildPickCard(BuildContext context, PickItem item, bool isDark, Color orange) {
    final theme = Theme.of(context);
    
    // Picked color: primaryContainer for both modes ensures consistent visibility
    final pickedColor = isDark ? theme.colorScheme.primaryContainer.withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.08);
    final unpickedColor = theme.cardColor;

    return Card(
      color: item.isPicked ? pickedColor : unpickedColor,
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isDark ? 0 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: item.isPicked
              ? Colors.green.withValues(alpha: isDark ? 0.3 : 0.5)
              : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
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
                      style: TextStyle(
                        color: orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.name,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          item.location,
                          style: TextStyle(
                            color: isDark ? Colors.white38 : Colors.black38,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 14,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Qty: ${item.qty}',
                          style: TextStyle(
                            color: isDark ? Colors.white38 : Colors.black38,
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
                side: BorderSide(color: isDark ? Colors.white24 : Colors.black26, width: 2),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context, bool isDark) {
    final theme = Theme.of(context);
    final orange = theme.primaryColor;
    final pickedCount = _items.where((i) => i.isPicked).length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(top: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05))),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: pickedCount == _items.length ? () {} : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: orange,
            foregroundColor: Colors.black,
            disabledBackgroundColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
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
