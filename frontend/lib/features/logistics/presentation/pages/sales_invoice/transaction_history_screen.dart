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
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_cart_cubit.dart'; // for CartItem
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'order_summary_screen.dart';


class TransactionHistoryScreen extends StatefulWidget {
  final String transactionType; // To support launching with a default filter, though the class might manage its own.
  final bool isForReversal;
  const TransactionHistoryScreen({super.key, this.transactionType = 'ALL', this.isForReversal = false});

  @override
  State<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  final TransactionHistoryRepository _repository = TransactionHistoryRepository();
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
      _selectedCustomerCode != null ||
      _selectedProductSku != null ||
      _selectedDate != null ||
      _selectedType != 'ALL';

  final currencyFormat = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'RS ',
    decimalDigits: 2,
  );

  @override
  void initState() {
    super.initState();
    _selectedType = widget.transactionType;
    _loadTransactions();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTransactions() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final transactions = await _repository.getTransactions(
        type: _selectedType == 'ALL' ? null : _selectedType,
        startDate: _startDate,
        endDate: _endDate,
        documentId: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
        customerCode: _selectedCustomerCode,
        productSku: _selectedProductSku,
        limit: 100, // Fetch up to 100 recent transactions
      );
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
      _selectedCustomerCode = null;
      _selectedCustomerName = null;
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
        title: const Text(
          'Transaction History',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. StandardFilter matching ViewSalesOrderScreen
          StandardFilter(
            searchController: _searchController,
            searchHint: 'Search INV or CN ID...',
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
                        icon: Icons.business,
                        onTap: () async {
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
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _transactions.isEmpty
                    ? Center(
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
                      )
                    : ListView.builder(
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
                                      '${tx.type} - ${tx.id}', 
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
                                  ],
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(tx.customerName),
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
                                    
                                    context.read<SalesInvoiceBloc>().add(ClearCart());
                                    
                                    if (customerMap != null) {
                                      context.read<SalesInvoiceBloc>().add(SetCustomer(customerMap));
                                    } else {
                                      context.read<SalesInvoiceBloc>().add(SetCustomer({
                                        'code': tx.customerCode,
                                        'name': tx.customerName,
                                        'statusFlag': '1',
                                        'creditLimit': '0',
                                        'outstandingBalance': '0'
                                      }));
                                    }

                                    final isCreditNote = tx.type == 'CREDIT_NOTE' || tx.id.startsWith('CN-');
                                    String type = widget.isForReversal 
                                        ? 'CREDIT_NOTE' 
                                        : (isCreditNote ? 'PREVIEW_CREDIT_NOTE' : 'PREVIEW_INVOICE');

                                    context.read<SalesInvoiceBloc>().add(
                                      InitializeTransaction(
                                        transactionType: type,
                                        originalDocumentId: tx.id,
                                      )
                                    );

                                    for (var item in lines) {
                                      final originalQty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
                                      final reversedQty = (item['reversedQty'] as num?)?.toDouble() ?? 0.0;
                                      final effectiveQty = widget.isForReversal
                                          ? (originalQty - reversedQty).clamp(0.0, double.infinity)
                                          : originalQty; // Show original items in preview
                                      
                                      if (effectiveQty > 0) {
                                        context.read<SalesInvoiceBloc>().add(
                                          AddCartItem(
                                            CartItem(
                                              product: SalesInvoiceProductModel(
                                                sku: item['sku'] ?? '',
                                                name: item['name'] ?? '',
                                                stockQty: 0.0,
                                                warehouse: item['warehouse'] ?? '',
                                                salesUnit: item['salesUnit'] ?? '',
                                              ),
                                              lotNumber: item['lotNumber'] ?? '',
                                              quantity: effectiveQty,
                                              basePrice: (item['basePrice'] as num?)?.toDouble() ?? 0.0,
                                              discountAmountFlat: (item['discountAmountFlat'] as num?)?.toDouble() ?? 0.0,
                                              taxRule: item['taxRule'] ?? '',
                                              vatRatePercent: 0.0,
                                            )
                                          )
                                        );
                                      }
                                    }

                                    if (widget.isForReversal) {
                                      Navigator.pushReplacement(
                                        context,
                                        MaterialPageRoute(builder: (_) => const OrderSummaryScreen()),
                                      );
                                    } else {
                                      final result = await Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => const OrderSummaryScreen()),
                                      );
                                      if (result == true) {
                                        _loadTransactions();
                                      }
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
        ],
      ),
    );
  }
}
