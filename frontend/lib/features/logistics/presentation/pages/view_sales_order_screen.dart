import 'package:enterprise_auth_mobile/features/logistics/domain/entities/site.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/entities/customer.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/entities/sales_rep.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:enterprise_auth_mobile/core/widgets/search_picker_sheet.dart';
import 'package:enterprise_auth_mobile/core/widgets/standard_filter.dart';
import 'package:enterprise_auth_mobile/core/widgets/filter_input_widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../widgets/sync_status_header.dart';
import '../../domain/entities/sales_order.dart';
import '../widgets/sales_order_card.dart';
import '../../data/repositories/delivery_repository.dart';
import 'new_cuts_bulk_screen.dart';
import '../widgets/sync_overlay.dart';
import 'package:enterprise_auth_mobile/core/utils/barcode_scanner/hardware_scanner_mixin.dart';
import 'package:enterprise_auth_mobile/core/utils/barcode_scanner/offline_barcode_processor.dart';

class ViewSalesOrderScreen extends StatefulWidget {
  final List<String> permissions;
  const ViewSalesOrderScreen({super.key, required this.permissions});

  @override
  State<ViewSalesOrderScreen> createState() => _ViewSalesOrderScreenState();
}

class _ViewSalesOrderScreenState extends State<ViewSalesOrderScreen> with HardwareScannerMixin<ViewSalesOrderScreen> {
  DateTime? _selectedDate;
  String _status = 'open';
  List<SalesOrder> _orders = [];
  List<Map<String, String>> _customersList = [];
  List<Map<String, String>> _salesRepsList = [];
  // ignore: unused_field
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
  String _poTypeFilter = 'ALL'; 
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _selectedDate = null;
    _selectedSite = null;
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);
    _loadLookups();
    _fetchOrders();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _scrollController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Future<void> onHardwareScan(String data) async {
    // Scanning is disabled when viewing closed orders
    if (_status.toLowerCase() == 'closed') return;

    // Force unfocus to prevent keyboard wedge from typing into fields
    FocusScope.of(context).unfocus();
    
    final processor = OfflineBarcodeProcessor();
    final result = await processor.processBarcode(data);
    final targetItemCode = result?.itemCode ?? data;
    
    _debounceTimer?.cancel();
    setState(() {
      _searchController.text = targetItemCode;
    });
    // Trigger immediate filter for hardware scans to feel responsive
    _applyLocalFilters();
  }

  void _onSearchChanged() {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        _applyLocalFilters();
      }
    });
  }

  void _applyLocalFilters() {
    final query = _searchController.text.trim().toLowerCase();
    final poType = _poTypeFilter;

    setState(() {
      _filteredOrders = _orders.where((o) {
        // 1. PO Type Filter (Fast check)
        if (poType != 'ALL') {
          final po = o.purchaseOrderNumber?.toUpperCase() ?? '';
          bool matchesType = false;
          if (poType == 'POD') {
            matchesType = po.contains('POD');
          } else if (poType == 'PTT') {
            matchesType = po.contains('PTT');
          } else if (poType == 'EXCESS') {
            matchesType = o.orderNumber.startsWith('CUTS-') || 
                          o.orderNumber.startsWith('BLK-') || 
                          (o.source?.toLowerCase() == 'internal');
          }
          if (!matchesType) return false;
        }

        // 2. Search Query Filter
        if (query.isEmpty) return true;
        
        return o.orderNumber.toLowerCase().contains(query) ||
               o.customerName.toLowerCase().contains(query) ||
               o.customerCode.toLowerCase().contains(query);
      }).toList();
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

  Future<void> _refreshAllLookups() async {
    if (_selectedDate == null) return;
    setState(() => _isLoadingLookups = true);
    try {
      final repository = context.read<DeliveryRepository>();
      
      // Fetch all lookups in parallel to avoid sequential network/DB lag
      final results = await Future.wait([
        repository.getFilteredSites(date: _selectedDate!),
        repository.getFilteredSalesReps(
          date: _selectedDate!,
          siteCode: _selectedSite?.code,
        ),
        repository.getFilteredCustomers(
          date: _selectedDate!,
          siteCode: _selectedSite?.code,
          salesmanCode: _selectedSalesmanCode,
        ),
      ]);

      if (mounted) {
        setState(() {
          _sitesList = (results[0] as List<Site>).map((s) => {'code': s.code, 'name': s.name}).toList();
          _salesRepsList = (results[1] as List<SalesRep>).map((r) => {'code': r.code, 'name': r.name}).toList();
          _customersList = (results[2] as List<Customer>).map((c) => {'code': c.code, 'name': c.name}).toList();
          _isLoadingLookups = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingLookups = false);
        debugPrint('Error refreshing lookups: $e');
      }
    }
  }

  // _reloadSites / _reloadSalesReps removed — site and salesman pickers
  // are no longer surfaced in the filter UI; _reloadCustomers is still used.
  Future<void> _reloadCustomers() => _refreshAllLookups();

  Future<void> _loadLookups() async {
    setState(() => _isLoadingLookups = true);
    try {
      final repository = context.read<DeliveryRepository>();
      
      if (_selectedDate == null) {
        final results = await Future.wait([
          repository.getCustomers(),
          repository.getSalesReps(),
          repository.getSites(),
        ]);
        setState(() {
          _customersList = (results[0] as List<Customer>).map((c) => {'code': c.code, 'name': c.name}).toList();
          _salesRepsList = (results[1] as List<SalesRep>).map((r) => {'code': r.code, 'name': r.name}).toList();
          _sitesList = (results[2] as List<Site>).map((s) => {'code': s.code, 'name': s.name}).toList();
          _isLoadingLookups = false;
        });
      } else {
        await _refreshAllLookups();
        setState(() => _isLoadingLookups = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingLookups = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading lookups: $e')));
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
        rep0: null,
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
        rep0: null,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'View Sales Order',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.home_rounded, color: theme.primaryColor, size: 24),
            tooltip: 'Back to Home',
            onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
          ),
          const SizedBox(width: 16),
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
                    (_status != 'all' && _status != 'open') ||
                    _poTypeFilter != 'ALL',
                onReset: () {
                  setState(() {
                    _selectedCustomerCode = null;
                    _selectedSalesmanCode = null;
                    _selectedSite = null;
                    _selectedDate = null;
                    _status = 'all';
                    _poTypeFilter = 'ALL';
                    _searchController.clear();
                  });
                  _loadLookups();
                  _fetchOrders();
                },
                filterBuilder: (context, setModalState) {
                  return Column(
                    children: [
                      if (_isLoadingLookups)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: LinearProgressIndicator(
                            minHeight: 2,
                            color: orange,
                            backgroundColor: Colors.transparent,
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
                                    colorScheme: ColorScheme.fromSeed(
                                      seedColor: orange,
                                      primary: orange,
                                      onPrimary: Colors.white,
                                      surface: theme.cardColor,
                                      onSurface: isDark ? Colors.white : Colors.black87,
                                      brightness: theme.brightness,
                                    ),
                                  ),
                                  child: child!,
                                ),
                              );
                              if (picked != null) {
                                setState(() {
                                  _selectedDate = picked;
                                  _selectedSite = null;
                                  _selectedSalesmanCode = null;
                                  _selectedCustomerCode = null;
                                });
                                await _refreshAllLookups();
                                setModalState(() {}); 
                              }
                            },
                          ),
                          const SizedBox(width: 12),
                          FilterPickerTile(
                            label: 'PO Type',
                            value: _poTypeFilter,
                            icon: Icons.assignment_outlined,
                            onTap: () => SearchPickerSheet.show(
                              context: context,
                              title: 'PO Type',
                              items: [
                                {'code': 'POD', 'name': 'POD'},
                                {'code': 'PTT', 'name': 'PTT'},
                              ],
                              onSelected: (code) {
                                setState(() {
                                  _poTypeFilter = code ?? 'ALL';
                                });
                                _applyLocalFilters();
                                setModalState(() {});
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
                            onTap: _selectedDate == null
                                ? () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a Delivery Date first')))
                                : () => SearchPickerSheet.show(
                                      context: context,
                                      title: 'Salesman',
                                      items: _salesRepsList,
                                      onSelected: (code) async {
                                        setState(() {
                                          _selectedSalesmanCode = code;
                                          _selectedCustomerCode = null;
                                        });
                                        await _reloadCustomers();
                                        setModalState(() {});
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
                            onTap: _selectedSalesmanCode == null || _selectedDate == null
                                ? () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a Date and Salesman first')))
                                : () => SearchPickerSheet.show(
                                      context: context,
                                      title: 'Customer',
                                      items: _customersList,
                                      onSelected: (code) {
                                        setState(() => _selectedCustomerCode = code);
                                        setModalState(() {});
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
                    ? Center(
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
                        cacheExtent: 1000, // Keep more items in memory for smoother scrolling
                        itemBuilder: (context, index) {
                          if (index == _filteredOrders.length) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: CircularProgressIndicator(color: orange),
                              ),
                            );
                          }
                          return SalesOrderCard(
                            order: _filteredOrders[index],
                            permissions: widget.permissions,
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
      // Hide the new-cuts FAB when the user is viewing closed orders or lacks create permission
      floatingActionButton: _status.toLowerCase() == 'closed' || !widget.permissions.contains('manufacturing.all.create')
          ? null
          : FloatingActionButton(
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


}
