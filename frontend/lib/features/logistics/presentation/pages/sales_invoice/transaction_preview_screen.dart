import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:enterprise_auth_mobile/core/app_theme.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/transaction_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/transaction_history_repository.dart';

class TransactionPreviewScreen extends StatefulWidget {
  final TransactionModel transaction;

  const TransactionPreviewScreen({super.key, required this.transaction});

  @override
  State<TransactionPreviewScreen> createState() => _TransactionPreviewScreenState();
}

class _TransactionPreviewScreenState extends State<TransactionPreviewScreen> {
  final TransactionHistoryRepository _repository = TransactionHistoryRepository();
  List<Map<String, dynamic>> _lines = [];
  bool _isLoading = true;

  final currencyFormat = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'RS ',
    decimalDigits: 2,
  );

  @override
  void initState() {
    super.initState();
    _loadLines();
  }

  Future<void> _loadLines() async {
    try {
      final lines = await _repository.getTransactionLines(widget.transaction.id);
      setState(() {
        _lines = lines;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load transaction lines: $e')),
        );
      }
    }
  }

  Future<void> _showCancelConfirmation() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Invoice', style: TextStyle(color: Colors.red)),
        content: const Text(
          'Are you sure you want to cancel this invoice? This will reverse the transaction, generate a Credit Note, and return the stock.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, Cancel', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        await _repository.cancelInvoice(widget.transaction);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invoice cancelled successfully.')),
          );
          Navigator.of(context).pop(true); // Return true so history screen refreshes
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to cancel invoice: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    DateTime parsedDate;
    try {
      parsedDate = DateTime.parse(widget.transaction.createdAt);
    } catch (_) {
      parsedDate = DateTime.now();
    }
    final dateStr = DateFormat('dd MMM yyyy, HH:mm').format(parsedDate);

    return Scaffold(
      appBar: AppBar(
        title: Text('Transaction ${widget.transaction.id}'),
        centerTitle: true,
        actions: [
          if (widget.transaction.type == 'INVOICE' && widget.transaction.isReversed == 0)
            IconButton(
              icon: const Icon(Icons.cancel, color: Colors.red),
              tooltip: 'Cancel Invoice',
              onPressed: _showCancelConfirmation,
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Card
          Card(
            margin: const EdgeInsets.all(16.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Customer: ${widget.transaction.customerName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text('Type: ${widget.transaction.type}'),
                  const SizedBox(height: 4),
                  Text('Date: $dateStr'),
                  const SizedBox(height: 8),
                  Text(
                    'Grand Total: ${currencyFormat.format(widget.transaction.grandTotal)}',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.primaryAmber),
                  ),
                ],
              ),
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text('Products & Lots', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _lines.isEmpty
                    ? const Center(child: Text('No lines found.'))
                    : ListView.builder(
                        itemCount: _lines.length,
                        itemBuilder: (context, index) {
                          final line = _lines[index];
                          final sku = line['sku'] ?? 'Unknown';
                          final name = line['name'] ?? 'Unknown Item';
                          final lot = line['lotNumber'] ?? 'No Lot';
                          final qty = (line['quantity'] as num?)?.toDouble() ?? 0.0;
                          final price = (line['basePrice'] as num?)?.toDouble() ?? 0.0;
                          
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                            child: ListTile(
                              title: Text('$sku - $name', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Lot: $lot'),
                                  Text('Qty: $qty EA'),
                                ],
                              ),
                              trailing: Text(
                                currencyFormat.format(price * qty),
                                style: const TextStyle(fontWeight: FontWeight.bold),
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
}
