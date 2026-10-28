import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:enterprise_auth_mobile/core/app_theme.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/credit_note_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/credit_note_pdf_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/credit_note_model.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_bloc.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_state.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_state.dart';
import '../../../../../core/widgets/industrial_module_layout.dart';
import 'package:enterprise_auth_mobile/core/utils/currency_formatter.dart';

class AmountOnlyCreditNoteScreen extends StatefulWidget {
  final String? initialCustomerCode;
  final Map<String, dynamic>? initialCustomer;
  final bool lockToCustomer;

  const AmountOnlyCreditNoteScreen({
    super.key,
    this.initialCustomerCode,
    this.initialCustomer,
    this.lockToCustomer = false,
  });

  @override
  State<AmountOnlyCreditNoteScreen> createState() => _AmountOnlyCreditNoteScreenState();
}

typedef CashOnlyCreditNoteScreen = AmountOnlyCreditNoteScreen;

class _AmountOnlyCreditNoteScreenState extends State<AmountOnlyCreditNoteScreen> {
  final CreditNoteService _creditNoteService = CreditNoteService();
  final CreditNotePdfService _pdfService = CreditNotePdfService();

  final TextEditingController _searchCustomerController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _referenceController = TextEditingController();

  Map<String, dynamic>? _selectedCustomer;
  List<Map<String, dynamic>> _customerInvoices = [];
  final Set<String> _selectedInvoiceIds = {};

  bool _isLoading = false;
  bool _isProcessing = false;

  final currencyFormat = CurrencyFormatter.currencyFormat;

  String get _customerCode {
    if (_selectedCustomer == null) return widget.initialCustomerCode ?? '';
    return (_selectedCustomer!['code'] ??
            _selectedCustomer!['customerCode'] ??
            _selectedCustomer!['CustomerNo'] ??
            _selectedCustomer!['BPCNUM_0'] ??
            widget.initialCustomerCode ??
            '')
        .toString()
        .trim();
  }

  String get _customerName {
    if (_selectedCustomer == null) return '';
    return (_selectedCustomer!['name'] ??
            _selectedCustomer!['customerName'] ??
            _selectedCustomer!['CustomerName'] ??
            _selectedCustomer!['BPCNAM_0'] ??
            _customerCode)
        .toString()
        .trim();
  }

  String get _customerOutstanding {
    if (_selectedCustomer == null) return '0.00';
    final raw = _selectedCustomer!['outstandingBalance'] ??
        _selectedCustomer!['effectiveOutstanding'] ??
        _selectedCustomer!['balance'] ??
        0;
    final parsed = double.tryParse(raw.toString()) ?? 0.0;
    return currencyFormat.format(parsed);
  }

  bool get _isCustomerLocked =>
      widget.lockToCustomer ||
      widget.initialCustomer != null ||
      (widget.initialCustomerCode != null && widget.initialCustomerCode!.isNotEmpty);

  @override
  void initState() {
    super.initState();
    // 1. Synchronously resolve customer BEFORE the first frame builds!
    if (widget.initialCustomer != null) {
      _selectedCustomer = Map<String, dynamic>.from(widget.initialCustomer!);
    } else {
      try {
        final blocState = context.read<SalesInvoiceBloc>().state;
        if (blocState is SalesInvoiceLoaded && blocState.customer != null) {
          _selectedCustomer = Map<String, dynamic>.from(blocState.customer!);
        }
      } catch (_) {}
    }

    // 2. Complete asynchronous resolution and fetch linked invoices
    _initCustomer();
  }

  Future<void> _initCustomer() async {
    String code = _customerCode;
    if (code.isEmpty) {
      try {
        final blocState = context.read<SalesInvoiceBloc>().state;
        if (blocState is SalesInvoiceLoaded && blocState.customer != null) {
          _selectedCustomer = Map<String, dynamic>.from(blocState.customer!);
          code = _customerCode;
        }
      } catch (_) {}
    }

    if (code.isNotEmpty) {
      try {
        final cust = await LocalDatabaseHelper.instance.getSalesInvoiceCustomerByCode(code);
        if (cust != null) {
          _selectedCustomer = Map<String, dynamic>.from(cust);
        }
      } catch (e) {
        debugPrint('AmountOnlyCreditNoteScreen._initCustomer error: $e');
      }
    }

    if (mounted) {
      setState(() {});
      if (_customerCode.isNotEmpty) {
        await _loadCustomerInvoices(_customerCode);
      }
    }
  }

