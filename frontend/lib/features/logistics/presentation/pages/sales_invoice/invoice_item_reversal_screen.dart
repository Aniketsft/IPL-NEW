import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/transaction_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/transaction_history_repository.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/credit_note_pdf_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'package:enterprise_auth_mobile/core/widgets/industrial_module_layout.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_bloc.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_event.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_cart_cubit.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/sales_invoice_product_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/models/transaction_config.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_state.dart';
import 'order_summary_screen.dart';
import 'package:enterprise_auth_mobile/core/utils/currency_formatter.dart';

/// Screen allowing the user to select specific invoice lines (and quantities)
/// to reverse, generating a partial Credit Note or entering Customer Return flow.
class InvoiceItemReversalScreen extends StatefulWidget {
  final TransactionModel transaction;
  final bool isReturnMode;

  const InvoiceItemReversalScreen({
    super.key,
    required this.transaction,
    this.isReturnMode = false,
  });

  @override
  State<InvoiceItemReversalScreen> createState() => _InvoiceItemReversalScreenState();
}

class _InvoiceItemReversalScreenState extends State<InvoiceItemReversalScreen> {
  final TransactionHistoryRepository _repository = TransactionHistoryRepository();

  List<Map<String, dynamic>> _lines = [];
  Map<String, double> _alreadyReversedQty = {}; // lineId → already reversed qty
  final Map<String, bool> _selected = {};
  final Map<String, TextEditingController> _qtyControllers = {};
  bool _isLoading = true;
  bool _isProcessing = false;

