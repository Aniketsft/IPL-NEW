import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:enterprise_auth_mobile/core/app_theme.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/transaction_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/credit_note_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_cart_cubit.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/transaction_history_repository.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/credit_note_pdf_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/sales_invoice_pdf_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/sales_invoice_product_model.dart';

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
        final creditNote = await _repository.cancelInvoice(widget.transaction);
        if (mounted) {
          setState(() => _isLoading = false);
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 8),
                  Text('Invoice Cancelled'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Credit Note ${creditNote.creditNoteId} generated successfully.'),
                  const SizedBox(height: 6),
                  const Text('Stock replenished and transaction recorded.'),
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
                        resolvedLines: _lines,
                      ),
                    );
                  },
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pop(true);
                  },
                  child: const Text('Done'),
                ),
              ],
            ),
          );
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

  Future<void> _handlePrint() async {
    final isCreditNote = widget.transaction.type == 'CREDIT_NOTE' || widget.transaction.id.startsWith('CN-');
    if (isCreditNote) {
      final creditNote = CreditNoteModel(
        creditNoteId: widget.transaction.id,
        creditNoteType: CreditNoteType.reversal,
        x3CreditNoteType: 'CRN',
        salesSite: 'SCG',
        customerCode: widget.transaction.customerCode,
        customerName: widget.transaction.customerName,
        currency: 'MUR',
        grandTotal: widget.transaction.grandTotal,
        originalInvoiceId: widget.transaction.id.replaceFirst('CN-', ''),
        settlementType: 'REFUND',
        reference: widget.transaction.id,
        isSynced: widget.transaction.isSynced,
        createdAt: widget.transaction.createdAt,
        createdBy: widget.transaction.auditMetadata.createdByUserName ?? 'SYSTEM',
        deviceId: widget.transaction.auditMetadata.deviceId,
      );

      await Printing.layoutPdf(
        onLayout: (format) => CreditNotePdfService().generateCreditNotePdf(
          pageFormat: format,
          creditNote: creditNote,
          resolvedLines: _lines,
        ),
      );
    } else {
      // Print Invoice thermal format
      final pdfService = SalesInvoicePdfService();
      await Printing.layoutPdf(
        dynamicLayout: true,
        onLayout: (format) async {
          return await pdfService.generateInvoicePdf(
            pageFormat: format,
            invoiceId: widget.transaction.id,
            customer: {
              'code': widget.transaction.customerCode,
              'name': widget.transaction.customerName,
            },
            items: _lines.map((l) => CartItem(
              product: SalesInvoiceProductModel(
                sku: (l['sku'] as String?) ?? '',
                name: (l['name'] as String?) ?? '',
                stockQty: (l['quantity'] as num?)?.toDouble() ?? 0.0,
                warehouse: (l['warehouse'] as String?) ?? '',
                salesUnit: (l['salesUnit'] as String?) ?? 'EA',
                cce0: (l['cce0'] as String?) ?? '',
              ),
              quantity: (l['quantity'] as num?)?.toDouble() ?? 0.0,
              basePrice: (l['basePrice'] as num?)?.toDouble() ?? 0.0,
              lotNumber: (l['lotNumber'] as String?) ?? '',
              warehouse: (l['warehouse'] as String?) ?? '',
              location: (l['location'] as String?) ?? '',
              taxRule: (l['taxRule'] as String?) ?? '',
            )).toList(),
            subtotal: widget.transaction.grandTotal,
            discountAmount: 0.0,
            vatAmount: 0.0,
            grandTotal: widget.transaction.grandTotal,
            paymentMethod: 'CASH',
            paymentStatus: widget.transaction.isReversed == 1 ? 'CANCELLED' : 'PAID',
          );
        },
      );
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
    final isCreditNote = widget.transaction.type == 'CREDIT_NOTE' || widget.transaction.id.startsWith('CN-');

    return Scaffold(
      appBar: AppBar(
        title: Text('Transaction ${widget.transaction.id}'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: isCreditNote ? 'Print Credit Note Voucher' : 'Print Invoice Receipt',
            onPressed: _handlePrint,
          ),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Customer: ${widget.transaction.customerName}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                      if (widget.transaction.isReversed == 1)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.red),
                          ),
                          child: const Text(
                            'REVERSED',
                            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        )
                      else if (isCreditNote)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.purple.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.purple),
                          ),
                          child: const Text(
                            'CREDIT NOTE',
                            style: TextStyle(color: Colors.purple, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ),
                    ],
                  ),
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
