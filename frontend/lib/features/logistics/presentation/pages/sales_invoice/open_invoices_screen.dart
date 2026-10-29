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
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_sync_bloc.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_sync_event.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_sync_state.dart';

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

  // Top tabs: 0 = Pending Collections, 1 = Collection History
  int _selectedTab = 0;

  String? _selectedCustomerNo;
  String? _selectedCustomerName;

  // Collection Budget entered upfront by user
  double? _targetCollectionAmount;

  // Selected allocations: documentNo -> allocated amount
  final Map<String, double> _selectedAllocations = {};

  bool _isLoading = true;
  List<Map<String, dynamic>> _paymentHistory = [];
  bool _isLoadingHistory = false;

  final currencyFormat = CurrencyFormatter.currencyFormat;

  double get _totalUnpaidInvoices => _allInvoices
      .fold(0.0, (sum, d) => sum + d.remainingAmtLCY.abs());

  int get _totalUnpaidInvoicesCount => _allInvoices.length;

  int get _overdueInvoicesCount {
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    return _allInvoices.where((d) {
      final dt = DateTime.tryParse(d.dueDate);
      return dt != null && dt.isBefore(today);
    }).length;
  }

  double get _totalAllocated => _selectedAllocations.values.fold(0.0, (sum, a) => sum + a);

  double get _remainingBudget {
    if (_targetCollectionAmount == null) return 0.0;
    final diff = _targetCollectionAmount! - _totalAllocated;
    return diff > 0.001 ? double.parse(diff.toStringAsFixed(2)) : 0.0;
  }

  List<OpenInvoiceModel> get _selectedDocuments {
    return _allInvoices.where((d) => _selectedAllocations.containsKey(d.documentNo)).toList();
  }

  void _syncCustomerOpenInvoices() {
    if (_selectedCustomerNo == null || _selectedCustomerNo!.isEmpty) return;
    final syncBloc = context.read<SalesInvoiceSyncBloc>();
    final syncState = syncBloc.state;
    if (syncState is SalesInvoiceSyncInProgress || syncState is SalesInvoiceCustomerSyncInProgress) return;

    final custCode = _selectedCustomerNo!;
    final custName = _selectedCustomerName ?? custCode;

    String siteCode = '';
    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is Authenticated) {
        siteCode = authState.siteCode ?? '';
      }
    } catch (_) {}

    syncBloc.add(
      StartSingleCustomerSyncRequested(
        customerCode: custCode,
        customerName: custName,
        siteCode: siteCode,
      ),
    );
  }

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

      // Ensure any legacy cached credit notes are purged from open invoices table
      await LocalDatabaseHelper.instance.purgeCreditNotesFromOpenInvoices();

      final rawList = await LocalDatabaseHelper.instance.getOpenInvoices(
        siteCode: siteCode,
        customerNo: _selectedCustomerNo,
        docType: 'INV',
      );

      final list = rawList
          .map((m) => OpenInvoiceModel.fromMap(m))
          .where((m) => m.isInvoice)
          .toList();

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
        // Strictly exclude credit notes
        if (!doc.isInvoice) return false;

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

  void _toggleSelect(OpenInvoiceModel doc, bool select) {
    if (!doc.isInvoice) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Credit notes (${doc.documentNo}) cannot be selected for cash collection receipts.'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    setState(() {
      if (!select) {
        _selectedAllocations.remove(doc.documentNo);
      } else {
        final due = doc.remainingAmtLCY.abs();
        if (_targetCollectionAmount != null) {
          final remaining = _remainingBudget;
          if (remaining <= 0.001) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Collection budget of ${CurrencyFormatter.format(_targetCollectionAmount!)} is fully allocated. Uncheck an invoice or adjust budget.',
                ),
                duration: const Duration(seconds: 3),
              ),
            );
            return;
          }
          final toAllocate = due <= remaining ? due : remaining;
          _selectedAllocations[doc.documentNo] = double.parse(toAllocate.toStringAsFixed(2));
        } else {
          _selectedAllocations[doc.documentNo] = double.parse(due.toStringAsFixed(2));
        }
      }
    });
  }

  void _updateAmount(OpenInvoiceModel doc, double amount) {
    setState(() {
      _selectedAllocations[doc.documentNo] = double.parse(amount.toStringAsFixed(2));
    });
  }

  void _autoAllocateFifo() {
    if (_targetCollectionAmount == null || _targetCollectionAmount! <= 0) {
      _showSetCollectionAmountDialog();
      return;
    }

    final invoices = _allInvoices.where((d) => d.isInvoice).toList();
    // Sort oldest due date first (FIFO)
    invoices.sort((a, b) {
      final dtA = DateTime.tryParse(a.dueDate) ?? DateTime(2099);
      final dtB = DateTime.tryParse(b.dueDate) ?? DateTime(2099);
      return dtA.compareTo(dtB);
    });

    double remaining = _targetCollectionAmount!;
    final Map<String, double> newAllocations = {};

    for (final inv in invoices) {
      if (remaining <= 0.001) break;
      final due = inv.remainingAmtLCY.abs();
      final toAllocate = due <= remaining ? due : remaining;
      newAllocations[inv.documentNo] = double.parse(toAllocate.toStringAsFixed(2));
      remaining -= toAllocate;
    }

    setState(() {
      _selectedAllocations.clear();
      _selectedAllocations.addAll(newAllocations);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Auto-allocated ${CurrencyFormatter.format(_totalAllocated)} across ${_selectedAllocations.length} invoice(s).',
        ),
        backgroundColor: Colors.green.shade800,
      ),
    );
  }

  void _showSetCollectionAmountDialog() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final controller = TextEditingController(
      text: _targetCollectionAmount != null && _targetCollectionAmount! > 0
          ? _targetCollectionAmount!.toStringAsFixed(2)
          : (_selectedAllocations.isNotEmpty
              ? _totalAllocated.toStringAsFixed(2)
              : ''),
    );

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
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: theme.primaryColor.withValues(alpha: 0.15),
                      child: Icon(Icons.payments_rounded, color: theme.primaryColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Enter Collection Amount',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            _selectedCustomerName != null
                                ? '$_selectedCustomerName (${_selectedCustomerNo ?? ''})'
                                : 'Set collection budget to allocate across invoices',
                            style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(height: 24),
                // Quick shortcut: Total unpaid debt
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Total Outstanding Invoices', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          Text(
                            CurrencyFormatter.format(_totalUnpaidInvoices),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      TextButton.icon(
                        onPressed: () {
                          controller.text = _totalUnpaidInvoices.toStringAsFixed(2);
                        },
                        icon: const Icon(Icons.bolt_rounded, size: 16),
                        label: const Text('Pay All Dues', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  textAlign: TextAlign.right,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  autofocus: true,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: 'Collection Amount',
                    prefixText: '${CurrencyFormatter.currencySymbol} ',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    if (_targetCollectionAmount != null) ...[
                      OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _targetCollectionAmount = null;
                          });
                          Navigator.pop(ctx);
                        },
                        child: const Text('Clear Budget'),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          final val = double.tryParse(controller.text.trim()) ?? 0.0;
                          if (val <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please enter a valid collection amount.')),
                            );
                            return;
                          }
                          Navigator.pop(ctx);
                          setState(() {
                            _targetCollectionAmount = double.parse(val.toStringAsFixed(2));
                          });
                        },
                        child: const Text('Set Amount', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickCustomer() async {
    if (widget.lockToCustomer) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Locked to current customer: $_selectedCustomerName')),
      );
      return;
    }
    try {
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
              _selectedAllocations.clear();
              _targetCollectionAmount = null;
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
      _selectedAllocations.clear();
      _targetCollectionAmount = null;
    });
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final syncState = context.watch<SalesInvoiceSyncBloc>().state;
    final isSyncingThisCustomer = (syncState is SalesInvoiceCustomerSyncInProgress && syncState.customerCode == _selectedCustomerNo) ||
        syncState is SalesInvoiceSyncInProgress;

    return BlocListener<SalesInvoiceSyncBloc, SalesInvoiceSyncState>(
      listener: (context, syncState) {
        if (syncState is SalesInvoiceCustomerSyncSuccess) {
          if (_selectedCustomerNo == null || syncState.customerCode == _selectedCustomerNo) {
            _loadData();
          }
        }
      },
      child: IndustrialModuleLayout(
        title: widget.lockToCustomer && _selectedCustomerName != null
            ? 'Receipt (Cash Collection) [${_selectedCustomerNo ?? ''}]'
            : 'Receipt (Cash Collection)',
        extraActions: [
          if (_selectedCustomerNo != null && _selectedCustomerNo!.isNotEmpty)
            IconButton(
              icon: isSyncingThisCustomer
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.cloud_sync_rounded),
              tooltip: 'Sync Open Invoices for ${_selectedCustomerName ?? _selectedCustomerNo}',
              onPressed: isSyncingThisCustomer ? null : _syncCustomerOpenInvoices,
            ),
        ],
        body: Column(
          children: [
            // Top Segmented Control Tab Bar: 0 = Pending Collections, 1 = Collection History
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

            // Search, Customer Filter & 2-Tab Sub Filter Bar
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
                        color: theme.primaryColor.withValues(alpha: 0.08),
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

                ],
              ),
            ),

            // Metrics Summary Tile (Always Invoices Summary Tile)
            if (_selectedTab == 0)
              _buildInvoicesSummaryTile(theme, isDark),

            // Body List: Tab 0 (Pending Collections) or Tab 1 (Collection History)
            Expanded(
              child: _selectedTab == 0
                  ? (_isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _filteredInvoices.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.receipt_long_outlined,
                                    size: 64,
                                    color: Colors.grey.withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'No open unpaid invoices found.',
                                    style: TextStyle(fontSize: 15, color: Colors.grey),
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _loadData,
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                itemCount: _filteredInvoices.length,
                                itemBuilder: (context, index) {
                                  final doc = _filteredInvoices[index];
                                  final isSelected = _selectedAllocations.containsKey(doc.documentNo);
                                  final allocated = _selectedAllocations[doc.documentNo] ?? 0.0;
                                  final remBudget = _remainingBudget;
                                  final maxAllowed = (allocated + remBudget).clamp(0.0, doc.remainingAmtLCY.abs());

                                  return OpenInvoiceCard(
                                    invoice: doc,
                                    isSelectable: true,
                                    isSelected: isSelected,
                                    selectedAmount: allocated,
                                    maxAllowedAllocation: maxAllowed,
                                    onToggleSelect: (sel) => _toggleSelect(doc, sel),
                                    onAmountChanged: (amt) => _updateAmount(doc, amt),
                                  );
                                },
                              ),
                            ))
                  : _buildHistoryList(),
            ),

            // Persistent Footer Bar: Visible on Pending Collections tab
            if (_selectedTab == 0)
              _buildPersistentFooter(theme, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoicesSummaryTile(ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.primaryColor.withValues(alpha: isDark ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.primaryColor.withValues(alpha: isDark ? 0.3 : 0.2),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: theme.primaryColor.withValues(alpha: 0.15),
            child: Icon(Icons.account_balance_wallet_rounded, color: theme.primaryColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TOTAL UNPAID INVOICES',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: Colors.grey),
                ),
                const SizedBox(height: 1),
                Text(
                  CurrencyFormatter.format(_totalUnpaidInvoices),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: theme.primaryColor,
                  ),
                ),
                Text(
                  '$_totalUnpaidInvoicesCount Open Invoices • $_overdueInvoicesCount Overdue',
                  style: TextStyle(
                    fontSize: 11,
                    color: _overdueInvoicesCount > 0 ? Colors.red.shade400 : Colors.grey,
                    fontWeight: _overdueInvoicesCount > 0 ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          if (_targetCollectionAmount != null)
            IconButton(
              icon: const Icon(Icons.bolt_rounded),
              tooltip: 'Auto-allocate FIFO',
              onPressed: _autoAllocateFifo,
              color: theme.primaryColor,
            ),
        ],
      ),
    );
  }



  Widget _buildPersistentFooter(ThemeData theme, bool isDark) {
    final hasBudget = _targetCollectionAmount != null;
    final hasAllocations = _selectedAllocations.isNotEmpty;
    final remaining = _remainingBudget;
    final selectedDocs = _selectedDocuments;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
            if (!hasBudget && !hasAllocations)
              // Initial State: Prompt user to enter collection amount or select directly
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _showSetCollectionAmountDialog,
                  icon: const Icon(Icons.payments_rounded),
                  label: const Text(
                    'Enter Collection Amount',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              )
            else ...[
              // Active Budget / Selection HUD
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  InkWell(
                    onTap: _showSetCollectionAmountDialog,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Row(
                        children: [
                          Text(
                            hasBudget
                                ? 'Budget: ${CurrencyFormatter.format(_targetCollectionAmount!)}'
                                : 'Allocated: ${CurrencyFormatter.format(_totalAllocated)}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.edit_rounded, size: 14, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                  if (hasBudget)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: (remaining <= 0.001 ? Colors.green : Colors.amber).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: (remaining <= 0.001 ? Colors.green : Colors.amber).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        remaining <= 0.001
                            ? 'Fully Allocated'
                            : 'Remaining: ${CurrencyFormatter.format(remaining)}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: remaining <= 0.001 ? Colors.green : Colors.amber.shade900,
                        ),
                      ),
                    )
                  else
                    Text(
                      '${selectedDocs.length} Invoice(s) Selected',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: hasAllocations
                      ? () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PaymentProcessingScreen(
                                openInvoiceDocuments: selectedDocs,
                                openInvoiceAllocations: Map.from(_selectedAllocations),
                                openInvoiceNetPayable: _totalAllocated,
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
                            setState(() {
                              _selectedAllocations.clear();
                              _targetCollectionAmount = null;
                            });
                            _loadData();
                          }
                        }
                      : _showSetCollectionAmountDialog,
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(
                    hasAllocations
                        ? 'Proceed with Payment (${CurrencyFormatter.format(_totalAllocated)})'
                        : 'Select Invoices or Set Amount',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ],
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
            Icon(Icons.history_rounded, size: 64, color: Colors.grey.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            const Text(
              'No collections recorded on this device yet.',
              style: TextStyle(fontSize: 15, color: Colors.grey),
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

    String formattedDate = createdAt;
    try {
      final dt = DateTime.parse(createdAt);
      formattedDate = DateFormat('dd MMM yyyy, HH:mm').format(dt);
    } catch (_) {}

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            method,
                            style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            docNo,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    CurrencyFormatter.format(amount),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.green.shade700,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('Customer: $custNo', style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color)),
                  const Spacer(),
                  Text(formattedDate, style: TextStyle(fontSize: 11, color: theme.textTheme.bodySmall?.color)),
                ],
              ),
              if (chequeNo.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('Cheque: $chequeNo', style: TextStyle(fontSize: 11, color: theme.textTheme.bodySmall?.color)),
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
                    Text('By $userName', style: TextStyle(fontSize: 11, color: theme.textTheme.bodySmall?.color)),
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
                      CurrencyFormatter.format(amount),
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
