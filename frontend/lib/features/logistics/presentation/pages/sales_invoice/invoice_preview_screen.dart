import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:enterprise_auth_mobile/core/app_theme.dart';
import 'package:enterprise_auth_mobile/core/widgets/industrial_module_layout.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_cart_cubit.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/sales_invoice_pdf_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/credit_note_pdf_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/credit_note_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'package:enterprise_auth_mobile/core/utils/currency_formatter.dart';
import 'package:enterprise_auth_mobile/core/services/printer_service.dart';
import 'pdf_preview_screen.dart';

class InvoicePreviewScreen extends StatefulWidget {
  final String invoiceId;
  final Map<String, dynamic> customer;
  final double subtotal;
  final double discountAmount;
  final double vatAmount;
  final double grandTotal;
  final String paymentMethod;
  final String paymentStatus;
  final List<CartItem> items;
  final bool isCreditNote;
  final String? creditNoteReason;
  final CreditNoteModel? creditNoteModel;
  final bool isPartiallyReversed;
  final double totalCreditedAmount;
  final double netBalanceDue;

  const InvoicePreviewScreen({
    super.key,
    required this.invoiceId,
    required this.customer,
    required this.subtotal,
    required this.discountAmount,
    required this.vatAmount,
    required this.grandTotal,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.items,
    this.isCreditNote = false,
    this.creditNoteReason,
    this.creditNoteModel,
    this.isPartiallyReversed = false,
    this.totalCreditedAmount = 0.0,
    this.netBalanceDue = 0.0,
  });

  @override
  State<InvoicePreviewScreen> createState() => _InvoicePreviewScreenState();
}

class _InvoicePreviewScreenState extends State<InvoicePreviewScreen> {
  bool _isPrinting = false;
  bool _isGeneratingPreview = false;

  Future<Uint8List> _generateDocumentPdf([PdfPageFormat format = PdfPageFormat.roll80]) async {
    if (widget.isCreditNote) {
      final creditNote = widget.creditNoteModel ??
          CreditNoteModel(
            creditNoteId: widget.invoiceId,
            creditNoteType: CreditNoteType.reversal,
            x3CreditNoteType: 'CRN',
            salesSite: 'IPL',
            customerCode: widget.customer['code']?.toString() ?? '',
            customerName: widget.customer['name']?.toString() ?? '',
            currency: 'MUR',
            grandTotal: widget.grandTotal,
            settlementType: 'REFUND',
            reference: '',
            reason: widget.creditNoteReason,
            createdAt: DateTime.now().toIso8601String(),
            createdBy: 'USER',
          );

      return await CreditNotePdfService().generateCreditNotePdf(
        pageFormat: format,
        creditNote: creditNote,
        resolvedLines: widget.items.map((i) => {
          'sku': i.product.sku,
          'name': i.product.name,
          'quantity': i.quantity,
          'basePrice': i.basePrice,
          'salesUnit': i.product.salesUnit,
          'stockStatus': i.product.stockStatus,
        }).toList(),
      );
    } else {
      final pdfService = SalesInvoicePdfService();
      return await pdfService.generateInvoicePdf(
        pageFormat: format,
        invoiceId: widget.invoiceId,
        customer: widget.customer,
        items: widget.items,
        subtotal: widget.subtotal,
        discountAmount: widget.discountAmount,
        vatAmount: widget.vatAmount,
        grandTotal: widget.grandTotal,
        paymentMethod: widget.paymentMethod,
        paymentStatus: widget.paymentStatus,
        isPartiallyReversed: widget.isPartiallyReversed,
        creditedAmount: widget.totalCreditedAmount,
        netBalanceDue: widget.netBalanceDue,
      );
    }
  }

