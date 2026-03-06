import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/sales_order.dart';
import '../widgets/sales_order_card.dart';
import '../../data/repositories/delivery_repository.dart';

class ViewSalesOrderScreen extends StatefulWidget {
  const ViewSalesOrderScreen({super.key});

  @override
  State<ViewSalesOrderScreen> createState() => _ViewSalesOrderScreenState();
}

class _ViewSalesOrderScreenState extends State<ViewSalesOrderScreen> {
  DateTime? _selectedDate;
  String _status = 'all';
  List<SalesOrder> _orders = [];
  bool _isLoading = false;
  String? _errorMessage;
  bool _isFilterExpanded = true;

  final TextEditingController _customerController = TextEditingController();
  final TextEditingController _sm1Controller = TextEditingController();
  final TextEditingController _sm2Controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchOrders();
  }

  Future<void> _fetchOrders() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repository = context.read<DeliveryRepository>();

      // Note: The backend currently supports customerCode filter.
      // sm1 and sm2 can be implemented if needed, but for now we filter by customer.
      final results = await repository.fetchSalesOrderHeaders(
        status: _status,
        date: _selectedDate,
        customerCode: _customerController.text,
      );

      setState(() {
        _orders = results;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('View Sales Order'),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.logout),
          ),
          const Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                'Main Plant',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterHeader(),
          if (_isFilterExpanded) _buildFilters(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                ? Center(child: Text(_errorMessage!))
                : _orders.isEmpty
                ? const Center(child: Text('No orders found'))
                : ListView.builder(
                    itemCount: _orders.length,
                    itemBuilder: (context, index) {
                      return SalesOrderCard(order: _orders[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterHeader() {
    return InkWell(
      onTap: () => setState(() => _isFilterExpanded = !_isFilterExpanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Filters',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Icon(_isFilterExpanded ? Icons.expand_less : Icons.expand_more),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white.withOpacity(0.05),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildDatePicker()),
              const SizedBox(width: 16),
              Expanded(child: _buildTextField('Customer', _customerController)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildTextField('Sales Man 1', _sm1Controller)),
              const SizedBox(width: 16),
              Expanded(child: _buildTextField('Sales Man 2', _sm2Controller)),
            ],
          ),
          const SizedBox(height: 16),
          _buildStatusToggle(),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _fetchOrders,
            child: const Text('Apply Filters'),
          ),
        ],
      ),
    );
  }

  Widget _buildDatePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Delivery Date',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _selectedDate ?? DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2101),
            );
            if (picked != null) {
              setState(() => _selectedDate = picked);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _selectedDate == null
                      ? 'dd/mm/yyyy'
                      : DateFormat('dd/MM/yyyy').format(_selectedDate!),
                  style: TextStyle(
                    color: _selectedDate == null ? Colors.grey : Colors.white,
                  ),
                ),
                const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: 'Select...',
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusToggle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Order Status',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        ToggleButtons(
          isSelected: [
            _status == 'open',
            _status == 'closed',
            _status == 'all',
          ],
          onPressed: (index) {
            setState(() {
              _status = ['open', 'closed', 'all'][index];
            });
          },
          borderRadius: BorderRadius.circular(8),
          fillColor: Colors.orange.withOpacity(0.2),
          selectedColor: Colors.orange,
          color: Colors.grey,
          constraints: const BoxConstraints(minHeight: 40, minWidth: 100),
          children: const [Text('Open'), Text('Closed'), Text('All')],
        ),
      ],
    );
  }
}
