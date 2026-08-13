import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:enterprise_auth_mobile/core/app_theme.dart';
import 'package:enterprise_auth_mobile/core/widgets/industrial_module_layout.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_cart_cubit.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/sales_invoice_pdf_service.dart';

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
  });

  @override
  State<InvoicePreviewScreen> createState() => _InvoicePreviewScreenState();
}

class _InvoicePreviewScreenState extends State<InvoicePreviewScreen> {
  bool _isPrinting = false;

  Future<void> _handlePrint() async {
    setState(() => _isPrinting = true);
    try {
      final pdfService = SalesInvoicePdfService();
      
      await Printing.layoutPdf(
        dynamicLayout: true,
        onLayout: (PdfPageFormat format) async {
          final pdfBytes = await pdfService.generateInvoicePdf(
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
          );
          return pdfBytes;
        },
        name: 'Invoice_${widget.invoiceId}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to print: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPrinting = false);
      }
    }
  }

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

    final currencyFormat = NumberFormat.currency(
      locale: 'en_US',
      symbol: 'RS ',
      decimalDigits: 2,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return IndustrialModuleLayout(
      title: 'Invoice Preview',
      showHome: false,
      extraActions: [
        _isPrinting
            ? const Padding(
                padding: EdgeInsets.all(16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                onPressed: _handlePrint,
                icon: Icon(Icons.print_rounded, color: Theme.of(context).primaryColor),
                tooltip: 'Print',
              ),
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
                          'INVOICE NUMBER',
                          style: TextStyle(
                            color: isDark ? Colors.white54 : Colors.grey[600],
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          invoiceId,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
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
                        color: paymentStatus == 'PAID'
                            ? Colors.green
                            : Colors.orange,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            paymentStatus == 'PAID'
                                ? Icons.check_circle
                                : Icons.schedule,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            paymentStatus,
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

            // Billed To
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
                  'BILLED TO',
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
            const SizedBox(height: 24),

            // Line Items
            const Text(
              'Line Items',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
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
                                Text(
                                  item.product.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
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

            // Payment Method
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
                      'PAYMENT METHOD',
                      style: TextStyle(color: isDark ? Colors.white54 : Colors.grey[600], fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          paymentMethod == 'CHEQUE'
                              ? Icons.receipt_long
                              : paymentMethod == 'CREDIT'
                              ? Icons.account_balance_wallet
                              : paymentMethod == 'QR'
                              ? Icons.qr_code
                              : Icons.money,
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
                        Text(
                          'Subtotal',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        Text(currencyFormat.format(subtotal)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Discount',
                          style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[600]),
                        ),
                        Text(
                          '-${currencyFormat.format(discountAmount)}',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('VAT', style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[600])),
                        Text(currencyFormat.format(vatAmount)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Grand Total',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          currencyFormat.format(grandTotal),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryAmber,
                          ),
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
              ElevatedButton.icon(
                onPressed: _isPrinting ? null : _handlePrint,
                icon: _isPrinting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.print),
                label: Text(_isPrinting ? 'GENERATING PDF...' : 'PRINT INVOICE'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: AppTheme.primaryAmber,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
