import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/transaction_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/transaction_history_repository.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/credit_note_pdf_service.dart';
import 'package:enterprise_auth_mobile/core/widgets/industrial_module_layout.dart';

/// Screen allowing the user to select specific invoice lines (and quantities)
/// to reverse, generating a partial Credit Note.
class InvoiceItemReversalScreen extends StatefulWidget {
  final TransactionModel transaction;

  const InvoiceItemReversalScreen({super.key, required this.transaction});

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

  final currencyFormat = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'RS ',
    decimalDigits: 2,
  );

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
            text: isFullyReversed ? '0' : remaining.toStringAsFixed(remaining == remaining.truncate() ? 0 : 2),
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

  String _formatQty(double val) =>
      val % 1 == 0 ? val.toStringAsFixed(0) : val.toStringAsFixed(2);

  bool get _hasInvalidSelectedQuantities {
    for (final line in _lines) {
      final lineId = line['lineId']?.toString() ?? line['id']?.toString() ?? '';
      if (_selected[lineId] == true) {
        final originalQty = (line['quantity'] as num?)?.toDouble() ?? 0.0;
        final alreadyReversed = _alreadyReversedQty[lineId] ?? 0.0;
        final remaining = originalQty - alreadyReversed;
        final qty = double.tryParse(_qtyControllers[lineId]?.text ?? '') ?? 0.0;
        if (qty <= 0 || qty > remaining) {
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
        final qty = double.tryParse(_qtyControllers[lineId]?.text ?? '0') ?? 0.0;
        if (qty > 0 && qty <= remaining) {
          final basePrice = (line['basePrice'] as num?)?.toDouble() ?? 0.0;
          total += basePrice * qty;
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
        final qty = double.tryParse(_qtyControllers[lineId]?.text ?? '0') ?? 0.0;

        if (qty <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Quantity for "${line['name'] ?? lineId}" must be greater than zero.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        if (qty > remaining) {
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

    // Summary confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.undo, color: Colors.orange),
            SizedBox(width: 8),
            Text('Confirm Partial Reversal'),
          ],
        ),
        content: Column(
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
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm Reversal'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isProcessing = true);
    try {
      final creditNote = await _repository.partialReverseInvoice(widget.transaction, selectedLines);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IndustrialModuleLayout(
      title: 'Reverse Items',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Column(
                  children: [
                    // Header info
                    Container(
                      margin: const EdgeInsets.all(16),
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

                          return Opacity(
                            opacity: isFullyReversed ? 0.4 : 1.0,
                            child: Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                  color: isSelected ? Colors.orange : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
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
                                              : (val) => setState(() => _selected[lineId] = val ?? false),
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
                                                'SKU: ${line['sku'] ?? ''} | Unit: ${line['salesUnit'] ?? 'EA'}',
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
                                          final enteredQty = double.tryParse(_qtyControllers[lineId]?.text ?? '') ?? 0.0;
                                          final isExceeding = enteredQty > remaining;

                                          return Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  const SizedBox(width: 48),
                                                  IconButton(
                                                    icon: const Icon(Icons.remove_circle_outline, size: 22),
                                                    color: enteredQty > 1 ? Colors.orange : Colors.grey,
                                                    padding: EdgeInsets.zero,
                                                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                                    tooltip: 'Decrease quantity',
                                                    onPressed: enteredQty > 1
                                                        ? () {
                                                            final newQty = (enteredQty - 1).clamp(1.0, remaining);
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
                                                    color: (enteredQty < remaining && !isExceeding) ? Colors.orange : Colors.grey,
                                                    padding: EdgeInsets.zero,
                                                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                                    tooltip: 'Increase quantity',
                                                    onPressed: (enteredQty < remaining && !isExceeding)
                                                        ? () {
                                                            final newQty = (enteredQty + 1).clamp(0.0, remaining);
                                                            _qtyControllers[lineId]?.text = _formatQty(newQty);
                                                            setState(() {});
                                                          }
                                                        : null,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  InkWell(
                                                    onTap: enteredQty != remaining
                                                        ? () {
                                                            _qtyControllers[lineId]?.text = _formatQty(remaining);
                                                            setState(() {});
                                                          }
                                                        : null,
                                                    borderRadius: BorderRadius.circular(4),
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                                      decoration: BoxDecoration(
                                                        color: (enteredQty == remaining ? Colors.grey : Colors.orange).withOpacity(0.15),
                                                        borderRadius: BorderRadius.circular(4),
                                                        border: Border.all(
                                                          color: enteredQty == remaining ? Colors.grey : Colors.orange,
                                                          width: 1,
                                                        ),
                                                      ),
                                                      child: Text(
                                                        'MAX',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                          color: enteredQty == remaining ? Colors.grey : Colors.orange,
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
                                              ] else if (enteredQty <= 0) ...[
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
                                Text('$_selectedCount item(s) selected'),
                                Text(
                                  'Total: ${currencyFormat.format(_reversalTotal)}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                                    ? _confirmReversal
                                    : null,
                                icon: const Icon(Icons.undo),
                                label: const Text('Reverse Selected Items'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
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
