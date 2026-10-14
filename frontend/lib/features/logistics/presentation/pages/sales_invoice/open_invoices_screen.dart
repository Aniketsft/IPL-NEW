import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../../core/widgets/industrial_module_layout.dart';
import '../../../../../core/widgets/search_picker_sheet.dart';
import '../../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../../auth/presentation/bloc/auth_state.dart';
import '../../../data/local/local_database_helper.dart';
import '../../../data/models/open_invoice_model.dart';
import '../../widgets/open_invoice_card.dart';
import 'payment_processing_screen.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_bloc.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_state.dart';

class OpenInvoicesScreen extends StatefulWidget {
  final String? initialCustomerNo;
  final String? initialCustomerName;
  final bool lockToCustomer;

  const OpenInvoicesScreen({
    super.key,
    this.initialCustomerNo,
    this.initialCustomerName,
    this.lockToCustomer = false,
  });

  @override
  State<OpenInvoicesScreen> createState() => _OpenInvoicesScreenState();
}

class _OpenInvoicesScreenState extends State<OpenInvoicesScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<OpenInvoiceModel> _allInvoices = [];
  List<OpenInvoiceModel> _filteredInvoices = [];

  String _selectedDocType = 'ALL'; // 'ALL', 'INV', 'CN'
  String? _selectedCustomerNo;
  String? _selectedCustomerName;

  // Selected allocations: documentNo -> allocated amount
  final Map<String, double> _selectedAllocations = {};

  bool _isLoading = true;
  final currencyFormat = NumberFormat.currency(locale: 'en_US', symbol: 'RS ', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    _selectedCustomerNo = widget.initialCustomerNo;
    _selectedCustomerName = widget.initialCustomerName;
    if (_selectedCustomerNo == null || _selectedCustomerNo!.isEmpty) {
      try {
        final blocState = context.read<SalesInvoiceBloc>().state;
        if (blocState is SalesInvoiceLoaded && blocState.customer != null) {
          _selectedCustomerNo = blocState.customer!['code']?.toString();
          _selectedCustomerName = blocState.customer!['name']?.toString();
        }
      } catch (_) {}
    }
    _loadData();
    _searchController.addListener(_filterData);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final authState = context.read<AuthBloc>().state;
      final siteCode = (authState is Authenticated &&
              authState.siteCode != null &&
              authState.siteCode!.isNotEmpty &&
              authState.siteCode != 'ALL')
          ? authState.siteCode
          : null;

      final rawList = await LocalDatabaseHelper.instance.getOpenInvoices(
        siteCode: siteCode,
        customerNo: _selectedCustomerNo,
      );

      final list = rawList.map((m) => OpenInvoiceModel.fromMap(m)).toList();

      if (mounted) {
        setState(() {
          _allInvoices = list;
          _isLoading = false;
        });
        _filterData();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load open invoices: $e')),
        );
      }
    }
  }

  void _filterData() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredInvoices = _allInvoices.where((doc) {
        // Document type filter
        if (_selectedDocType != 'ALL') {
          if (_selectedDocType == 'INV' && !doc.isInvoice) return false;
          if (_selectedDocType == 'CN' && !doc.isCreditNote) return false;
        }

        // Search query filter
        if (query.isNotEmpty) {
          final docNoMatch = doc.documentNo.toLowerCase().contains(query);
          final custNoMatch = doc.customerNo.toLowerCase().contains(query);
          final custNameMatch = doc.customerName.toLowerCase().contains(query);
          return docNoMatch || custNoMatch || custNameMatch;
        }

        return true;
      }).toList();
    });
  }

  void _toggleSelect(OpenInvoiceModel doc, bool selected) {
    setState(() {
      if (selected) {
        _selectedAllocations[doc.documentNo] = doc.remainingAmtLCY.abs();
      } else {
        _selectedAllocations.remove(doc.documentNo);
      }
    });
  }

  void _updateAmount(OpenInvoiceModel doc, double amount) {
    setState(() {
      _selectedAllocations[doc.documentNo] = double.parse(amount.toStringAsFixed(2));
    });
  }

  double get _calculatedNetPayable {
    double totalInvoices = 0.0;
    double totalCN = 0.0;

    for (final doc in _allInvoices) {
      final amt = _selectedAllocations[doc.documentNo];
      if (amt != null && amt > 0) {
        if (doc.isInvoice) {
          totalInvoices += amt;
        } else if (doc.isCreditNote) {
          totalCN += amt;
        }
      }
    }

    return double.parse((totalInvoices - totalCN).toStringAsFixed(2));
  }

  List<OpenInvoiceModel> get _selectedDocuments {
    return _allInvoices.where((d) => _selectedAllocations.containsKey(d.documentNo)).toList();
  }

  Future<void> _pickCustomer() async {
    if (widget.lockToCustomer) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Locked to current customer: $_selectedCustomerName')),
      );
      return;
    }
    try {
      // Load unique customers from local database
      final customers = await LocalDatabaseHelper.instance.getSalesInvoiceCustomers();
      if (!mounted) return;

      final items = customers.map((c) => {
        'code': (c['code'] ?? '').toString(),
        'name': (c['name'] ?? '').toString(),
      }).toList();

      SearchPickerSheet.show(
        context: context,
        title: 'Filter by Customer',
        items: items,
        onSelected: (selectedCode) {
          if (selectedCode != null && selectedCode.isNotEmpty) {
            final match = items.firstWhere(
              (it) => it['code'] == selectedCode,
              orElse: () => {'name': ''},
            );
            setState(() {
              _selectedCustomerNo = selectedCode;
              _selectedCustomerName = match['name'];
            });
            _loadData();
          }
        },
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load customers: $e')),
      );
    }
  }

  void _clearCustomerFilter() {
    if (widget.lockToCustomer) return;
    setState(() {
      _selectedCustomerNo = null;
      _selectedCustomerName = null;
    });
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final netPayable = _calculatedNetPayable;
    final selectedDocs = _selectedDocuments;

    return IndustrialModuleLayout(
      title: widget.lockToCustomer && _selectedCustomerName != null
          ? 'Open Invoices [${_selectedCustomerNo ?? ''}]'
          : 'Open Invoice',
      body: Column(
        children: [
          // Search & Customer Filter Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: theme.cardColor,
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: widget.lockToCustomer ? 'Search Document No...' : 'Search Document No or Customer...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () => _searchController.clear(),
                          )
                        : null,
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 8),

                // Customer Filter Chip & Clear button
                if (widget.lockToCustomer)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.primaryColor.withOpacity(0.08),
                      border: Border.all(color: theme.primaryColor),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lock_rounded, size: 16, color: theme.primaryColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Customer: ${_selectedCustomerName ?? ''} (${_selectedCustomerNo ?? ''})',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: theme.primaryColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: _pickCustomer,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: _selectedCustomerNo != null
                                    ? theme.primaryColor
                                    : (isDark ? Colors.white10 : Colors.black12),
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.person_search_rounded,
                                  size: 18,
                                  color: _selectedCustomerNo != null ? theme.primaryColor : Colors.grey,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _selectedCustomerName != null
                                        ? '$_selectedCustomerName (${_selectedCustomerNo!})'
                                        : 'All Customers (Tap to filter)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: _selectedCustomerNo != null ? FontWeight.bold : FontWeight.normal,
                                      color: _selectedCustomerNo != null ? theme.primaryColor : null,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (_selectedCustomerNo != null) ...[
                        const SizedBox(width: 6),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          tooltip: 'Clear customer filter',
                          onPressed: _clearCustomerFilter,
                        ),
                      ],
                    ],
                  ),
                const SizedBox(height: 6),

                // Type Segmented Filter Chips
                Row(
                  children: [
                    _buildFilterChip('ALL', 'All (${_allInvoices.length})'),
                    const SizedBox(width: 6),
                    _buildFilterChip('INV', 'Invoices (${_allInvoices.where((d) => d.isInvoice).length})'),
                    const SizedBox(width: 6),
                    _buildFilterChip('CN', 'Credit Notes (${_allInvoices.where((d) => d.isCreditNote).length})'),
                  ],
                ),
              ],
            ),
          ),

          // Invoice / CN Cards List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredInvoices.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.withValues(alpha: 0.5)),
                            const SizedBox(height: 16),
                            const Text(
                              'No open invoices or credit notes found.',
                              style: TextStyle(fontSize: 16, color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _filteredInvoices.length,
                          itemBuilder: (context, index) {
                            final doc = _filteredInvoices[index];
                            final isSelected = _selectedAllocations.containsKey(doc.documentNo);
                            final allocated = _selectedAllocations[doc.documentNo] ?? 0.0;

                            return OpenInvoiceCard(
                              invoice: doc,
                              isSelected: isSelected,
                              selectedAmount: allocated,
                              onToggleSelect: (sel) => _toggleSelect(doc, sel),
                              onAmountChanged: (amt) => _updateAmount(doc, amt),
                            );
                          },
                        ),
                      ),
          ),

          // Bottom Checkout / Allocation Bar
          if (selectedDocs.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.cardColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${selectedDocs.length} Document(s) Selected',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          netPayable < 0
                              ? 'Refund: -${currencyFormat.format(netPayable.abs())}'
                              : 'Net: ${currencyFormat.format(netPayable)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: netPayable < 0 ? Colors.amber.shade800 : theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PaymentProcessingScreen(
                                openInvoiceDocuments: selectedDocs,
                                openInvoiceAllocations: Map.from(_selectedAllocations),
                                openInvoiceNetPayable: netPayable,
                                customCustomer: _selectedCustomerNo != null
                                    ? {
                                        'code': _selectedCustomerNo,
                                        'name': _selectedCustomerName ?? '',
                                      }
                                    : null,
                              ),
                            ),
                          );

                          if (result == true) {
                            _selectedAllocations.clear();
                            _loadData();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(
                          netPayable.abs() <= 0.001
                              ? 'Complete Balance Offset'
                              : (netPayable < 0
                                  ? 'Process Credit Refund (${currencyFormat.format(netPayable.abs())})'
                                  : 'Proceed to Payment (${currencyFormat.format(netPayable)})'),
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String type, String label) {
    final isSelected = _selectedDocType == type;
    final theme = Theme.of(context);

    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _selectedDocType = type);
          _filterData();
        },
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? theme.primaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? theme.primaryColor : (Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.black12),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.white : theme.textTheme.bodyMedium?.color,
            ),
          ),
        ),
      ),
    );
  }
}