  Future<void> _handlePdfPreview() async {
    if (_isGeneratingPreview || _isPrinting) return;
    setState(() => _isGeneratingPreview = true);

    try {
      final pdfBytes = await _generateDocumentPdf(PdfPageFormat.a4);
      if (mounted) {
        final docTitle = widget.isCreditNote
            ? 'Credit Note ${widget.invoiceId}'
            : 'Invoice ${widget.invoiceId}';
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PdfPreviewScreen(
              title: docTitle,
              pdfBytes: pdfBytes,
            ),
          ),
        );
      }
    } catch (e, stack) {
      debugPrint('InvoicePreviewScreen: Failed to generate preview: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate preview: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPreview = false);
    }
  }

  Future<void> _handlePrintBluetooth() async {
    if (_isPrinting || _isGeneratingPreview) return;
    setState(() => _isPrinting = true);

    try {
      final docName = widget.isCreditNote
          ? 'CreditNote_${widget.invoiceId}'
          : 'Invoice_${widget.invoiceId}';

      final doc = widget.isCreditNote
          ? CreditNotePdfService().buildCreditNoteDoc(
              creditNote: widget.creditNoteModel ??
                  CreditNoteModel(
                    creditNoteId: widget.invoiceId,
                    creditNoteType: CreditNoteType.reversal,
                    x3CreditNoteType: 'CRN',
                    salesSite: 'IPL',
                    customerCode: widget.customer['code']?.toString() ?? '',
                    customerName: widget.customer['name']?.toString() ?? '',
                    currency: 'MUR',
                    grandTotal: widget.grandTotal,
                    settlementType: 'REFUND',
                    reference: '',
                    reason: widget.creditNoteReason,
                    createdAt: DateTime.now().toIso8601String(),
                    createdBy: 'USER',
                  ),
              resolvedLines: widget.items.map((i) => {
                'sku': i.product.sku,
                'name': i.product.name,
                'quantity': i.quantity,
                'basePrice': i.basePrice,
                'salesUnit': i.product.salesUnit,
                'stockStatus': i.product.stockStatus,
              }).toList(),
            )
          : SalesInvoicePdfService().buildInvoiceDoc(
              invoiceId: widget.invoiceId,
              customer: widget.customer,
              items: widget.items,
              subtotal: widget.subtotal,
              discountAmount: widget.discountAmount,
              vatAmount: widget.vatAmount,
              grandTotal: widget.grandTotal,
              paymentMethod: widget.paymentMethod,
              paymentStatus: widget.paymentStatus,
              isPartiallyReversed: widget.isPartiallyReversed,
              creditedAmount: widget.totalCreditedAmount,
              netBalanceDue: widget.netBalanceDue,
            );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sending to Bluetooth printer...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      await PrinterService.instance.printThermalLinesViaBluetooth(
        lines: doc.toPrintLines(),
        documentName: docName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Document printed successfully on Sewoo LK-P43II'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e, stack) {
      debugPrint('InvoicePreviewScreen: Failed to print: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to print: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPrinting = false);
      }
    }
  }

  Future<void> _handlePrint() => _handlePrintBluetooth();

  @override
  Widget build(BuildContext context) {
    final invoiceId = widget.invoiceId;
    final customer = widget.customer;
    final subtotal = widget.subtotal;
    final discountAmount = widget.discountAmount;
    final vatAmount = widget.vatAmount;
    final grandTotal = widget.grandTotal;
    final paymentMethod = widget.paymentMethod;
    final paymentStatus = widget.paymentStatus;
    final items = widget.items;

    final currencyFormat = CurrencyFormatter.currencyFormat;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return IndustrialModuleLayout(
      title: widget.isCreditNote ? 'Credit Note Preview' : 'Invoice Preview',
      showHome: false,
      extraActions: [
        if (_isPrinting || _isGeneratingPreview)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else ...[
          IconButton(
            onPressed: _handlePdfPreview,
            icon: const Icon(Icons.picture_as_pdf_rounded),
            tooltip: 'Preview PDF',
          ),
          IconButton(
            onPressed: _handlePrintBluetooth,
            icon: Icon(Icons.print_rounded, color: Theme.of(context).primaryColor),
            tooltip: 'Print via Bluetooth',
          ),
        ],
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.grey.withOpacity(0.3)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.isCreditNote ? 'CREDIT NOTE NUMBER' : 'INVOICE NUMBER',
                          style: TextStyle(
                            color: isDark ? Colors.white54 : Colors.grey[600],
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              invoiceId,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            if (widget.isPartiallyReversed) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.orange),
                                ),
                                child: const Text(
                                  'PARTIAL REV',
                                  style: TextStyle(
                                    color: Colors.orange,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'DATE',
                          style: TextStyle(
                            color: isDark ? Colors.white54 : Colors.grey[600],
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(DateFormat('MMM dd, yyyy').format(DateTime.now())),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: widget.isPartiallyReversed
                            ? Colors.orange.shade700
                            : ((paymentStatus == 'PAID' || paymentStatus == 'REFUNDED')
                                ? Colors.green
                                : Colors.orange),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            (paymentStatus == 'PAID' || paymentStatus == 'REFUNDED') && !widget.isPartiallyReversed
                                ? Icons.check_circle
                                : Icons.schedule,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            widget.isPartiallyReversed ? 'PARTIAL REV' : paymentStatus,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Billed To / Credited To
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.grey.withOpacity(0.3)),
              ),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.business),
                ),
                title: Text(
                  widget.isCreditNote ? 'CREDITED TO' : 'BILLED TO',
                  style: TextStyle(color: isDark ? Colors.white54 : Colors.grey[600], fontSize: 10, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  customer['name']?.toString() ?? 'Unknown Customer',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),

            // Credit Note Reason card
            if (widget.isCreditNote && (widget.creditNoteReason?.isNotEmpty ?? false)) ...[
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.assignment_return_outlined, color: Colors.orange),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CREDIT NOTE REASON',
                              style: TextStyle(
                                color: isDark ? Colors.white54 : Colors.grey[600],
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Builder(
                              builder: (context) {
                                final rawReason = widget.creditNoteReason ?? '';
                                String display = rawReason;
                                if (rawReason.isNotEmpty && !rawReason.contains('(')) {
                                  final match = LocalDatabaseHelper.defaultCreditNoteReasons.firstWhere(
                                    (r) => r['code'] == rawReason,
                                    orElse: () => {'code': rawReason, 'description': rawReason},
                                  );
                                  if (match['description'] != rawReason) {
                                    display = '${match['description']} ($rawReason)';
                                  }
                                }
                                return Text(
                                  display,
                                  style: TextStyle(
                                    color: isDark ? Colors.white : Colors.black87,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Line Items
            Text(
              widget.isCreditNote ? 'Returned Line Items' : 'Line Items',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.grey.withOpacity(0.3)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: items.map((item) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.product.name,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? Colors.white : Colors.black87,
                                        ),
                                      ),
                                    ),
                                    if (widget.isCreditNote) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: (item.product.stockStatus?.toUpperCase() == 'Q')
                                              ? Colors.orange.withOpacity(0.15)
                                              : Colors.green.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                            color: (item.product.stockStatus?.toUpperCase() == 'Q')
                                                ? Colors.orange
                                                : Colors.green,
                                          ),
                                        ),
                                        child: Text(
                                          (item.product.stockStatus?.toUpperCase() == 'Q') ? 'STATUS Q' : 'STATUS A',
                                          style: TextStyle(
                                            color: (item.product.stockStatus?.toUpperCase() == 'Q')
                                                ? Colors.orange.shade800
                                                : Colors.green.shade800,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${item.quantity} x ${currencyFormat.format(item.basePrice)}',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              currencyFormat.format(item.total),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Payment / Refund Method
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.grey.withOpacity(0.3)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.isCreditNote ? 'REFUND METHOD' : 'PAYMENT METHOD',
                      style: TextStyle(color: isDark ? Colors.white54 : Colors.grey[600], fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          widget.isCreditNote
                              ? Icons.assignment_return
                              : paymentMethod == 'CHEQUE'
                              ? Icons.receipt_long
                              : paymentMethod == 'CREDIT'
                              ? Icons.account_balance_wallet
                              : paymentMethod == 'QR'
                              ? Icons.qr_code
                              : Icons.money,
                          color: widget.isCreditNote ? AppTheme.primaryAmber : null,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          paymentMethod,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Summary
            Card(
              elevation: 0,
              color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.withOpacity(0.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Subtotal',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ),
                        Text(
                          currencyFormat.format(subtotal),
                          textAlign: TextAlign.right,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Discount',
                            style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[600]),
                          ),
                        ),
                        Text(
                          CurrencyFormatter.formatDiscount(discountAmount),
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.right,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text('VAT', style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[600])),
                        ),
                        Text(
                          currencyFormat.format(vatAmount),
                          textAlign: TextAlign.right,
                        ),
                      ],
                    ),
                    if (widget.isPartiallyReversed) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text('Less Credited', style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[600])),
                          ),
                          Text(
                            '-${currencyFormat.format(widget.totalCreditedAmount)}',
                            style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.right,
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            widget.isCreditNote
                                ? 'Total Refund'
                                : (widget.isPartiallyReversed ? 'Net Balance Due' : 'Grand Total'),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Text(
                          currencyFormat.format(widget.isPartiallyReversed ? widget.netBalanceDue : grandTotal),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryAmber,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  // Navigate back to the Select Transaction screen
                  Navigator.of(context).popUntil(
                    (route) => route.settings.name == '/sales' || route.isFirst,
                  );
                },
                icon: const Icon(Icons.dashboard),
                label: const Text('CLOSE & RETURN'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (_isPrinting || _isGeneratingPreview) ? null : _handlePdfPreview,
                      icon: _isGeneratingPreview
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.picture_as_pdf_rounded),
                      label: const Text('PREVIEW PDF'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (_isPrinting || _isGeneratingPreview) ? null : _handlePrintBluetooth,
                      icon: _isPrinting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.print_rounded),
                      label: Text(
                        _isPrinting
                            ? 'PRINTING...'
                            : (widget.isCreditNote ? 'PRINT CRN (BT)' : 'PRINT INV (BT)'),
                      ),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 50),
                        backgroundColor: AppTheme.primaryAmber,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
