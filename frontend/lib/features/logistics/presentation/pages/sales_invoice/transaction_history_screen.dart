import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:enterprise_auth_mobile/core/app_theme.dart';
import 'package:enterprise_auth_mobile/core/widgets/search_picker_sheet.dart';
import 'package:enterprise_auth_mobile/core/widgets/standard_filter.dart';
import 'package:enterprise_auth_mobile/core/widgets/filter_input_widgets.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/transaction_history_repository.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/transaction_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/sales_invoice_product_model.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_bloc.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_event.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_state.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_cart_cubit.dart'; // for CartItem
import 'package:enterprise_auth_mobile/core/network_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'order_summary_screen.dart';
import 'invoice_item_reversal_screen.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/models/transaction_config.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/sales_invoice_sync_repository.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_state.dart';


class TransactionHistoryScreen extends StatefulWidget {
  final String transactionType; // To support launching with a default filter, though the class might manage its own.
  final bool isForReversal;
  final String? initialCustomerCode;
  final String? initialCustomerName;
  final bool lockToCustomer;
  final bool isX3History;
  final bool isForReturn;

  const TransactionHistoryScreen({
    super.key,
    this.transactionType = 'ALL',
    this.isForReversal = false,
    this.initialCustomerCode,
    this.initialCustomerName,
    this.lockToCustomer = false,
    this.isX3History = false,
    this.isForReturn = false,
  });

  @override
  State<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  late final TransactionHistoryRepository _repository;
  List<TransactionModel> _transactions = [];
  bool _isLoading = true;
  String _selectedType = 'ALL';
  DateTime? _selectedDate;
  String? _startDate;
  String? _endDate;

  // Standard Filter State
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  String? _selectedCustomerCode;
  String? _selectedCustomerName;

  String? _selectedProductSku;
  String? _selectedProductName;

  List<Map<String, String>> _availableCustomerProducts = [];
  bool _isLoadingProducts = false;

  bool get _hasActiveFilters =>
      _searchController.text.trim().isNotEmpty ||
      (!widget.lockToCustomer && _selectedCustomerCode != null) ||
      _selectedProductSku != null ||
      _selectedDate != null ||
      _selectedType != 'ALL';

