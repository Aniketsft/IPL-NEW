import 'package:flutter/material.dart';
import 'package:enterprise_auth_mobile/core/widgets/standard_filter.dart';
import 'package:enterprise_auth_mobile/core/widgets/filter_input_widgets.dart';
import 'dart:async';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';

class CustomerSelectionScreen extends StatefulWidget {
  const CustomerSelectionScreen({Key? key}) : super(key: key);

  @override
  State<CustomerSelectionScreen> createState() => _CustomerSelectionScreenState();
}

class _CustomerSelectionScreenState extends State<CustomerSelectionScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  List<Map<String, dynamic>> _customers = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentOffset = 0;
  final int _limit = 25;
  
  String _selectedStatus = 'All';
  String? _selectedPaymentTerm;

  String? get _statusCode {
    switch (_selectedStatus) {
      case 'Check': return '1';
      case 'No Check': return '2';
      case 'Hold': return '3';
      default: return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);
    _fetchCustomers();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        _fetchCustomers();
      }
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoading &&
        !_isLoadingMore &&
        _hasMore) {
      _fetchMoreCustomers();
    }
  }

  Future<void> _fetchCustomers() async {
    setState(() {
      _isLoading = true;
      _currentOffset = 0;
      _hasMore = true;
    });

    try {
      final results = await LocalDatabaseHelper.instance.getPaginatedSalesInvoiceCustomers(
        limit: _limit,
        offset: 0,
        query: _searchController.text.trim(),
        statusFilters: _statusCode != null ? [_statusCode!] : null,
        paymentTermFilters: _selectedPaymentTerm != null ? [_selectedPaymentTerm!] : null,
      );

      setState(() {
        _customers = List.from(results);
        _hasMore = results.length == _limit;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      debugPrint('Error fetching customers: $e');
    }
  }

  Future<void> _fetchMoreCustomers() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final nextOffset = _currentOffset + _limit;
      final results = await LocalDatabaseHelper.instance.getPaginatedSalesInvoiceCustomers(
        limit: _limit,
        offset: nextOffset,
        query: _searchController.text.trim(),
        statusFilters: _statusCode != null ? [_statusCode!] : null,
        paymentTermFilters: _selectedPaymentTerm != null ? [_selectedPaymentTerm!] : null,
      );

      setState(() {
        _customers.addAll(results);
        _currentOffset = nextOffset;
        _hasMore = results.length == _limit;
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingMore = false;
      });
      debugPrint('Error loading more customers: $e');
    }
  }

  Widget _buildFilterChip(String label, String value, List<String> selectedList, StateSetter setModalState, Color orange, bool isDark) {
    final isSelected = selectedList.contains(value);
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: orange.withOpacity(0.2),
      checkmarkColor: orange,
      backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide.none),
      labelStyle: TextStyle(
        color: isSelected ? orange : (isDark ? Colors.white : Colors.black87),
        fontWeight: isSelected ? FontWeight.bold : null,
      ),
      onSelected: (selected) {
        setModalState(() {
          if (selected) {
            selectedList.add(value);
          } else {
            selectedList.remove(value);
          }
        });
        setState(() {}); // Trigger main screen rebuild if needed
      },
    );
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
          'Select Customer',
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
      body: Column(
        children: [
          StandardFilter(
            onApply: _fetchCustomers,
            searchController: _searchController,
            searchHint: 'Search by name, ID, or location...',
            onSearchChanged: (_) {}, // Debounce is handled by _searchController listener
            hasActiveFilters: _selectedStatus != 'All' || _selectedPaymentTerm != null,
            onReset: () {
              setState(() {
                _selectedStatus = 'All';
                _selectedPaymentTerm = null;
                _searchController.clear();
              });
              _fetchCustomers();
            },
            filterBuilder: (context, setModalState) {
              return FutureBuilder<List<String>>(
                future: LocalDatabaseHelper.instance.getDistinctPaymentTerms(),
                builder: (context, snapshot) {
                  final availableTerms = snapshot.data ?? [];
                  
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          FilterPickerTile(
                            label: 'Payment Term',
                            value: _selectedPaymentTerm,
                            icon: Icons.payments_outlined,
                            onTap: () => _showSearchPicker(
                              'Payment Term',
                              availableTerms.map((t) => {'code': t, 'name': t}).toList(),
                              (code) {
                                setState(() => _selectedPaymentTerm = code);
                                setModalState(() {});
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      FilterSegmentedToggle(
                        label: 'Status',
                        value: _selectedStatus,
                        options: const ['All', 'Check', 'No Check', 'Hold'],
                        onChanged: (value) {
                          setState(() => _selectedStatus = value);
                          setModalState(() {});
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                  );
                }
              );
            },
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _customers.isEmpty
                    ? const Center(child: Text('No customers found'))
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: _customers.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _customers.length) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }

                          final customer = _customers[index];
                          final code = customer[LocalDatabaseHelper.colCode] as String? ?? '';
                          final name = customer[LocalDatabaseHelper.colName] as String? ?? '';
                          final paymentTerm = customer['paymentTerm'] as String? ?? 'N/A';
                          final creditLimitRaw = customer['creditLimit']?.toString() ?? '0';
                          final statusStr = customer['statusFlag']?.toString() ?? '1';
                          
                          // Parse status flag logic
                          IconData statusIcon = Icons.check_circle;
                          Color statusColor = Colors.green;
                          String statusText = 'CHECK';
                          
                          if (statusStr == '2') {
                            statusIcon = Icons.cancel;
                            statusColor = Colors.grey;
                            statusText = 'NO CHECK';
                          } else if (statusStr == '3') {
                            statusIcon = Icons.error;
                            statusColor = Colors.red[800]!;
                            statusText = 'HOLD';
                          }
                          
                          double creditLimitVal = double.tryParse(creditLimitRaw) ?? 0.0;
                          final creditLimitStr = 'RS ${creditLimitVal.toStringAsFixed(2)}';
                          
                          return Card(
                            elevation: 0,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(color: Colors.grey.withOpacity(0.3), width: 1),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                // Navigate to next screen
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Top Row: Name and Code
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: orange.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            code,
                                            style: TextStyle(
                                              color: orange,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    // Middle Row: Payment Term and Status
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            paymentTerm.toUpperCase(),
                                            style: const TextStyle(
                                              color: Colors.grey,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 10,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: statusColor.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(statusIcon, color: statusColor, size: 12),
                                              const SizedBox(width: 4),
                                              Text(
                                                statusText,
                                                style: TextStyle(
                                                  color: statusColor,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 10,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Divider(color: Colors.grey.withOpacity(0.2), thickness: 1, height: 1),
                                    const SizedBox(height: 12),
                                    // Bottom Row: Credit Limit & Outstanding
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'CREDIT LIMIT',
                                                style: TextStyle(
                                                  color: Colors.grey[600],
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                creditLimitStr,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: isDark ? Colors.white : Colors.black87,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'OUTSTANDING',
                                                style: TextStyle(
                                                  color: Colors.grey[600],
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'RS 0.00',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.red[800],
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  void _showSearchPicker(
    String title,
    List<Map<String, String>> items,
    Function(String?) onSelected,
  ) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.scaffoldBackgroundColor,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

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
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Select ${widget.title}',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            onChanged: _filter,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: 'Search...',
              hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.black26),
              prefixIcon: Icon(Icons.search, color: isDark ? Colors.grey : Colors.grey[600]),
              filled: true,
              fillColor: theme.cardColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
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
                    title: Text(
                      'All',
                      style: TextStyle(color: orange),
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
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    item['name'] ?? '',
                    style: TextStyle(color: isDark ? Colors.grey : Colors.black45, fontSize: 12),
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
