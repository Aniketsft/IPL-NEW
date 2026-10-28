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
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:enterprise_auth_mobile/features/logistics/domain/services/cash_collection_pdf_service.dart';
import 'package:enterprise_auth_mobile/core/utils/currency_formatter.dart';
import '../../../data/repositories/sales_invoice_sync_repository.dart';

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
  bool _isSyncing = false;
  final currencyFormat = CurrencyFormatter.currencyFormat;

  Future<void> _syncCustomerOpenInvoices() async {
    if (_isSyncing || _selectedCustomerNo == null || _selectedCustomerNo!.isEmpty) return;

    setState(() => _isSyncing = true);
    final custCode = _selectedCustomerNo!;
    final custName = _selectedCustomerName ?? custCode;

    String siteCode = '';
    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is Authenticated) {
        siteCode = authState.siteCode ?? '';
      }
    } catch (_) {}

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Syncing open invoices for $custName from Sage X3...'),
        duration: const Duration(seconds: 25),
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      final syncRepo = context.read<SalesInvoiceSyncRepository>();
      final result = await syncRepo.syncSingleCustomerData(
        customerCode: custCode,
        siteCode: siteCode,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (result.success) {
        await _loadData();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade800,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            content: Text('Synced ${result.openInvoicesCount} open invoices for $custName'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            content: Text(result.errorMessage ?? 'Failed to sync open invoices.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: Text('Sync error: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  int _selectedTab = 0; // 0: Pending Collections, 1: Collection History
  List<Map<String, dynamic>> _paymentHistory = [];
  bool _isLoadingHistory = false;

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
    _loadHistoryData();
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
        _loadHistoryData();
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

  Future<void> _loadHistoryData() async {
    setState(() => _isLoadingHistory = true);
    try {
      final authState = context.read<AuthBloc>().state;
      final siteCode = (authState is Authenticated &&
              authState.siteCode != null &&
              authState.siteCode!.isNotEmpty &&
              authState.siteCode != 'ALL')
          ? authState.siteCode
          : null;

      final history = await LocalDatabaseHelper.instance.getOpenInvoicePaymentHistory(
        customerNo: _selectedCustomerNo,
        siteCode: siteCode,
        searchQuery: _searchController.text.trim().isNotEmpty ? _searchController.text.trim() : null,
      );

      if (mounted) {
        setState(() {
          _paymentHistory = history;
          _isLoadingHistory = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingHistory = false);
      }
    }
  }

  void _filterData() {
    if (_selectedTab == 1) {
      _loadHistoryData();
      return;
    }
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
          ? 'Receipt (Cash Collection) [${_selectedCustomerNo ?? ''}]'
          : 'Receipt (Cash Collection)',
      extraActions: [
        if (_selectedCustomerNo != null && _selectedCustomerNo!.isNotEmpty)
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.cloud_sync_rounded),
            tooltip: 'Sync Open Invoices for ${_selectedCustomerName ?? _selectedCustomerNo}',
            onPressed: _isSyncing ? null : _syncCustomerOpenInvoices,
          ),
      ],
      body: Column(
        children: [
          // Top Segmented Control Tab Bar
          Container(
            color: theme.cardColor,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() => _selectedTab = 0);
                      _filterData();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _selectedTab == 0 ? theme.primaryColor : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _selectedTab == 0
                              ? theme.primaryColor
                              : (isDark ? Colors.white12 : Colors.black12),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.receipt_long_rounded,
                            size: 16,
                            color: _selectedTab == 0 ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Pending Collections (${_allInvoices.length})',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _selectedTab == 0 ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() => _selectedTab = 1);
                      _loadHistoryData();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _selectedTab == 1 ? theme.primaryColor : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _selectedTab == 1
                              ? theme.primaryColor
                              : (isDark ? Colors.white12 : Colors.black12),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.history_rounded,
                            size: 16,
                            color: _selectedTab == 1 ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Collection History (${_paymentHistory.length})',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _selectedTab == 1 ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Search & Customer Filter Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: theme.cardColor,
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: _selectedTab == 0
                        ? (widget.lockToCustomer ? 'Search Document No...' : 'Search Document No or Customer...')
                        : 'Search Document No, Tender or Customer...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _searchController.clear();
                              _filterData();
                            },
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
                if (_selectedTab == 0) ...[
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
              ],
            ),
          ),

          // Body Content: Tab 0 (Pending Collections) or Tab 1 (Collection History)
          Expanded(
            child: _selectedTab == 0
                ? (_isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _filteredInvoices.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.withValues(alpha: 0.5)),
                                const SizedBox(height: 16),
                                const Text(
                                  'No open invoices or credit notes found for cash collection.',
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
                          ))
                : _buildHistoryList(),
          ),

          // Bottom Checkout / Allocation Bar (Only for Tab 0)
          if (_selectedTab == 0 && selectedDocs.isNotEmpty)
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
                        Expanded(
                          child: Text(
                            '${selectedDocs.length} Document(s) Selected',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
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
                          textAlign: TextAlign.right,
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

  Widget _buildHistoryList() {
    if (_isLoadingHistory) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_paymentHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_rounded, size: 64, color: Colors.grey.withOpacity(0.5)),
            const SizedBox(height: 16),
            const Text(
              'No collections recorded on this device yet.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadHistoryData,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _paymentHistory.length,
        itemBuilder: (context, index) {
          final item = _paymentHistory[index];
          return _buildHistoryItem(item);
        },
      ),
    );
  }

  Widget _buildHistoryItem(Map<String, dynamic> item) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
    final docNo = item['documentNo']?.toString() ?? '';
    final custNo = item['customerNo']?.toString() ?? '';
    final method = (item['paymentMethod'] ?? 'CASH').toString().toUpperCase();
    final createdAt = item['createdAt']?.toString() ?? '';
    final userName = item['userName']?.toString() ?? '';
    final isSynced = (item['isSynced'] ?? 0) == 1;
    final chequeNo = item['chequeNumber']?.toString() ?? '';
    final bankName = item['bankName']?.toString() ?? '';
    final qrRef = item['qrTransactionRef']?.toString() ?? '';

    String formattedDate = createdAt;
    try {
      final dt = DateTime.parse(createdAt);
      formattedDate = DateFormat('dd MMM yyyy, HH:mm').format(dt);
    } catch (_) {}

    final Color tenderColor = method == 'CASH'
        ? Colors.green
        : (method == 'CHEQUE' ? Colors.blue : Colors.purple);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _showReceiptDetailsModal(item),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: tenderColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: tenderColor.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          method == 'CASH'
                              ? Icons.payments_rounded
                              : (method == 'CHEQUE'
                                  ? Icons.account_balance_rounded
                                  : Icons.qr_code_rounded),
                          color: tenderColor,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          method,
                          style: TextStyle(
                            color: tenderColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      docNo,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    currencyFormat.format(amount),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.person_outline_rounded, size: 14, color: theme.textTheme.bodySmall?.color),
                  const SizedBox(width: 4),
                  Text(
                    'Customer: $custNo',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.textTheme.bodyMedium?.color),
                  ),
                  const Spacer(),
                  Text(
                    formattedDate,
                    style: TextStyle(fontSize: 11, color: theme.textTheme.bodySmall?.color),
                  ),
                ],
              ),
              if (chequeNo.isNotEmpty || qrRef.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (chequeNo.isNotEmpty)
                      Text(
                        'Cheque: $chequeNo ${bankName.isNotEmpty ? "($bankName)" : ""}',
                        style: TextStyle(fontSize: 11, color: theme.textTheme.bodySmall?.color),
                      ),
                    if (qrRef.isNotEmpty)
                      Text(
                        'Ref: $qrRef',
                        style: TextStyle(fontSize: 11, color: theme.textTheme.bodySmall?.color),
                      ),
                  ],
                ),
              ],
              const Divider(height: 16),
              Row(
                children: [
                  Icon(
                    isSynced ? Icons.cloud_done_rounded : Icons.cloud_upload_outlined,
                    size: 14,
                    color: isSynced ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isSynced ? 'Synced to Sage X3' : 'Offline • Pending Sync',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isSynced ? Colors.green : Colors.orange,
                    ),
                  ),
                  const Spacer(),
                  if (userName.isNotEmpty)
                    Text(
                      'Collected by $userName',
                      style: TextStyle(fontSize: 11, color: theme.textTheme.bodySmall?.color),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showReceiptDetailsModal(Map<String, dynamic> item) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
    final docNo = item['documentNo']?.toString() ?? '';
    final custNo = item['customerNo']?.toString() ?? '';
    final method = (item['paymentMethod'] ?? 'CASH').toString().toUpperCase();
    final createdAt = item['createdAt']?.toString() ?? '';
    final userName = item['userName']?.toString() ?? '';
    final isSynced = (item['isSynced'] ?? 0) == 1;
    final chequeNo = item['chequeNumber']?.toString() ?? '';
    final bankName = item['bankName']?.toString() ?? '';
    final qrRef = item['qrTransactionRef']?.toString() ?? '';
    final paymentId = item['paymentId']?.toString() ?? '';

    String formattedDate = createdAt;
    try {
      final dt = DateTime.parse(createdAt);
      formattedDate = DateFormat('dd MMM yyyy, HH:mm').format(dt);
    } catch (_) {}

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Receipt Settlement Details',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(height: 16),
                _buildReceiptRow('Receipt ID', paymentId.length > 16 ? paymentId.substring(0, 16) : paymentId),
                _buildReceiptRow('Document No', docNo),
                _buildReceiptRow('Customer', custNo),
                _buildReceiptRow('Date & Time', formattedDate),
                _buildReceiptRow('Payment Method', method),
                if (chequeNo.isNotEmpty) _buildReceiptRow('Cheque Number', chequeNo),
                if (bankName.isNotEmpty) _buildReceiptRow('Bank', bankName),
                if (qrRef.isNotEmpty) _buildReceiptRow('QR / Payment Ref', qrRef),
                if (userName.isNotEmpty) _buildReceiptRow('Collected By', userName),
                _buildReceiptRow('Sync Status', isSynced ? 'Synced to Sage X3' : 'Pending Sync'),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text('Total Amount Paid', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                    Text(
                      currencyFormat.format(amount),
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green.shade700),
                      textAlign: TextAlign.right,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _printReceipt(item);
                    },
                    icon: const Icon(Icons.print_rounded),
                    label: const Text('Reprint / Share Receipt Slip'),
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildReceiptRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Future<void> _printReceipt(Map<String, dynamic> item) async {
    final docNo = item['documentNo']?.toString() ?? 'Receipt';
    try {
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) => CashCollectionPdfService().generateSingleReceiptPdf(
          pageFormat: format,
          item: item,
        ),
        name: 'Receipt_${docNo}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to print receipt: $e')),
        );
      }
    }
  }
}
