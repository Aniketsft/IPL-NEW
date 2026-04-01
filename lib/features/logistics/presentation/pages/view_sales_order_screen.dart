import 'package:enterprise_auth_mobile/features/logistics/domain/entities/site.dart';
import 'package:flutter/material.dart';
import 'package:enterprise_auth_mobile/core/widgets/standard_filter.dart';
import 'package:enterprise_auth_mobile/core/widgets/filter_input_widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../widgets/sync_status_header.dart';
import '../../domain/entities/sales_order.dart';
import '../widgets/sales_order_card.dart';
import '../../data/repositories/delivery_repository.dart';
import 'new_cuts_bulk_screen.dart';
import '../widgets/sync_overlay.dart';


class ViewSalesOrderScreen extends StatefulWidget {
  const ViewSalesOrderScreen({super.key});

  @override
  State<ViewSalesOrderScreen> createState() => _ViewSalesOrderScreenState();
}

class _ViewSalesOrderScreenState extends State<ViewSalesOrderScreen> {
  DateTime? _selectedDate;
  String _status = 'open';
  List<SalesOrder> _orders = [];
  List<Map<String, String>> _customersList = [];
  List<Map<String, String>> _salesRepsList = [];
  List<Map<String, String>> _sitesList = [];
  final String _lastSync = '2026-03-10 10:25'; // Mocked for UI demo