  final currencyFormat = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'RS ',
    decimalDigits: 2,
  );

  bool _isSyncingX3History = false;

  Future<void> _syncCustomerHistory() async {
    if (_isSyncingX3History || _selectedCustomerCode == null || _selectedCustomerCode!.isEmpty) return;

    setState(() => _isSyncingX3History = true);
    final custCode = _selectedCustomerCode!;
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
        content: Text('Syncing 6-month X3 history for $custName from Sage X3...'),
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
        await _loadTransactions();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade800,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            content: Text('Synced ${result.x3HistoryInvoicesCount} X3 invoices for $custName'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            content: Text(result.errorMessage ?? 'Failed to sync X3 history.'),
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
        setState(() => _isSyncingX3History = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _repository = TransactionHistoryRepository(
      networkService: context.read<NetworkService>(),
    );
    _selectedType = widget.transactionType;
    _selectedCustomerCode = widget.initialCustomerCode;
    _selectedCustomerName = widget.initialCustomerName;
    if (_selectedCustomerCode == null || _selectedCustomerCode!.isEmpty) {
      try {
        final blocState = context.read<SalesInvoiceBloc>().state;
        if (blocState is SalesInvoiceLoaded && blocState.customer != null) {
          _selectedCustomerCode = blocState.customer!['code']?.toString();
          _selectedCustomerName = blocState.customer!['name']?.toString();
        }
      } catch (_) {}
    }
    _loadTransactions();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTransactions({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final List<TransactionModel> transactions;
      if (widget.isX3History && _selectedCustomerCode != null && _selectedCustomerCode!.isNotEmpty) {
        transactions = await _repository.getX3HistoryTransactions(
          customerCode: _selectedCustomerCode!,
          type: _selectedType == 'ALL' ? null : _selectedType,
          startDate: _startDate,
          endDate: _endDate,
          searchQuery: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
          forceRefresh: forceRefresh,
        );
      } else {
        transactions = await _repository.getTransactions(
          type: _selectedType == 'ALL' ? null : _selectedType,
          startDate: _startDate,
          endDate: _endDate,
          documentId: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
          customerCode: _selectedCustomerCode,
          productSku: _selectedProductSku,
          limit: 100, // Fetch up to 100 recent transactions
          isForReversal: widget.isForReversal,
        );
      }
      if (mounted) {
        setState(() {
          _transactions = transactions;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load transactions: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _resetAllFilters() {
    setState(() {
      _searchController.clear();
      if (!widget.lockToCustomer) {
        _selectedCustomerCode = null;
        _selectedCustomerName = null;
      }
      _selectedProductSku = null;
      _selectedProductName = null;
      _selectedDate = null;
      _startDate = null;
      _endDate = null;
      _selectedType = 'ALL';
      _availableCustomerProducts = [];
    });
    _loadTransactions();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          widget.isForReturn
              ? 'Select X3 Invoice to Return [${_selectedCustomerCode ?? ''}]'
              : widget.isX3History
                  ? 'X3 History [${_selectedCustomerCode ?? ''}]'
                  : widget.lockToCustomer && _selectedCustomerName != null
                      ? (widget.isForReversal ? 'Select Reversal [${_selectedCustomerCode ?? ''}]' : 'History [${_selectedCustomerCode ?? ''}]')
                      : (widget.isForReversal ? 'Select Invoice to Reverse' : 'Transaction History'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_selectedCustomerCode != null && _selectedCustomerCode!.isNotEmpty)
            IconButton(
              icon: _isSyncingX3History
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.cloud_sync_rounded),
              tooltip: 'Sync Live Data for ${_selectedCustomerName ?? _selectedCustomerCode}',
              onPressed: _isSyncingX3History ? null : _syncCustomerHistory,
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. StandardFilter matching ViewSalesOrderScreen
          StandardFilter(
            searchController: _searchController,
            searchHint: widget.isX3History ? 'Search X3 Doc or Product...' : 'Search INV or CN ID...',
            onApply: _loadTransactions,
            onSearchChanged: (_) {
              _searchDebounce?.cancel();
              _searchDebounce = Timer(const Duration(milliseconds: 300), () {
                if (mounted) _loadTransactions();
              });
            },
            hasActiveFilters: _hasActiveFilters,
            onReset: _resetAllFilters,
            filterBuilder: (context, setModalState) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      FilterPickerTile(
                        label: 'Client',
                        value: _selectedCustomerName != null
                            ? '$_selectedCustomerName (${_selectedCustomerCode ?? ''})'
                            : _selectedCustomerCode,
                        icon: widget.lockToCustomer ? Icons.lock_rounded : Icons.business,
                        onTap: () async {
                          if (widget.lockToCustomer) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Locked to current customer: $_selectedCustomerName')),
                            );
                            return;
                          }
                          final customers = await _repository.getCustomersWithTransactions();
                          if (customers.isEmpty) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('No clients found with transaction history.')),
                              );
                            }
                            return;
                          }
                          if (context.mounted) {
                            SearchPickerSheet.show(
                              context: context,
                              title: 'Select Client',
                              items: customers,
                              onSelected: (code) async {
                                if (code == null) {
                                  setState(() {
                                    _selectedCustomerCode = null;
                                    _selectedCustomerName = null;
                                    _selectedProductSku = null;
                                    _selectedProductName = null;
                                    _availableCustomerProducts = [];
                                  });
                                  setModalState(() {});
                                  return;
                                }
                                final customer = customers.firstWhere(
                                  (c) => c['code'] == code,
                                  orElse: () => {'code': code, 'name': code},
                                );
                                setState(() {
                                  _selectedCustomerCode = code;
                                  _selectedCustomerName = customer['name'];
                                  _selectedProductSku = null;
                                  _selectedProductName = null;
                                  _isLoadingProducts = true;
                                });
                                setModalState(() {});

                                try {
                                  final products = await _repository.getProductsSoldToCustomer(code);
                                  if (mounted) {
                                    setState(() {
                                      _availableCustomerProducts = products.map((p) => {
                                        'code': p['sku'] ?? '',
                                        'name': p['name'] ?? '',
                                      }).toList();
                                      _isLoadingProducts = false;
                                    });
                                    setModalState(() {});
                                  }
                                } catch (_) {
                                  if (mounted) {
                                    setState(() => _isLoadingProducts = false);
                                    setModalState(() {});
                                  }
                                }
                              },
                            );
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilterPickerTile(
                        label: 'Product',
                        value: _selectedProductName != null
                            ? '$_selectedProductName (${_selectedProductSku ?? ''})'
                            : (_selectedCustomerCode == null ? 'Select Client first' : _selectedProductSku),
                        icon: Icons.inventory_2_outlined,
                        onTap: () {
                          if (_selectedCustomerCode == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please select a Client first to view products sold to them.'),
                              ),
                            );
                            return;
                          }
                          if (_isLoadingProducts) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Loading products sold to this client...')),
                            );
                            return;
                          }
                          if (_availableCustomerProducts.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'No products found that were sold to ${_selectedCustomerName ?? _selectedCustomerCode}.',
                                ),
                              ),
                            );
                            return;
                          }
                          SearchPickerSheet.show(
                            context: context,
                            title: 'Products Sold to ${_selectedCustomerName ?? _selectedCustomerCode}',
                            items: _availableCustomerProducts,
                            onSelected: (code) {
                              if (code == null) {
                                setState(() {
                                  _selectedProductSku = null;
                                  _selectedProductName = null;
                                });
                                setModalState(() {});
                                return;
                              }
                              final product = _availableCustomerProducts.firstWhere(
                                (p) => p['code'] == code,
                                orElse: () => {'code': code, 'name': code},
                              );
                              setState(() {
                                _selectedProductSku = code;
                                _selectedProductName = product['name'];
                              });
                              setModalState(() {});
                            },
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilterDatePicker(
                        label: 'Date',
                        value: _selectedDate,
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _selectedDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
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
                              _startDate = '${DateFormat('yyyy-MM-dd').format(picked)}T00:00:00';
                              _endDate = '${DateFormat('yyyy-MM-dd').format(picked)}T23:59:59';
                            });
                            setModalState(() {});
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilterSegmentedToggle(
                    label: 'Transaction Type',
                    value: _selectedType,
                    options: const ['ALL', 'INVOICE', 'CREDIT_NOTE', 'RETURN'],
                    onChanged: (value) {
                      setState(() => _selectedType = value);
                      setModalState(() {});
                    },
                  ),
                ],
              );
            },
          ),

          // 2. Active filter indicators (if any active)
          if (_hasActiveFilters)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Row(
                children: [
                  if (_selectedCustomerCode != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 6.0),
                      child: Chip(
                        avatar: const Icon(Icons.person, size: 16, color: AppTheme.primaryAmber),
                        label: Text('Client: ${_selectedCustomerName ?? _selectedCustomerCode}', style: const TextStyle(fontSize: 12)),
                        onDeleted: () {
                          setState(() {
                            _selectedCustomerCode = null;
                            _selectedCustomerName = null;
                            _selectedProductSku = null;
                            _selectedProductName = null;
                            _availableCustomerProducts = [];
                          });
                          _loadTransactions();
                        },
                        deleteIconColor: AppTheme.primaryAmber,
                      ),
                    ),
                  if (_selectedProductSku != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 6.0),
                      child: Chip(
                        avatar: const Icon(Icons.inventory_2, size: 16, color: AppTheme.primaryAmber),
                        label: Text('Product: ${_selectedProductName ?? _selectedProductSku}', style: const TextStyle(fontSize: 12)),
                        onDeleted: () {
                          setState(() {
                            _selectedProductSku = null;
                            _selectedProductName = null;
                          });
                          _loadTransactions();
                        },
                        deleteIconColor: AppTheme.primaryAmber,
                      ),
                    ),
                  if (_selectedDate != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 6.0),
                      child: Chip(
                        avatar: const Icon(Icons.calendar_today, size: 16, color: AppTheme.primaryAmber),
                        label: Text('Date: ${DateFormat('dd MMM yyyy').format(_selectedDate!)}', style: const TextStyle(fontSize: 12)),
                        onDeleted: () {
                          setState(() {
                            _selectedDate = null;
                            _startDate = null;
                            _endDate = null;
                          });
                          _loadTransactions();
                        },
                        deleteIconColor: AppTheme.primaryAmber,
                      ),
                    ),
                  if (_selectedType != 'ALL')
                    Padding(
                      padding: const EdgeInsets.only(right: 6.0),
                      child: Chip(
                        label: Text('Type: $_selectedType', style: const TextStyle(fontSize: 12)),
                        onDeleted: () {
                          setState(() => _selectedType = 'ALL');
                          _loadTransactions();
                        },
                        deleteIconColor: AppTheme.primaryAmber,
                      ),
                    ),
                ],
              ),
            ),

          const Divider(height: 12),
          // List view
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _loadTransactions(forceRefresh: true),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _transactions.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(height: MediaQuery.of(context).size.height * 0.15),
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.search_off, size: 48, color: Colors.grey.withOpacity(0.5)),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'No transactions found matching the criteria.',
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                                      textAlign: TextAlign.center,
                                    ),
                                    if (_hasActiveFilters) ...[
                                      const SizedBox(height: 12),
                                      OutlinedButton.icon(
                                        onPressed: _resetAllFilters,
                                        icon: const Icon(Icons.refresh, size: 16),
                                        label: const Text('Reset All Filters'),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: _transactions.length,
                        itemBuilder: (context, index) {
                          final tx = _transactions[index];
                          
                          // Parse date for display
                          DateTime parsedDate;
                          try {
                            parsedDate = DateTime.parse(tx.createdAt);
                          } catch (_) {
                            parsedDate = DateTime.now();
                          }
                          final dateStr = DateFormat('dd MMM yyyy, HH:mm').format(parsedDate);

                          IconData iconData;
                          Color iconColor;
                          switch (tx.type) {
                            case 'CREDIT_NOTE':
                              iconData = Icons.money_off;
                              iconColor = Colors.orange;
                              break;
                            case 'RETURN':
                              iconData = Icons.assignment_return;
                              iconColor = Colors.red;
                              break;
                            case 'INVOICE':
                            default:
                              iconData = Icons.receipt;
                              iconColor = Colors.green;
                              break;
                          }

                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: iconColor.withOpacity(0.1),
                                child: Icon(iconData, color: iconColor),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      widget.isX3History ? tx.id : '${tx.type} - ${tx.id}', 
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (tx.isReversed == 1) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.red),
                                      ),
                                      child: const Text('Reversed', style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                  ] else if (tx.isPartiallyReversed == 1) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.orange),
                                      ),
                                      child: Text(
                                        tx.remainingAmount != null
                                            ? 'Partial (${currencyFormat.format(tx.remainingAmount)})'
                                            : 'Partial',
                                        style: const TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(tx.customerName),
                                  if (tx.reversalCreditNoteId != null && tx.reversalCreditNoteId!.isNotEmpty)
                                    Text(
                                      tx.isReversed == 1
                                          ? 'Reversed by: ${tx.reversalCreditNoteId}'
                                          : 'Credit Note: ${tx.reversalCreditNoteId}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: tx.isReversed == 1 ? Colors.red[700] : Colors.orange[800],
                                      ),
                                    ),
                                  Text(dateStr, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  if (tx.auditMetadata.createdByUserName != null)
                                    Text('By: ${tx.auditMetadata.createdByUserName}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                ],
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    currencyFormat.format(tx.grandTotal),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  if (tx.isSynced == 1)
                                    const Icon(Icons.cloud_done, size: 16, color: Colors.green)
                                  else
                                    const Icon(Icons.cloud_upload, size: 16, color: Colors.grey),
                                ],
                              ),
                              onTap: () async {
                                if (widget.isForReturn) {
                                  final isCreditNote = tx.type == 'CREDIT_NOTE' || tx.id.startsWith('CN-');
                                  if (isCreditNote) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Cannot return items from a Credit Note (${tx.id}). Please select an Invoice.'),
                                        backgroundColor: Colors.orange,
                                      ),
                                    );
                                    return;
                                  }

                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => InvoiceItemReversalScreen(
                                        transaction: tx,
                                        isReturnMode: true,
                                      ),
                                    ),
                                  );
                                  if (result == true && mounted) {
                                    _loadTransactions();
                                  }
                                  return;
                                }

                                if (widget.isForReversal && tx.isReversed == 1) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Invoice ${tx.id} has already been fully reversed${tx.reversalCreditNoteId != null && tx.reversalCreditNoteId!.isNotEmpty ? " (${tx.reversalCreditNoteId})" : ""}.'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                  return;
                                }

                                // Show loading overlay
                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (_) => const Center(child: CircularProgressIndicator()),
                                );

                                try {
                                  final lines = await _repository.getTransactionLines(tx.id);
                                  
                                  if (context.mounted) {
                                    Navigator.pop(context); // Dismiss loading
                                    
                                    final customerMap = await LocalDatabaseHelper.instance.getSalesInvoiceCustomerByCode(tx.customerCode);
                                    final resolvedCustomer = customerMap ?? {
                                      'code': tx.customerCode,
                                      'name': tx.customerName,
                                      'statusFlag': '1',
                                      'creditLimit': '0',
                                      'outstandingBalance': '0'
                                    };
                                    
                                    context.read<SalesInvoiceBloc>().add(ClearCart());

                                    final isCreditNote = tx.type == 'CREDIT_NOTE' || tx.id.startsWith('CN-');
                                    String type = widget.isForReversal 
                                        ? 'CREDIT_NOTE' 
                                        : (isCreditNote ? 'PREVIEW_CREDIT_NOTE' : 'PREVIEW_INVOICE');

                                    context.read<SalesInvoiceBloc>().add(
                                      InitializeTransaction(
                                        transactionType: type,
                                        originalDocumentId: tx.id,
                                        customer: resolvedCustomer,
                                        config: TransactionConfig.forType(type),
                                      )
                                    );
                                    context.read<SalesInvoiceBloc>().add(SetCustomer(resolvedCustomer));

                                    int validItemsAdded = 0;
                                    for (var item in lines) {
                                      final originalQty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
                                      final reversedQty = (item['reversedQty'] as num?)?.toDouble() ?? 0.0;
                                      final effectiveQty = widget.isForReversal
                                          ? (originalQty - reversedQty).clamp(0.0, double.infinity)
                                          : originalQty; // Show original items in preview
                                      final totalAmount = (item['total'] as num?)?.toDouble() ?? 0.0;
                                      final lineAmtInc = (item['lineAmountIncTax'] as num?)?.toDouble() ?? 0.0;
                                      final basePrice = (item['basePrice'] as num?)?.toDouble() ?? 0.0;
                                      final effectivePrice = basePrice.abs() > 0.0001
                                          ? basePrice
                                          : (totalAmount.abs() > 0.0001 ? totalAmount : lineAmtInc);
                                      
                                      // If in reversal mode, skip lines that have 0 remaining quantity
                                      if (widget.isForReversal && effectiveQty <= 0.0001) {
                                        continue;
                                      }

                                      // Support standard quantity lines as well as amount-only credit notes
                                      if (effectiveQty > 0 || effectivePrice.abs() > 0.0001) {
                                        validItemsAdded++;
                                        context.read<SalesInvoiceBloc>().add(
                                          AddCartItem(
                                            CartItem(
                                              product: SalesInvoiceProductModel(
                                                sku: item['sku'] ?? '',
                                                name: item['name'] ?? '',
                                                stockQty: 0.0,
                                                warehouse: item['warehouse'] ?? '',
                                                salesUnit: (item['salesUnit'] != null && (item['salesUnit'] as String).isNotEmpty)
                                                    ? item['salesUnit']
                                                    : 'EA',
                                              ),
                                              lotNumber: item['lotNumber'] ?? '',
                                              quantity: effectiveQty > 0 ? effectiveQty : 1.0,
                                              basePrice: effectivePrice,
                                              discountAmountFlat: (item['discountAmountFlat'] as num?)?.toDouble() ?? 0.0,
                                              taxRule: item['taxRule'] ?? '',
                                              vatRatePercent: 0.0,
                                            )
                                          )
                                        );
                                      }
                                    }

                                    if (widget.isForReversal && validItemsAdded == 0) {
                                      context.read<SalesInvoiceBloc>().add(ClearCart());
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('All items in ${tx.id} have already been reversed.'),
                                          backgroundColor: Colors.orange,
                                        ),
                                      );
                                      _loadTransactions();
                                      return;
                                    }

                                    final result = await Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => const OrderSummaryScreen()),
                                    );
                                    if (result == true || widget.isForReversal) {
                                      _loadTransactions();
                                    }
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    Navigator.pop(context); // Dismiss loading
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Failed to load transaction lines: $e')),
                                    );
                                  }
                                }
                              },
                            ),
                          );
                        },
                      ),
            ),
          ),
        ],
      ),
    );
  }
}
