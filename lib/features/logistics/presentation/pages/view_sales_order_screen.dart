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
  List<Map<String, String>> _customersList = [];
  List<Map<String, String>> _salesRepsList = [];

  String? _selectedCustomerCode;
  String? _selectedSM1Code;
  String? _selectedSM2Code;

  bool _isLoading = false;
  bool _isLoadingLookups = false;
  String? _errorMessage;
  bool _isFilterExpanded = true;

  @override
  void initState() {
    super.initState();
    _loadLookups();
    _fetchOrders();
  }

  Future<void> _loadLookups() async {
    setState(() => _isLoadingLookups = true);
    try {
      final repository = context.read<DeliveryRepository>();
      final customers = await repository.getCustomers();
      final reps = await repository.getSalesReps();

      setState(() {
        _customersList = customers;
        _salesRepsList = reps;
        _isLoadingLookups = false;
      });
    } catch (e) {
      setState(() => _isLoadingLookups = false);
      debugPrint('Error loading lookups: $e');
    }
  }

  Future<void> _fetchOrders() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repository = context.read<DeliveryRepository>();

      // Note: The backend currently supports customerCode filter.
      final results = await repository.fetchSalesOrderHeaders(
        status: _status,
        date: _selectedDate,
        customerCode: _selectedCustomerCode,
        rep0: _selectedSM1Code,
        rep1: _selectedSM2Code,
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
          if (_isLoadingLookups)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          Row(
            children: [
              Expanded(child: _buildDatePicker()),
              const SizedBox(width: 16),
              Expanded(
                child: _buildDropdownFilter(
                  'Customer',
                  _selectedCustomerCode,
                  _customersList,
                  (val) => setState(() => _selectedCustomerCode = val),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildDropdownFilter(
                  'Sales Man 1',
                  _selectedSM1Code,
                  _salesRepsList,
                  (val) => setState(() => _selectedSM1Code = val),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildDropdownFilter(
                  'Sales Man 2',
                  _selectedSM2Code,
                  _salesRepsList,
                  (val) => setState(() => _selectedSM2Code = val),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildStatusToggle(),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _fetchOrders,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text('Apply Filters'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownFilter(
    String label,
    String? currentValue,
    List<Map<String, String>> items,
    Function(String?) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: currentValue,
          hint: const Text(
            'Select...',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          dropdownColor: const Color(0xFF1E1E1E),
          isExpanded: true,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.white10),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.orange, width: 1),
            ),
          ),
          items: [
            const DropdownMenuItem<String>(value: null, child: Text('All')),
            ...items.map((item) {
              return DropdownMenuItem<String>(
                value: item['code'],
                child: Text(
                  '${item['code']} - ${item['name']}',
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildDatePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Del. Date',
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
              color: Colors.white.withOpacity(0.05),
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
                    fontSize: 13,
                  ),
                ),
                const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
              ],
            ),
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
        LayoutBuilder(
          builder: (context, constraints) {
            return ToggleButtons(
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
              constraints: BoxConstraints(
                minHeight: 36,
                minWidth: (constraints.maxWidth - 4) / 3,
              ),
              children: const [
                Text('Open', style: TextStyle(fontSize: 13)),
                Text('Closed', style: TextStyle(fontSize: 13)),
                Text('All', style: TextStyle(fontSize: 13)),
              ],
            );
          },
        ),
      ],
    );
  }
}
