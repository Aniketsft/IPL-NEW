import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:enterprise_auth_mobile/core/app_theme.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/transaction_history_repository.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/transaction_model.dart';
import '../../../../../core/widgets/industrial_module_layout.dart';
import 'transaction_preview_screen.dart';

class TransactionHistoryScreen extends StatefulWidget {
  final String transactionType; // To support launching with a default filter, though the class might manage its own.
  const TransactionHistoryScreen({super.key, this.transactionType = 'ALL'});

  @override
  State<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  final TransactionHistoryRepository _repository = TransactionHistoryRepository();
  List<TransactionModel> _transactions = [];
  bool _isLoading = true;
  late String _selectedType;
  String? _startDate;
  String? _endDate;

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

  Future<void> _loadTransactions() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final transactions = await _repository.getTransactions(
        type: _selectedType == 'ALL' ? null : _selectedType,
        startDate: _startDate,
        endDate: _endDate,
        limit: 100, // Fetch up to 100 recent transactions
      );
      setState(() {
        _transactions = transactions;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load transactions: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _onTypeSelected(String type) {
    if (_selectedType == type) return;
    setState(() {
      _selectedType = type;
    });
    _loadTransactions();
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2101),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppTheme.primaryAmber,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start.toIso8601String();
        _endDate = picked.end.toIso8601String();
      });
      _loadTransactions();
    }
  }

  void _clearDateFilter() {
    setState(() {
      _startDate = null;
      _endDate = null;
    });
    _loadTransactions();
  }

  Widget _buildFilterChip(String label, String type) {
    final isSelected = _selectedType == type;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: AppTheme.primaryAmber.withOpacity(0.2),
        checkmarkColor: AppTheme.primaryAmber,
        labelStyle: TextStyle(
          color: isSelected ? AppTheme.primaryAmber : Colors.grey[700],
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        onSelected: (_) => _onTypeSelected(type),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction History'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: () => _selectDateRange(context),
            tooltip: 'Filter by Date',
          ),
          if (_startDate != null || _endDate != null)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _clearDateFilter,
              tooltip: 'Clear Date Filter',
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Filter section
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                _buildFilterChip('All', 'ALL'),
                _buildFilterChip('Invoices', 'INVOICE'),
                _buildFilterChip('Credit Notes', 'CREDIT_NOTE'),
                _buildFilterChip('Returns', 'RETURN'),
              ],
            ),
          ),
          if (_startDate != null && _endDate != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                'Showing from ${DateFormat.yMd().format(DateTime.parse(_startDate!))} to ${DateFormat.yMd().format(DateTime.parse(_endDate!))}',
                style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
              ),
            ),
          const Divider(),
          // List view
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _transactions.isEmpty
                    ? const Center(
                        child: Text('No transactions found matching the criteria.', style: TextStyle(fontSize: 16)),
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
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => TransactionPreviewScreen(transaction: tx),
                                  ),
                                );
                                if (result == true) {
                                  _loadTransactions();
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