  final currencyFormat = CurrencyFormatter.currencyFormat;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final lines = await _repository.getTransactionLines(widget.transaction.id);
      final reversedMap = await _repository.getReversedLineIds(widget.transaction.id);
      setState(() {
        _lines = lines;
        _alreadyReversedQty = reversedMap;
        for (final line in lines) {
          final lineId = line['lineId']?.toString() ?? line['id']?.toString() ?? '';
          final originalQty = (line['quantity'] as num?)?.toDouble() ?? 0.0;
          final alreadyReversed = reversedMap[lineId] ?? 0.0;
          final remaining = originalQty - alreadyReversed;
          final isFullyReversed = remaining <= 0;
          _selected[lineId] = false;
          _qtyControllers[lineId] = TextEditingController(
            text: isFullyReversed ? '0' : _formatQty(remaining),
          );
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load invoice lines: $e')),
        );
      }
    }
  }

  String _formatQty(double val) {
    if ((val - val.roundToDouble()).abs() < 0.0001) {
      return val.round().toString();
    }
    String formatted = val.toStringAsFixed(3);
    while (formatted.endsWith('0') && formatted.contains('.')) {
      formatted = formatted.substring(0, formatted.length - 1);
    }
    if (formatted.endsWith('.')) {
      formatted = formatted.substring(0, formatted.length - 1);
    }
    return formatted;
  }

  double _resolveEffectiveQty(double enteredQty, double remaining) {
    if (enteredQty <= 0.0001) return 0.0;
    if ((enteredQty - remaining).abs() <= 0.005) {
      return remaining;
    }
    return enteredQty;
  }

  void _toggleSelection(String lineId, double remaining, bool isFullyReversed) {
    if (isFullyReversed) return;
    setState(() {
      final willSelect = !(_selected[lineId] ?? false);
      _selected[lineId] = willSelect;
      if (willSelect) {
        final currentText = _qtyControllers[lineId]?.text.trim() ?? '';
        final currentVal = double.tryParse(currentText) ?? 0.0;
        if (currentVal <= 0.0001 || currentVal > remaining) {
          _qtyControllers[lineId]?.text = _formatQty(remaining);
        }
      }
    });
  }

  bool get _hasInvalidSelectedQuantities {
    for (final line in _lines) {
      final lineId = line['lineId']?.toString() ?? line['id']?.toString() ?? '';
      if (_selected[lineId] == true) {
        final originalQty = (line['quantity'] as num?)?.toDouble() ?? 0.0;
        final alreadyReversed = _alreadyReversedQty[lineId] ?? 0.0;
        final remaining = originalQty - alreadyReversed;
        final rawQty = double.tryParse(_qtyControllers[lineId]?.text ?? '') ?? 0.0;
        final qty = _resolveEffectiveQty(rawQty, remaining);
        if (qty <= 0.0001 || (qty - remaining) > 0.0001) {
          return true;
        }
      }
    }
    return false;
  }

  double get _reversalTotal {
    double total = 0.0;
    for (final line in _lines) {
      final lineId = line['lineId']?.toString() ?? line['id']?.toString() ?? '';
      if (_selected[lineId] == true) {
        final originalQty = (line['quantity'] as num?)?.toDouble() ?? 0.0;
        final alreadyReversed = _alreadyReversedQty[lineId] ?? 0.0;
        final remaining = originalQty - alreadyReversed;
        final rawQty = double.tryParse(_qtyControllers[lineId]?.text ?? '0') ?? 0.0;
        final qty = _resolveEffectiveQty(rawQty, remaining);
        if (qty > 0.0001 && (qty - remaining) <= 0.0001) {
          final basePrice = (line['basePrice'] as num?)?.toDouble() ?? 0.0;
          final vatRate = (line['vatRatePercent'] as num?)?.toDouble() ?? 0.0;
          total += (basePrice * qty) * (1.0 + (vatRate / 100.0));
        }
      }
    }
    return total;
  }

  int get _selectedCount => _selected.values.where((v) => v).length;

  Future<void> _confirmReversal() async {
    final selectedLines = <Map<String, dynamic>>[];
    for (final line in _lines) {
      final lineId = line['lineId']?.toString() ?? line['id']?.toString() ?? '';
      if (_selected[lineId] == true) {
        final originalQty = (line['quantity'] as num?)?.toDouble() ?? 0.0;
        final alreadyReversed = _alreadyReversedQty[lineId] ?? 0.0;
        final remaining = originalQty - alreadyReversed;
        final rawQty = double.tryParse(_qtyControllers[lineId]?.text ?? '0') ?? 0.0;
        final qty = _resolveEffectiveQty(rawQty, remaining);

        if (qty <= 0.0001) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Quantity for "${line['name'] ?? lineId}" must be greater than zero.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        if ((qty - remaining) > 0.0001) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Cannot reverse ${_formatQty(qty)} of "${line['name'] ?? lineId}". '
                'Only ${_formatQty(remaining)} remaining of ordered ${_formatQty(originalQty)}.',
              ),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        selectedLines.add({'lineId': lineId, 'reversedQty': qty});
      }
    }

    if (selectedLines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one item with a valid quantity.')),
      );
      return;
    }

    if (_reversalTotal <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reversal amount must be greater than zero.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final availableReasons = await LocalDatabaseHelper.instance.getCreditNoteReasons();
    String selectedReasonCode = availableReasons.isNotEmpty ? availableReasons.first['code']! : 'RET';

    // Summary confirmation dialog
    final confirmedReason = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.undo, color: Colors.orange),
                SizedBox(width: 8),
                Text('Confirm Partial Reversal'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${selectedLines.length} item(s) will be reversed.'),
                  const SizedBox(height: 8),
                  ...selectedLines.map((s) {
                    final line = _lines.firstWhere(
                      (l) => (l['lineId']?.toString() ?? l['id']?.toString() ?? '') == s['lineId'],
                      orElse: () => {},
                    );
                    return Text(
                      '• ${line['name'] ?? s['lineId']} — Qty: ${s['reversedQty']}',
                      style: const TextStyle(fontSize: 13),
                    );
                  }),
                  const SizedBox(height: 12),
                  Text(
                    'Reversal Total: ${currencyFormat.format(_reversalTotal)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text('Stock for reversed items will be replenished.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedReasonCode,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Credit Note Reason *',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: availableReasons.map((r) {
                      final code = r['code'] ?? '';
                      final desc = r['description'] ?? code;
                      return DropdownMenuItem<String>(
                        value: code,
                        child: Text(
                          '$desc ($code)',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() {
                          selectedReasonCode = val;
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                onPressed: () {
                  Navigator.of(ctx).pop(selectedReasonCode);
                },
                child: const Text('Confirm Reversal'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmedReason == null || confirmedReason.isEmpty || !mounted) return;

    setState(() => _isProcessing = true);
    try {
      final creditNote = await _repository.partialReverseInvoice(
        widget.transaction,
        selectedLines,
        reason: confirmedReason,
      );
      if (!mounted) return;
      setState(() => _isProcessing = false);

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('Partial Reversal Done'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Credit Note ${creditNote.creditNoteId} generated.'),
              const SizedBox(height: 6),
              Text('Amount: ${currencyFormat.format(creditNote.grandTotal)}'),
              const SizedBox(height: 6),
              const Text('Stock replenished for reversed items.'),
            ],
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.print),
              label: const Text('Print Voucher'),
              onPressed: () async {
                await Printing.layoutPdf(
                  onLayout: (format) => CreditNotePdfService().generateCreditNotePdf(
                    pageFormat: format,
                    creditNote: creditNote,
                    resolvedLines: [],
                  ),
                );
              },
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop(true); // signal list to reload
              },
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reversal failed: $e')),
        );
      }
    }
  }

  Future<void> _continueToReturnSummary() async {
    final selectedLines = <Map<String, dynamic>>[];
    for (final line in _lines) {
      final lineId = line['lineId']?.toString() ?? line['id']?.toString() ?? '';
      if (_selected[lineId] == true) {
        final originalQty = (line['quantity'] as num?)?.toDouble() ?? 0.0;
        final alreadyReversed = _alreadyReversedQty[lineId] ?? 0.0;
        final remaining = originalQty - alreadyReversed;
        final rawQty = double.tryParse(_qtyControllers[lineId]?.text ?? '0') ?? 0.0;
        final qty = _resolveEffectiveQty(rawQty, remaining);

        if (qty <= 0.0001) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Quantity for "${line['name'] ?? lineId}" must be greater than zero.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        if ((qty - remaining) > 0.0001) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Cannot return ${_formatQty(qty)} of "${line['name'] ?? lineId}". '
                'Only ${_formatQty(remaining)} remaining of ordered ${_formatQty(originalQty)}.',
              ),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        selectedLines.add({'lineId': lineId, 'returnQty': qty, 'line': line});
      }
    }

    if (selectedLines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one item to return.')),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final customerMap = await LocalDatabaseHelper.instance.getSalesInvoiceCustomerByCode(widget.transaction.customerCode);
      final resolvedCustomer = customerMap ?? {
        'code': widget.transaction.customerCode,
        'name': widget.transaction.customerName,
        'statusFlag': '1',
        'creditLimit': '0',
        'outstandingBalance': '0',
      };

      if (!mounted) return;

      final bloc = context.read<SalesInvoiceBloc>();
      bloc.add(ClearCart());
      bloc.add(InitializeTransaction(
        transactionType: 'RETURN',
        originalDocumentId: widget.transaction.id,
        customer: resolvedCustomer,
        config: TransactionConfig.forType('RETURN'),
      ));
      bloc.add(SetCustomer(resolvedCustomer));

      final authState = context.read<AuthBloc>().state;
      final userSiteCode = (authState is Authenticated &&
              authState.siteCode != null &&
              authState.siteCode!.isNotEmpty &&
              authState.siteCode != 'ALL')
          ? authState.siteCode!
          : 'IPL';

      for (final item in selectedLines) {
        final line = item['line'] as Map<String, dynamic>;
        final returnQty = item['returnQty'] as double;
        final origQty = (line['quantity'] as num?)?.toDouble() ?? 1.0;
        final basePrice = (line['basePrice'] as num?)?.toDouble() ?? 0.0;
        final totalAmount = (line['total'] as num?)?.toDouble() ?? 0.0;
        final lineAmtInc = (line['lineAmountIncTax'] as num?)?.toDouble() ?? 0.0;

        // Exact unit price per EA/KG paid by customer
        final effectivePrice = basePrice.abs() > 0.0001
            ? basePrice
            : (origQty > 0.0001
                ? (totalAmount.abs() > 0.0001 ? (totalAmount / origQty) : (lineAmtInc / origQty))
                : (totalAmount.abs() > 0.0001 ? totalAmount : lineAmtInc));

        final vatRate = (line['vatRatePercent'] as num?)?.toDouble() ?? 0.0;
        final taxRule = (line['taxRule'] as String?)?.isNotEmpty == true
            ? line['taxRule'] as String
            : (vatRate > 0.1 ? 'VAT15' : 'ZERO');

        final warehouse = (line['warehouse'] != null && (line['warehouse'] as String).isNotEmpty)
            ? line['warehouse'] as String
            : userSiteCode;

        bloc.add(
          AddCartItem(
            CartItem(
              product: SalesInvoiceProductModel(
                sku: line['sku'] ?? '',
                name: line['name'] ?? '',
                stockQty: 0.0,
                warehouse: warehouse,
                salesUnit: (line['salesUnit'] != null && (line['salesUnit'] as String).isNotEmpty)
                    ? line['salesUnit']
                    : 'EA',
              ),
              lotNumber: (line['lotNumber'] != null && (line['lotNumber'] as String).isNotEmpty)
                  ? line['lotNumber']
                  : 'RETURN',
              quantity: returnQty,
              basePrice: effectivePrice,
              discountAmountFlat: 0.0,
              discountPercent: 0.0,
              taxRule: taxRule,
              vatRatePercent: vatRate,
              pricingSource: 'X3_HISTORIC',
              priceListCode: 'X3_INVOICE',
              warehouse: warehouse,
            ),
          ),
        );
      }

      setState(() => _isProcessing = false);

      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const OrderSummaryScreen()),
      );

      if (result == true && mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to prepare return: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IndustrialModuleLayout(
      title: widget.isReturnMode ? 'Select Return Items' : 'Reverse Items',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Column(
                  children: [
                    // 1. Customer Context Banner
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green.withOpacity(0.5)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.lock_rounded, size: 16, color: Colors.green),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.transaction.customerName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Customer: ${widget.transaction.customerCode}  •  Source Invoice: ${widget.transaction.id}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.textTheme.bodySmall?.color ?? Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 2. Header info
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.orange, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Select the items you wish to reverse. Greyed-out items have already been fully reversed.',
                              style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Line items list
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _lines.length,
                        itemBuilder: (context, index) {
                          final line = _lines[index];
                          final lineId = line['lineId']?.toString() ?? line['id']?.toString() ?? '';
                          final originalQty = (line['quantity'] as num?)?.toDouble() ?? 0.0;
                          final alreadyReversed = _alreadyReversedQty[lineId] ?? 0.0;
                          final remaining = originalQty - alreadyReversed;
                          final isFullyReversed = remaining <= 0;
                          final isSelected = _selected[lineId] == true;
                          final basePrice = (line['basePrice'] as num?)?.toDouble() ?? 0.0;
                          final vatRate = (line['vatRatePercent'] as num?)?.toDouble() ?? 0.0;

                          return Opacity(
                            opacity: isFullyReversed ? 0.4 : 1.0,
                            child: Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              clipBehavior: Clip.antiAlias,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                  color: isSelected ? Colors.orange : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: isFullyReversed
                                    ? null
                                    : () => _toggleSelection(lineId, remaining, isFullyReversed),
                                onLongPress: isFullyReversed
                                    ? null
                                    : () => _toggleSelection(lineId, remaining, isFullyReversed),
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Checkbox(
                                            value: isSelected,
                                            activeColor: Colors.orange,
                                            onChanged: isFullyReversed
                                                ? null
                                                : (val) {
                                                    setState(() {
                                                      _selected[lineId] = val ?? false;
                                                      if (val == true) {
                                                        final curText = _qtyControllers[lineId]?.text.trim() ?? '';
                                                        final curVal = double.tryParse(curText) ?? 0.0;
                                                        if (curVal <= 0.0001 || curVal > remaining) {
                                                          _qtyControllers[lineId]?.text = _formatQty(remaining);
                                                        }
                                                      }
                                                    });
                                                  },
                                          ),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  line['name'] ?? 'Unknown Product',
                                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                                ),
                                                Text(
                                                  'SKU: ${line['sku'] ?? ''} | Unit: ${line['salesUnit'] ?? 'EA'} • ${currencyFormat.format(basePrice)}${vatRate > 0 ? " (+${vatRate.toInt()}% VAT)" : ""}',
                                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (isFullyReversed)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.red.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: const Text('Reversed', style: TextStyle(color: Colors.red, fontSize: 11)),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          const SizedBox(width: 48),
                                          Flexible(
                                            child: Text(
                                              'Original: ${_formatQty(originalQty)} | Reversed: ${_formatQty(alreadyReversed)} | Remaining: ${_formatQty(remaining)}',
                                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 2,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (!isFullyReversed && isSelected) ...[
                                        const SizedBox(height: 8),
                                        Builder(
                                          builder: (context) {
                                            final rawEntered = double.tryParse(_qtyControllers[lineId]?.text ?? '') ?? 0.0;
                                            final enteredQty = _resolveEffectiveQty(rawEntered, remaining);
                                            final isExceeding = (enteredQty - remaining) > 0.0001;
                                            final isAtMax = (enteredQty - remaining).abs() <= 0.0001;
                                            final canIncrease = (remaining - enteredQty) > 0.0001 && !isExceeding;
                                            final canDecrease = enteredQty > 1.0001;

                                            return Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    const SizedBox(width: 48),
                                                    IconButton(
                                                      icon: const Icon(Icons.remove_circle_outline, size: 22),
                                                      color: canDecrease ? Colors.orange : Colors.grey,
                                                      padding: EdgeInsets.zero,
                                                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                                      tooltip: 'Decrease quantity',
                                                      onPressed: canDecrease
                                                          ? () {
                                                              final newQty = (enteredQty - 1).clamp(0.01, remaining);
                                                              _qtyControllers[lineId]?.text = _formatQty(newQty);
                                                              setState(() {});
                                                            }
                                                          : null,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    SizedBox(
                                                      width: 76,
                                                      child: TextField(
                                                        controller: _qtyControllers[lineId],
                                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                        textAlign: TextAlign.center,
                                                        style: TextStyle(
                                                          color: isExceeding ? Colors.red : null,
                                                          fontWeight: isExceeding ? FontWeight.bold : FontWeight.normal,
                                                        ),
                                                        decoration: InputDecoration(
                                                          isDense: true,
                                                          border: OutlineInputBorder(
                                                            borderSide: BorderSide(color: isExceeding ? Colors.red : Colors.grey),
                                                          ),
                                                          enabledBorder: OutlineInputBorder(
                                                            borderSide: BorderSide(
                                                              color: isExceeding ? Colors.red : Colors.grey.withOpacity(0.5),
                                                              width: isExceeding ? 1.5 : 1.0,
                                                            ),
                                                          ),
                                                          focusedBorder: OutlineInputBorder(
                                                            borderSide: BorderSide(
                                                              color: isExceeding ? Colors.red : Colors.orange,
                                                              width: 1.5,
                                                            ),
                                                          ),
                                                          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                                        ),
                                                        onChanged: (_) => setState(() {}),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    IconButton(
                                                      icon: const Icon(Icons.add_circle_outline, size: 22),
                                                      color: canIncrease ? Colors.orange : Colors.grey,
                                                      padding: EdgeInsets.zero,
                                                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                                      tooltip: 'Increase quantity',
                                                      onPressed: canIncrease
                                                          ? () {
                                                              final newQty = (enteredQty + 1).clamp(0.0, remaining);
                                                              _qtyControllers[lineId]?.text = _formatQty(newQty);
                                                              setState(() {});
                                                            }
                                                          : null,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    InkWell(
                                                      onTap: !isAtMax
                                                          ? () {
                                                              _qtyControllers[lineId]?.text = _formatQty(remaining);
                                                              setState(() {});
                                                            }
                                                          : null,
                                                      borderRadius: BorderRadius.circular(4),
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                                        decoration: BoxDecoration(
                                                          color: (isAtMax ? Colors.grey : Colors.orange).withOpacity(0.15),
                                                          borderRadius: BorderRadius.circular(4),
                                                          border: Border.all(
                                                            color: isAtMax ? Colors.grey : Colors.orange,
                                                            width: 1,
                                                          ),
                                                        ),
                                                        child: Text(
                                                          'MAX',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.bold,
                                                            color: isAtMax ? Colors.grey : Colors.orange,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        '/ ${_formatQty(remaining)} max',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: isExceeding ? Colors.red : Colors.grey,
                                                          fontWeight: isExceeding ? FontWeight.bold : FontWeight.normal,
                                                        ),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                if (!isExceeding && enteredQty > 0.0001) ...[
                                                  const SizedBox(height: 4),
                                                  Padding(
                                                    padding: const EdgeInsets.only(left: 48),
                                                    child: Text(
                                                      'Refund: ${currencyFormat.format((enteredQty * basePrice) * (1.0 + (vatRate / 100.0)))}',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.orange.shade800,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                                if (isExceeding) ...[
                                                  const SizedBox(height: 4),
                                                  Padding(
                                                    padding: const EdgeInsets.only(left: 48),
                                                    child: Text(
                                                      'Cannot exceed remaining (${_formatQty(remaining)}) of ordered (${_formatQty(originalQty)})',
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                        color: Colors.red,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ] else if (enteredQty <= 0.0001) ...[
                                                  const SizedBox(height: 4),
                                                  const Padding(
                                                    padding: EdgeInsets.only(left: 48),
                                                    child: Text(
                                                      'Quantity must be greater than zero',
                                                      style: TextStyle(fontSize: 11, color: Colors.red),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            );
                                          },
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    // Bottom bar
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, -2))],
                      ),
                      child: SafeArea(
                        top: false,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_hasInvalidSelectedQuantities)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 8.0),
                                child: Row(
                                  children: [
                                    Icon(Icons.error_outline, color: Colors.red, size: 16),
                                    SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'Please fix invalid or exceeding quantities before reversing.',
                                        style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text('$_selectedCount item(s) selected'),
                                ),
                                Text(
                                  'Total: ${currencyFormat.format(_reversalTotal)}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  textAlign: TextAlign.right,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _selectedCount > 0 &&
                                        _reversalTotal > 0 &&
                                        !_hasInvalidSelectedQuantities &&
                                        !_isProcessing
                                    ? (widget.isReturnMode ? _continueToReturnSummary : _confirmReversal)
                                    : null,
                                icon: Icon(widget.isReturnMode ? Icons.arrow_forward_rounded : Icons.undo),
                                label: Text(widget.isReturnMode ? 'Continue to Return Summary' : 'Reverse Selected Items'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: widget.isReturnMode ? theme.primaryColor : Colors.orange,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (_isProcessing)
                  Container(
                    color: Colors.black.withOpacity(0.4),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
    );
  }
}
