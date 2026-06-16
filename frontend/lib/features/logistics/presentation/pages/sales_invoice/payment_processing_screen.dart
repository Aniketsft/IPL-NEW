import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:enterprise_auth_mobile/core/app_theme.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_cart_cubit.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'invoice_preview_screen.dart';

class PaymentProcessingScreen extends StatefulWidget {
  const PaymentProcessingScreen({super.key});

  @override
  State<PaymentProcessingScreen> createState() =>
      _PaymentProcessingScreenState();
}

class _PaymentProcessingScreenState extends State<PaymentProcessingScreen> {
  String _selectedMethod = 'CASH'; // 'CASH', 'CHEQUE', 'QR', 'CREDIT'

  // Cheque Fields
  final _bankCodeController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _chequeNumController = TextEditingController();
  final _chequeDateController = TextEditingController();
  final _qrRefController = TextEditingController();

  final currencyFormat = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'RS ',
    decimalDigits: 2,
  );
  bool _isProcessing = false;

  Future<void> _processPayment(SalesInvoiceCartState cartState) async {
    if (cartState.customer == null || cartState.items.isEmpty) return;

    final grandTotal = cartState.grandTotal;

    // Validate Credit Limit
    if (_selectedMethod == 'CREDIT') {
      final outstandingStr =
          cartState.customer!['outstandingBalance']?.toString() ?? '0';
      double outstanding = double.tryParse(outstandingStr) ?? 0.0;
      final creditLimitStr =
          cartState.customer!['creditLimit']?.toString() ?? '0';
      double creditLimit = double.tryParse(creditLimitStr) ?? 0.0;

      if (creditLimit > 0 && (outstanding + grandTotal) > creditLimit) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Credit Limit Exceeded! Payment cannot be processed on account.',
            ),
          ),
        );
        return;
      }
    }

    // Validate Cheque
    if (_selectedMethod == 'CHEQUE') {
      if (_bankNameController.text.isEmpty ||
          _chequeNumController.text.isEmpty ||
          _chequeDateController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill all cheque details.')),
        );
        return;
      }
    }

    setState(() => _isProcessing = true);

    try {
      final db = await LocalDatabaseHelper.instance.database;
      final batch = db.batch();

      final invoiceId =
          'INV-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}'; // Mock ID

      // 1. Insert Invoice
      batch.insert(LocalDatabaseHelper.tableSiInvoices, {
        'invoiceId': invoiceId,
        'customerCode': cartState.customer!['code'],
        'customerName': cartState.customer!['name'],
        'totalVat': cartState.totalVat,
        'totalDiscount': cartState.totalDiscount,
        'grandTotal': grandTotal,
        'createdAt': DateTime.now().toIso8601String(),
        'status': _selectedMethod == 'CREDIT' ? 'CREDIT' : 'PAID',
        'isSynced': 0,
      });

      // 2. Insert Lines
      for (var item in cartState.items) {
        batch.insert(LocalDatabaseHelper.tableSiInvoiceLines, {
          'invoiceId': invoiceId,
          'sku': item.product.sku,
          'name': item.product.name,
          'quantity': item.quantity,
          'basePrice': item.basePrice,
          'discountAmount': item.discountAmount,
          'vatAmount': item.vatAmount,
          'total': item.total,
        });
      }

      // 3. Insert Payment
      batch.insert(LocalDatabaseHelper.tableSiPayments, {
        'invoiceId': invoiceId,
        'method': _selectedMethod,
        'amount': grandTotal,
        'bankCode': _bankCodeController.text,
        'bankName': _bankNameController.text,
        'chequeNumber': _chequeNumController.text,
        'chequeDate': _chequeDateController.text,
        'qrTransactionRef': _qrRefController.text,
      });

      await batch.commit(noResult: true);

      // Clear Cart
      if (!mounted) return;
      context.read<SalesInvoiceCartCubit>().clearCart();

      // Navigate to Preview
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => InvoicePreviewScreen(
            invoiceId: invoiceId,
            customer: cartState.customer!,
            subtotal: cartState.subtotal,
            discountAmount: cartState.totalDiscount,
            vatAmount: cartState.totalVat,
            grandTotal: grandTotal,
            paymentMethod: _selectedMethod,
            paymentStatus: _selectedMethod == 'CREDIT' ? 'CREDIT' : 'PAID',
            items: cartState.items,
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Widget _buildMethodButton(String method, IconData icon, String label, {bool isEnabled = true}) {
    final isSelected = _selectedMethod == method;
    return Expanded(
      child: GestureDetector(
        onTap: isEnabled ? () => setState(() => _selectedMethod = method) : null,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primaryAmber.withOpacity(0.1)
                : (isEnabled ? Colors.transparent : Colors.grey.withOpacity(0.1)),
            border: Border.all(
              color: isSelected
                  ? AppTheme.primaryAmber
                  : (isEnabled ? Colors.grey.withOpacity(0.3) : Colors.grey.withOpacity(0.1)),
              width: isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? AppTheme.primaryAmber : (isEnabled ? Colors.grey : Colors.grey.withOpacity(0.4)),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? AppTheme.primaryAmber : (isEnabled ? Colors.grey[700] : Colors.grey.withOpacity(0.4)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Processing'),
        centerTitle: true,
      ),
      body: BlocBuilder<SalesInvoiceCartCubit, SalesInvoiceCartState>(
        builder: (context, state) {
          if (state.customer == null) {
            return const Center(child: Text('No Customer'));
          }

          final customer = state.customer!;
          final statusStr = customer['statusFlag']?.toString() ?? '1';
          
          // 1. Cheque is allowed only if OSTCTL_0 (statusStr) == 1
          bool isChequeEnabled = (statusStr == '1');
          
          // 2. Credit is allowed if:
          //    - Not on hold (OSTCTL_0 != 3)
          //    - Available credit covers the invoice
          bool isCreditEnabled = false;
          
          if (statusStr != '3') {
            final creditLimitStr = customer['creditLimit']?.toString() ?? '0';
            final outstandingStr = customer['outstandingBalance']?.toString() ?? '0';
            double creditLimit = double.tryParse(creditLimitStr) ?? 0.0;
            double outstanding = double.tryParse(outstandingStr) ?? 0.0;
            
            if (creditLimit > 0 && (creditLimit - outstanding) >= state.grandTotal) {
               isCreditEnabled = true;
            }
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Summary Card
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(
                          'TOTAL AMOUNT DUE',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          currencyFormat.format(state.grandTotal),
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Methods
                const Text(
                  'SELECT PAYMENT METHOD',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildMethodButton('CASH', Icons.money, 'CASH'),
                    _buildMethodButton('CHEQUE', Icons.receipt_long, 'CHEQUE', isEnabled: isChequeEnabled),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildMethodButton('QR', Icons.qr_code, 'QR CODE'),
                    _buildMethodButton(
                      'CREDIT',
                      Icons.account_balance_wallet,
                      'CREDIT',
                      isEnabled: isCreditEnabled,
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Method Specific UI
                if (_selectedMethod == 'CHEQUE') ...[
                  const Text(
                    'Cheque Details',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bankNameController,
                    decoration: const InputDecoration(
                      labelText: 'Bank Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bankCodeController,
                    decoration: const InputDecoration(
                      labelText: 'Bank Code (Optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _chequeNumController,
                    decoration: const InputDecoration(
                      labelText: 'Cheque Number',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _chequeDateController,
                    decoration: const InputDecoration(
                      labelText: 'Cheque Date (DD/MM/YYYY)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],

                if (_selectedMethod == 'QR') ...[
                  const Text(
                    'MauCAS QR Code',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  const Center(
                    child: Icon(
                      Icons.qr_code_2,
                      size: 150,
                      color: Colors.blueGrey,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Please ask customer to scan. Enter reference below:',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _qrRefController,
                    decoration: const InputDecoration(
                      labelText: 'Transaction Reference',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],

                const SizedBox(height: 48),

                // Process Button
                ElevatedButton(
                  onPressed: _isProcessing
                      ? null
                      : () => _processPayment(state),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: AppTheme.primaryAmber,
                    foregroundColor: Colors.white,
                  ),
                  child: _isProcessing
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'PROCESS PAYMENT',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