  String? _selectedCustomerCode;
  String? _selectedSalesmanCode;
  Site? _selectedSite;

  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentOffset = 0;
  bool _isLoadingLookups = false;
  String? _errorMessage;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  List<SalesOrder> _filteredOrders = [];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);
    _loadLookups();
    _fetchOrders();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _applyLocalFilters();
  }

  void _applyLocalFilters() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredOrders = List.from(_orders);
      } else {
        _filteredOrders = _orders.where((o) {
          final matchesSearch =
              o.orderNumber.toLowerCase().contains(query) ||
              o.customerName.toLowerCase().contains(query) ||
              o.customerCode.toLowerCase().contains(query);
          return matchesSearch;
        }).toList();
      }
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoading &&
        !_isLoadingMore &&
        _hasMore) {
      _fetchMoreOrders();
    }
  }

  Future<void> _loadLookups() async {
    setState(() => _isLoadingLookups = true);
    try {
      final repository = context.read<DeliveryRepository>();
      final customers = await repository.getCustomers();
      final reps = await repository.getSalesReps();
      final sites = await repository.getSites();

      setState(() {
        _customersList = customers
            .map((c) => {'code': c.code, 'name': c.name})
            .toList();
        _salesRepsList = reps
            .map((r) => {'code': r.code, 'name': r.name})
            .toList();
        _sitesList = sites
            .map((s) => {'code': s.code, 'name': s.name})
            .toList();
        _isLoadingLookups = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingLookups = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading lookups: $e')));
      }
    }
  }

  Future<void> _fetchOrders() async {
    setState(() {
      _isLoading = true;
      _currentOffset = 0;
      _hasMore = true;
      _errorMessage = null;
    });

    try {
      final repository = context.read<DeliveryRepository>();

      final results = await repository.fetchSalesOrderHeaders(
        status: _status,
        date: _selectedDate,
        siteCode: _selectedSite?.code,
        customerCode: _selectedCustomerCode,
        rep0: null, // Removed per request
        rep1: _selectedSalesmanCode,
        limit: 100,
        offset: 0,
      );

      setState(() {
        _orders = results;
        _applyLocalFilters();
        _hasMore = results.length == 100;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _fetchMoreOrders() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final repository = context.read<DeliveryRepository>();
      final nextOffset = _currentOffset + 100;

      final results = await repository.fetchSalesOrderHeaders(
        status: _status,
        date: _selectedDate,
        siteCode: _selectedSite?.code,
        customerCode: _selectedCustomerCode,
        rep0: null, // Removed per request
        rep1: _selectedSalesmanCode,
        limit: 100,
        offset: nextOffset,
      );

      setState(() {
        _orders.addAll(results);
        _applyLocalFilters();
        _currentOffset = nextOffset;
        _hasMore = results.length == 100;
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingMore = false;
      });
      debugPrint('Error loading more orders: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF9800);
    const dark900 = Color(0xFF0D0D0D);

    return Scaffold(
      backgroundColor: dark900,
      appBar: AppBar(
        title: const Text(
          'View Sales Order',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.logout),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                _selectedSite?.name ??
                    (_orders.isNotEmpty
                        ? (_orders.first.site ?? 'Main Plant')
                        : 'Main Plant'),
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              SyncStatusHeader(lastSync: _lastSync),
              StandardFilter(
                onApply: _fetchOrders,
                searchController: _searchController,
                onSearchChanged: (_) => _applyLocalFilters(),
                hasActiveFilters:
                    _selectedDate != null ||
                    _selectedCustomerCode != null ||
                    _selectedSalesmanCode != null ||
                    _selectedSite != null ||
                    (_status != 'all' && _status != 'open'),
                onReset: () {
                  setState(() {
                    _selectedCustomerCode = null;
                    _selectedSalesmanCode = null;
                    _selectedSite = null;
                    _selectedDate = null;
                    _status = 'all';
                    _searchController.clear();
                  });
                  _fetchOrders();
                },
                filterBuilder: (context, setModalState) {
                  return Column(
                    children: [
                      if (_isLoadingLookups)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: LinearProgressIndicator(
                            minHeight: 2,
                            color: Colors.orange,
                            backgroundColor: Colors.white10,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          FilterDatePicker(
                            label: 'Del. Date',
                            value: _selectedDate,
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _selectedDate ?? DateTime.now(),
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2101),
                                builder: (context, child) => Theme(
                                  data: Theme.of(context).copyWith(
                                    colorScheme: const ColorScheme.dark(
                                      primary: orange,
                                      onPrimary: Colors.white,
                                      surface: Color(0xFF1E1E1E),
                                      onSurface: Colors.white,
                                    ),
                                  ),
                                  child: child!,
                                ),
                              );
                              if (picked != null) {
                                setState(() => _selectedDate = picked);
                              }
                            },
                          ),
                          const SizedBox(width: 12),
                          FilterPickerTile(
                            label: 'Site',
                            value: _selectedSite?.name,
                            icon: Icons.location_on_outlined,
                            onTap: () => _showSearchPicker(
                              'Site',
                              _sitesList,
                              (code) {
                                final site = _sitesList.firstWhere(
                                  (s) => s['code'] == code,
                                  orElse: () => {},
                                );
                                setState(() {
                                  _selectedSite = site.isNotEmpty
                                      ? Site(
                                          code: site['code']!,
                                          name: site['name']!,
                                        )
                                      : null;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          FilterPickerTile(
                            label: 'Customer',
                            value: _selectedCustomerCode,
                            icon: Icons.business,
                            onTap: () => _showSearchPicker(
                              'Customer',
                              _customersList,
                              (code) {
                                setState(() => _selectedCustomerCode = code);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          FilterPickerTile(
                            label: 'Salesman',
                            value: _selectedSalesmanCode,
                            icon: Icons.person_outline,
                            onTap: () => _showSearchPicker(
                              'Salesman',
                              _salesRepsList,
                              (code) {
                                setState(() => _selectedSalesmanCode = code);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      FilterSegmentedToggle(
                        label: 'Order Status',
                        value: _status,
                        options: const ['open', 'closed', 'all'],
                        onChanged: (value) {
                          setState(() => _status = value);
                        },
                      ),
                    ],
                  );
                },
              ),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: orange),
                      )
                    : _errorMessage != null
                    ? Center(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      )
                    : _orders.isEmpty
                    ? const Center(
                        child: Text(
                          'No orders found',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: _filteredOrders.length + (_hasMore ? 1 : 0),
                        padding: const EdgeInsets.only(bottom: 20),
                        itemBuilder: (context, index) {
                          if (index == _filteredOrders.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: CircularProgressIndicator(color: orange),
                              ),
                            );
                          }
                          return SalesOrderCard(
                            order: _filteredOrders[index],
                            onRefresh: _fetchOrders,
                          );
                        },
                      ),
              ),
            ],
          ),
          const SyncOverlay(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NewCutsBulkScreen()),
          );
          if (result == true) {
            _fetchOrders();
          }
        },
        backgroundColor: orange,
        child: const Icon(Icons.add, color: Colors.white, size: 30),
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
        onSelected: onSelected,
      ),
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
            child: ListView.builder(
              itemCount: _filteredItems.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return ListTile(
                    title: const Text(
                      'All',
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
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
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