  @override
  void dispose() {
    _searchCustomerController.dispose();
    _amountController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _pickCustomer() async {
    final db = await LocalDatabaseHelper.instance.database;
    final customers = await db.query(
      LocalDatabaseHelper.tableSalesInvoiceCustomers,
      orderBy: 'name ASC',
      limit: 100,
    );

    if (!mounted) return;

    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String filter = '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filtered = customers.where((c) {
              final name = (c['name'] ?? '').toString().toLowerCase();
              final code = (c['code'] ?? '').toString().toLowerCase();
              return name.contains(filter.toLowerCase()) || code.contains(filter.toLowerCase());
            }).toList();

            return SafeArea(
              child: Container(
                height: MediaQuery.of(context).size.height * 0.75,
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text(
                      'Select Customer for Amount Refund',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search customer name or code...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) => setSheetState(() => filter = val),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, idx) {
                          final cust = filtered[idx];
                          return ListTile(
                            title: Text((cust['name'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('Code: ${cust['code']} • Balance: RS ${cust['outstandingBalance'] ?? 0}'),
                            onTap: () => Navigator.pop(ctx, cust),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedCustomer = picked;
        _selectedInvoiceIds.clear();
      });
      await _loadCustomerInvoices(_customerCode);
    }
  }

  Future<void> _loadCustomerInvoices(String customerCode) async {
    if (customerCode.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final db = await LocalDatabaseHelper.instance.database;

      // 1. Fetch local invoices created on device
      final localInvoices = await db.query(
        LocalDatabaseHelper.tableSiInvoices,
        where: 'customerCode = ? AND (isReversed = 0 OR isReversed IS NULL)',
        whereArgs: [customerCode],
        orderBy: 'createdAt DESC',
      );

      // 2. Fetch Sage X3 open invoices synced for this customer
      final openDocs = await LocalDatabaseHelper.instance.getOpenInvoices(
        customerNo: customerCode,
      );

      final Map<String, Map<String, dynamic>> merged = {};
      for (final inv in localInvoices) {
        final id = (inv['invoiceId'] ?? '').toString();
        if (id.isNotEmpty) {
          merged[id] = {
            'invoiceId': id,
            'customerCode': inv['customerCode'] ?? customerCode,
            'customerName': inv['customerName'] ?? '',
            'grandTotal': (inv['grandTotal'] as num?)?.toDouble() ?? 0.0,
            'createdAt': (inv['createdAt'] ?? '').toString(),
          };
        }
      }

      for (final doc in openDocs) {
        final id = (doc['documentNo'] ?? '').toString();
        if (id.isNotEmpty && !merged.containsKey(id)) {
          merged[id] = {
            'invoiceId': id,
            'customerCode': doc['customerNo'] ?? customerCode,
            'customerName': doc['customerName'] ?? '',
            'grandTotal': (doc['remainingAmtLCY'] as num?)?.toDouble() ?? 0.0,
            'createdAt': (doc['dueDate'] ?? doc['lastSyncAt'] ?? '').toString(),
          };
        }
      }

      if (mounted) {
        setState(() {
          _customerInvoices = merged.values.toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading customer invoices: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  double _getSelectedInvoicesBalance() {
    double total = 0.0;
    for (final inv in _customerInvoices) {
      final id = (inv['invoiceId'] ?? '').toString();
      if (_selectedInvoiceIds.contains(id)) {
        total += (inv['grandTotal'] as num?)?.toDouble() ?? 0.0;
      }
    }
    return total;
  }

  Future<void> _submitAmountRefund() async {
    final refundAmount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    final selectedBalance = _getSelectedInvoicesBalance();

    if (_selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a customer.')),
      );
      return;
    }

    if (_selectedInvoiceIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('At least 1 linked invoice is required for Cash refund.')),
      );
      return;
    }

    if (refundAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid refund amount > 0.')),
      );
      return;
    }

    if (refundAmount > selectedBalance) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Refund amount cannot exceed selected invoice balance (${currencyFormat.format(selectedBalance)}).')),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final authState = context.read<AuthBloc>().state;
      final siteCode = (authState is Authenticated &&
              authState.siteCode != null &&
              authState.siteCode!.isNotEmpty &&
              authState.siteCode != 'ALL')
          ? authState.siteCode!
          : 'IPL';

      final username = authState is Authenticated ? authState.username : 'user';

      final creditNote = await _creditNoteService.createCashOnlyCreditNote(
        salesSite: siteCode,
        customerCode: _customerCode,
        customerName: _customerName,
        refundAmount: refundAmount,
        linkedInvoiceIds: _selectedInvoiceIds.toList(),
        createdBy: username,
        reference: _referenceController.text.trim().isNotEmpty
            ? _referenceController.text.trim()
            : _selectedInvoiceIds.join(', '),
      );

      if (!mounted) return;

      // Show success & thermal print dialog
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('Amount Refund Confirmed'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Credit Note ID: ${creditNote.creditNoteId}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Customer: ${creditNote.customerName}'),
              Text('Refund Amount: ${currencyFormat.format(creditNote.grandTotal)}'),
              Text('Linked Invoices: ${_selectedInvoiceIds.join(', ')}'),
              const SizedBox(height: 12),
              const Text('Stock replenished and transaction recorded for synchronization.', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.print),
              label: const Text('Print Receipt'),
              onPressed: () async {
                await Printing.layoutPdf(
                  onLayout: (format) => _pdfService.generateCreditNotePdf(
                    pageFormat: format,
                    creditNote: creditNote,
                  ),
                );
              },
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx); // Close dialog
                Navigator.pop(context, true); // Pop screen
              },
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to process refund: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final refundAmount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    final selectedBalance = _getSelectedInvoicesBalance();
    final isOverBalance = refundAmount > selectedBalance && selectedBalance > 0;
    final canSubmit = _selectedCustomer != null &&
        _selectedInvoiceIds.isNotEmpty &&
        refundAmount > 0 &&
        !isOverBalance &&
        !_isProcessing;

    return IndustrialModuleLayout(
      title: 'Cash Refund',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Customer Selection Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'CUSTOMER',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey),
                        ),
                        if (_isCustomerLocked && _selectedCustomer != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.lock_outline, size: 14, color: Colors.green),
                                SizedBox(width: 4),
                                Text(
                                  'ACTIVE CUSTOMER',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
                                ),
                              ],
                            ),
                          )
                        else
                          TextButton.icon(
                            onPressed: _pickCustomer,
                            icon: const Icon(Icons.person_search, size: 18),
                            label: Text(_selectedCustomer == null ? 'Select' : 'Change'),
                          ),
                      ],
                    ),
                    if (_selectedCustomer == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          'No customer selected. Tap "Select" to pick a customer.',
                          style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
                        ),
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _customerName,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Code: $_customerCode • Outstanding: $_customerOutstanding',
                            style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 2. Refund Amount Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'REFUND AMOUNT',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        prefixText: 'RS ',
                        labelText: 'Enter Amount to Return',
                        border: const OutlineInputBorder(),
                        errorText: isOverBalance
                            ? 'Amount exceeds selected invoices balance (${currencyFormat.format(selectedBalance)})'
                            : null,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _referenceController,
                      decoration: const InputDecoration(
                        labelText: 'Internal Reference / Notes (Optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 3. Mandatory Linked Invoices Selection
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'LINKED INVOICES (MANDATORY >= 1)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _selectedInvoiceIds.isNotEmpty ? Colors.green.withOpacity(0.15) : Colors.red.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${_selectedInvoiceIds.length} Selected',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _selectedInvoiceIds.isNotEmpty ? Colors.green : Colors.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_isLoading)
                      const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator()))
                    else if (_selectedCustomer == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          'Select a customer above to view available invoices.',
                          style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
                        ),
                      )
                    else if (_customerInvoices.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          'No unreversed invoices found for this customer.',
                          style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                        ),
                      )
                    else ...[
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _customerInvoices.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, idx) {
                          final inv = _customerInvoices[idx];
                          final id = (inv['invoiceId'] ?? '').toString();
                          final total = (inv['grandTotal'] as num?)?.toDouble() ?? 0.0;
                          final isChecked = _selectedInvoiceIds.contains(id);

                          return CheckboxListTile(
                            value: isChecked,
                            title: Text(id, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('Date: ${inv['createdAt']}'),
                            secondary: Text(
                              currencyFormat.format(total),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                              textAlign: TextAlign.right,
                            ),
                            onChanged: (bool? val) {
                              setState(() {
                                if (val == true) {
                                  _selectedInvoiceIds.add(id);
                                } else {
                                  _selectedInvoiceIds.remove(id);
                                }
                              });
                            },
                          );
                        },
                      ),
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Text('Total Available in Selected:', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                            Text(
                              currencyFormat.format(selectedBalance),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: isOverBalance ? Colors.red : AppTheme.primaryAmber,
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 4. Confirm Button
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryAmber,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: canSubmit ? _submitAmountRefund : null,
              icon: _isProcessing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.check_circle_outline, color: Colors.white),
              label: Text(
                _isProcessing ? 'Processing Refund...' : 'Confirm Amount Refund',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
