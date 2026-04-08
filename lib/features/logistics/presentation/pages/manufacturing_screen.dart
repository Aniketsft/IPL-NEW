import 'package:flutter/material.dart';
import 'package:enterprise_auth_mobile/core/widgets/industrial_module_layout.dart';
import 'package:enterprise_auth_mobile/core/widgets/filter_input_widgets.dart';
import 'package:enterprise_auth_mobile/core/widgets/standard_filter.dart';


class ManufacturingScreen extends StatefulWidget {
  final List<String> permissions;

  const ManufacturingScreen({super.key, required this.permissions});

  @override
  State<ManufacturingScreen> createState() => _ManufacturingScreenState();
}

class _ManufacturingScreenState extends State<ManufacturingScreen> {
  final TextEditingController _searchController = TextEditingController();
  DateTime? _deliveryDate = DateTime.now();

  final List<DeliveryItem> _deliveries = [
    DeliveryItem(
      id: 'DEL-2024-001',
      customer: 'Industrial Dynamics Corp',
      status: 'In Transit',
      items: 450,
      date: '2024-03-20',
      destination: 'Main Warehouse A',
    ),
    DeliveryItem(
      id: 'DEL-2024-002',
      customer: 'Precision Engineering Ltd',
      status: 'Delayed',
      items: 120,
      date: '2024-03-19',
      destination: 'Regional Hub B',
    ),
    DeliveryItem(
      id: 'DEL-2024-003',
      customer: 'Global Tech Systems',
      status: 'Loading',
      items: 890,
      date: '2024-03-21',
      destination: 'Distribution Center West',
    ),
    DeliveryItem(
      id: 'DEL-2024-004',
      customer: 'Mega Structure Group',
      status: 'Ready',
      items: 300,
      date: '2024-03-20',
      destination: 'Site Port 4',
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
    final dateQuery = _deliveryDate != null ? _deliveryDate!.toString().split(' ')[0] : '';

    final filtered = _deliveries.where((d) {
      final matchesSearch =
          d.id.toLowerCase().contains(query) ||
          d.customer.toLowerCase().contains(query);
      final matchesDate = dateQuery.isEmpty || d.date == dateQuery;
      return matchesSearch && matchesDate;
    }).toList();

    return IndustrialModuleLayout(
      title: 'MANUFACTURING',
      body: Column(
        children: [
          _buildFilterSection(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filtered.length,
              itemBuilder: (context, index) => _buildDeliveryCard(filtered[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: StandardFilter(
        searchController: _searchController,
        searchHint: 'Search Delivery # or Customer...',
        onSearchChanged: (_) => setState(() {}),
        onApply: () => setState(() {}),
        onReset: () => setState(() {
          _searchController.clear();
          _deliveryDate = null;
        }),
        filterBuilder: (context, setModalState) {
          return FilterDatePicker(
            label: 'Delivery Date',
            value: _deliveryDate,
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _deliveryDate ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              );
              if (picked != null) {
                setState(() => _deliveryDate = picked);
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildDeliveryCard(DeliveryItem item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: const Color(0xFF2C2C2E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.id,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Customer: ${item.customer}',
              style: const TextStyle(color: Colors.white70),
            ),
            Text(
              'Status: ${item.status}',
              style: TextStyle(
                color: item.status == 'In Transit'
                    ? Colors.blueAccent
                    : item.status == 'Delayed'
                        ? Colors.redAccent
                        : item.status == 'Loading'
                            ? Colors.orangeAccent
                            : Colors.greenAccent,
              ),
            ),
            Text(
              'Items: ${item.items}',
              style: const TextStyle(color: Colors.white70),
            ),
            Text(
              'Date: ${item.date}',
              style: const TextStyle(color: Colors.white70),
            ),
            Text(
              'Destination: ${item.destination}',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

class DeliveryItem {
  final String id;
  final String customer;
  final String status;
  final int items;
  final String date;
  final String destination;

  DeliveryItem({
    required this.id,
    required this.customer,
    required this.status,
    required this.items,
    required this.date,
    required this.destination,
  });
}
