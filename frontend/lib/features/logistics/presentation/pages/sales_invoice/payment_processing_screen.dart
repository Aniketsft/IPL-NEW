import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:enterprise_auth_mobile/core/app_theme.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_bloc.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_state.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_event.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'package:enterprise_auth_mobile/core/secure_storage_service.dart';
import 'package:enterprise_auth_mobile/core/services/device_info_service.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_state.dart';
import 'invoice_preview_screen.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/credit_note_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/credit_note_pdf_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/credit_note_model.dart';

import 'package:enterprise_auth_mobile/features/logistics/domain/services/si_sales_order_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/sales_invoice_pdf_service.dart';
import 'package:printing/printing.dart';

class PaymentEntry {
  final String id;
  final String method;
  final double amount;
  final String bankCode;
  final String bankName;
  final String chequeNumber;
  final String chequeDate;
  final String qrTransactionRef;

  PaymentEntry({
    required this.id,
    required this.method,
    required this.amount,
    this.bankCode = '',
    this.bankName = '',
    this.chequeNumber = '',
    this.chequeDate = '',
    this.qrTransactionRef = '',
  });
}

class PaymentProcessingScreen extends StatefulWidget {
  final bool isCreditNoteRefund;

  const PaymentProcessingScreen({
    super.key,
    this.isCreditNoteRefund = false,
  });

  @override
  State<PaymentProcessingScreen> createState() =>
      _PaymentProcessingScreenState();
}

class _PaymentProcessingScreenState extends State<PaymentProcessingScreen> {
  String _selectedMethod =
      'CASH'; // 'CASH', 'CHEQUE', 'CREDIT', 'MYT MONEY', 'BLINK'
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();

  // Dynamic Fields
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

  List<PaymentEntry> _payments = [];

  double _getTotalPaid() {
    return _payments.fold(0.0, (sum, item) => sum + item.amount);
  }

  void _addPayment(SalesInvoiceLoaded cartState) {
    final grandTotal = cartState.grandTotal;
    if (grandTotal <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Total amount must be greater than zero.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final totalPaid = _getTotalPaid();
    final remaining = grandTotal - totalPaid;

    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice is already fully paid.')),
      );
      return;
    }

    final amountStr = _amountController.text.trim();
    if (amountStr.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter an amount.')));
      return;
    }

    final amount = double.tryParse(amountStr) ?? 0.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Amount must be greater than 0.')),
      );
      return;
    }

    // Overpayment check
    if (amount > remaining) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Amount cannot exceed the remaining balance.'),
        ),
      );
      return;
    }

    // Dynamic Validations
    if (_selectedMethod == 'CHEQUE') {
      if (_bankNameController.text.isEmpty ||
          _chequeNumController.text.isEmpty ||
          _chequeDateController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please fill all required cheque details.'),
          ),
        );
        return;
      }
    } else if (_selectedMethod == 'QR CODE') {
      if (_qrRefController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transaction reference is required for QR payments.'),
          ),
        );
        return;
      }
    } else if (_selectedMethod == 'CREDIT') {
      final customer = cartState.customer!;
      final creditLimitStr = customer['creditLimit']?.toString() ?? '0';
      final outstandingStr = customer['outstandingBalance']?.toString() ?? '0';
      double creditLimit = double.tryParse(creditLimitStr) ?? 0.0;
      double outstanding = double.tryParse(outstandingStr) ?? 0.0;

      // Calculate existing credit payments in the cart
      double cartCreditTotal = _payments
          .where((p) => p.method == 'CREDIT')
          .fold(0.0, (sum, p) => sum + p.amount);

      if (creditLimit > 0 &&
          (outstanding + cartCreditTotal + amount) > creditLimit) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This amount exceeds the available credit limit.'),
          ),
        );
        return;
      }
    }

    setState(() {
      _payments.add(
        PaymentEntry(
          id: const Uuid().v4(),
          method: _selectedMethod,
          amount: amount,
          bankCode: _bankCodeController.text.trim(),
          bankName: _bankNameController.text.trim(),
          chequeNumber: _chequeNumController.text.trim(),
          chequeDate: _chequeDateController.text.trim(),
          qrTransactionRef: _qrRefController.text.trim(),
        ),
      );

      // Clear dynamic inputs
      _bankCodeController.clear();
      _bankNameController.clear();
      _chequeNumController.clear();
      _chequeDateController.clear();
      _qrRefController.clear();
      _amountController.clear();

      if (_selectedMethod == 'CHEQUE') {
        _chequeDateController.text = DateFormat(
          'dd/MM/yyyy',
        ).format(DateTime.now());
      }
    });
  }

  void _removePayment(PaymentEntry payment) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Payment'),
        content: Text(
          'Are you sure you want to remove this ${payment.method} payment of ${currencyFormat.format(payment.amount)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _payments.removeWhere((p) => p.id == payment.id);
                // Reset amount field if we are removing a payment
                _amountController.clear();
              });
              Navigator.pop(context);
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _processPayment(SalesInvoiceLoaded cartState) async {
    if (cartState.customer == null || cartState.cartItems.isEmpty) return;

    final grandTotal = cartState.grandTotal;
    if (grandTotal <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isCreditNoteRefund
                ? 'Credit note amount must be greater than zero.'
                : 'Invoice amount must be greater than zero.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final totalPaid = _getTotalPaid();

    if (totalPaid < grandTotal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Full payment is required to process the invoice.'),
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final db = await LocalDatabaseHelper.instance.database;
      final batch = db.batch();

      final invoiceId =
          'INV-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';

      // Read user assigned site from AuthBloc synchronously before async gaps
      final authState = context.read<AuthBloc>().state;
      final userSiteCode = (authState is Authenticated &&
              authState.siteCode != null &&
              authState.siteCode!.isNotEmpty &&
              authState.siteCode != 'ALL')
          ? authState.siteCode!
          : 'IPL';

      // Fetch audit details
      final secureStorage = SecureStorageService();
      final username = await secureStorage.getUsername() ?? 'Unknown User';
      final deviceId = DeviceInfoService.instance.deviceInfo;
      final appVersion = '1.0.0';

      // Determine main invoice status
      bool hasCredit = _payments.any((p) => p.method == 'CREDIT');
      String mainStatus = hasCredit ? 'CREDIT' : 'PAID';

      // Handle Credit Note Refund flow
      if (widget.isCreditNoteRefund) {
        final refundMethod = _payments.isNotEmpty ? _payments.first.method : 'CASH';
        final creditNote = await CreditNoteService().createStandaloneCreditNote(
          salesSite: userSiteCode,
          customerCode: cartState.customer!['code'],
          customerName: cartState.customer!['name'],
          refundMethod: refundMethod,
          refundAmount: grandTotal,
          createdBy: username,
          deviceId: deviceId,
          reference: _referenceController.text.trim(),
          items: cartState.cartItems.map((item) => CreditNoteLineModel(
            creditNoteId: '',
            lineNo: 1000,
            quantity: item.quantity,
            standaloneSku: item.product.sku,
            standaloneName: item.product.name,
            standaloneSalesUnit: item.product.salesUnit,
            standalonePrice: item.basePrice,
            standaloneTaxRule: item.taxRule,
            standaloneLot: item.lotNumber,
            standaloneWarehouse: item.warehouse,
            standaloneCce0: item.product.cce0,
          )).toList(),
        );

        if (!mounted) return;
        context.read<SalesInvoiceBloc>().add(ClearCart());

        // Print thermal receipt
        await Printing.layoutPdf(
          onLayout: (format) => CreditNotePdfService().generateCreditNotePdf(
            pageFormat: format,
            creditNote: creditNote,
            resolvedLines: cartState.cartItems.map((i) => {
              'sku': i.product.sku,
              'name': i.product.name,
              'quantity': i.quantity,
              'basePrice': i.basePrice,
            }).toList(),
          ),
        );

        Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      }

        // Resolve the pricing rule: use the first matched pricelist code from any cart item.
        // Falls back to empty string if all items were manually priced.
        final resolvedPricingRule = cartState.cartItems
            .map((i) => i.pricingSource)
            .where((s) => s.isNotEmpty && s != 'MANUAL' && !s.contains('discount-only'))
            .firstOrNull ?? '';

      // 1. Insert Invoice with Active Selected Sales Rep(s)
      final selectedReps = await LocalDatabaseHelper.instance.getSelectedSalesReps(username: username);
      final salesRepString = selectedReps.isNotEmpty
          ? selectedReps.map((r) => (r['code'] ?? '').toString().trim()).where((c) => c.isNotEmpty).join(',')
          : username;

      batch.insert(LocalDatabaseHelper.tableSiInvoices, {
        'invoiceId': invoiceId,
        'customerCode': cartState.customer!['code'],
        'customerName': cartState.customer!['name'],
        'totalVat': cartState.totalVat,
        'totalDiscount': cartState.totalDiscount,
        'grandTotal': grandTotal,
        'createdAt': DateTime.now().toIso8601String(),
        'status': mainStatus,
        'isSynced': 0,
        'transactionType': 'INVOICE',
        'createdByUserId': username,
        'createdByUserName': username,
        'deviceId': deviceId,
        'appVersion': appVersion,
        'reference': _referenceController.text.trim(),
        'invoiceType': 'STD',
        'salesSite': userSiteCode,
        'salesRep': salesRepString,
        'pricingRule': resolvedPricingRule,
        'dueDate': DateTime.now().toIso8601String(),
        'userName': username,
        'createdBy': username,
        'transactionalId': invoiceId,
      });

      // 2. Insert Lines & Deduct Stock
      for (var item in cartState.cartItems) {
        batch.insert(LocalDatabaseHelper.tableSiInvoiceLines, {
          'invoiceId': invoiceId,
          'sku': item.product.sku,
          'name': item.product.name,
          'quantity': item.quantity,
          'basePrice': item.basePrice,
          'discountAmount': item.discountAmount,
          'vatAmount': item.vatAmount,
          'total': item.total,
          'lotNumber': item.lotNumber,
          'warehouse': item.warehouse,
          'location': item.location,
          'salesUnit': item.product.salesUnit,
          'cce0': item.product.cce0,
          'taxRule': item.taxRule,
          'isFoc': item.isFoc ? 1 : 0,
          'pricingSource': item.pricingSource,
          'discountAmountFlat': item.discountAmountFlat,
          'priceListCode': item.priceListCode,
          'reasonType': item.reasonType,
        });

        // Deduct from local stock to prevent overselling offline
        batch.rawUpdate(
          '''
          UPDATE ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails} 
          SET totalQty = totalQty - ? 
          WHERE itemCode = ? AND lotNumber = ? AND warehouse = ? AND location = ?
          ''',
          [item.quantity, item.product.sku, item.lotNumber, item.warehouse, item.location],
        );
      }

      // 3. Insert Payments
      for (var payment in _payments) {
        // If Cash is overpaid, we record exactly the amount they inputted.
        // Wait, typically we just record the full amount paid and the system infers change.
        batch.insert(LocalDatabaseHelper.tableSiPayments, {
          'invoiceId': invoiceId,
          'method': payment.method,
          'amount': payment.amount,
          'bankCode': payment.bankCode,
          'bankName': payment.bankName,
          'chequeNumber': payment.chequeNumber,
          'chequeDate': payment.chequeDate,
          'qrTransactionRef': payment.qrTransactionRef,
        });
      }

      await batch.commit(noResult: true);

      if (cartState.originalDocumentId != null) {
        final service = SISalesOrderService();
        await service.markOrderAsConverted(int.parse(cartState.originalDocumentId!));
      }

      if (!mounted) return;
      context.read<SalesInvoiceBloc>().add(ClearCart());

      // Get distinct payment methods for the preview screen summary
      final distinctMethods = _payments.map((p) => p.method).toSet().join(', ');

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
            paymentMethod: distinctMethods,
            paymentStatus: mainStatus,
            items: cartState.cartItems,
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

  Widget _buildMethodButton(
    String method,
    IconData icon,
    String label, {
    bool isEnabled = true,
  }) {
    final isSelected = _selectedMethod == method;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: GestureDetector(
        onTap: isEnabled
            ? () {
                setState(() {
                  _selectedMethod = method;
                  // Clear dynamic fields when switching
                  _bankCodeController.clear();
                  _bankNameController.clear();
                  _chequeNumController.clear();
                  _chequeDateController.clear();
                  _qrRefController.clear();

                  if (method == 'CHEQUE') {
                    _chequeDateController.text = DateFormat(
                      'dd/MM/yyyy',
                    ).format(DateTime.now());
                  }
                });
              }
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primaryAmber.withOpacity(0.15)
                : (isEnabled
                      ? Theme.of(context).cardColor
                      : Colors.grey.withOpacity(isDark ? 0.05 : 0.1)),
            border: Border.all(
              color: isSelected
                  ? AppTheme.primaryAmber
                  : (isEnabled
                        ? Colors.grey.withOpacity(0.3)
                        : Colors.grey.withOpacity(0.1)),
              width: isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppTheme.primaryAmber.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : (isEnabled
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(
                              isDark ? 0.2 : 0.05,
                            ),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : []),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected
                    ? AppTheme.primaryAmber
                    : (isEnabled
                          ? (isDark ? Colors.white70 : Colors.black87)
                          : Colors.grey.withOpacity(0.4)),
                size: 24,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected
                      ? AppTheme.primaryAmber
                      : (isEnabled
                            ? (isDark ? Colors.white70 : Colors.black87)
                            : Colors.grey.withOpacity(0.4)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleHistoricalPrint(SalesInvoiceLoaded cartState) async {
    final isCreditNote = cartState.transactionType == 'PREVIEW_CREDIT_NOTE';
    if (isCreditNote) {
      final authState = context.read<AuthBloc>().state;
      final userSite = (authState is Authenticated &&
              authState.siteCode != null &&
              authState.siteCode!.isNotEmpty &&
              authState.siteCode != 'ALL')
          ? authState.siteCode!
          : 'IPL';

      final creditNote = CreditNoteModel(
        creditNoteId: cartState.originalDocumentId ?? '',
        creditNoteType: CreditNoteType.reversal,
        x3CreditNoteType: 'CRN',
        salesSite: userSite, 
        customerCode: cartState.customer!['code'],
        customerName: cartState.customer!['name'],
        currency: 'MUR',
        grandTotal: cartState.grandTotal,
        originalInvoiceId: cartState.originalDocumentId?.replaceFirst('CN-', '') ?? '',
        settlementType: 'REFUND',
        reference: cartState.originalDocumentId ?? '',
        isSynced: 0,
        createdAt: DateTime.now().toIso8601String(), 
        createdBy: 'SYSTEM',
        deviceId: '',
      );

      await Printing.layoutPdf(
        onLayout: (format) => CreditNotePdfService().generateCreditNotePdf(
          pageFormat: format,
          creditNote: creditNote,
          resolvedLines: cartState.cartItems.map((i) => {
            'sku': i.product.sku,
            'name': i.product.name,
            'quantity': i.quantity,
            'basePrice': i.basePrice,
          }).toList(),
        ),
      );
    } else {
      final pdfService = SalesInvoicePdfService();
      await Printing.layoutPdf(
        dynamicLayout: true,
        onLayout: (format) async {
          return await pdfService.generateInvoicePdf(
            pageFormat: format,
            invoiceId: cartState.originalDocumentId ?? '',
            customer: {
              'code': cartState.customer!['code'],
              'name': cartState.customer!['name'],
            },
            items: cartState.cartItems.toList(),
            subtotal: cartState.subtotal,
            discountAmount: cartState.totalDiscount,
            vatAmount: cartState.totalVat,
            grandTotal: cartState.grandTotal,
            paymentMethod: 'MULTIPLE',
            paymentStatus: 'PAID',
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SalesInvoiceBloc, SalesInvoiceState>(
      builder: (context, state) {
        if (state is! SalesInvoiceLoaded) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final cartState = state;
        final isPreview = cartState.transactionType.startsWith('PREVIEW');
        
        if (cartState.customer == null && !widget.isCreditNoteRefund) {
          return const Scaffold(body: Center(child: Text('No Customer')));
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(widget.isCreditNoteRefund ? 'Refund Processing' : (isPreview ? 'Transaction Details' : 'Payment Processing')),
            centerTitle: true,
            actions: [
              if (isPreview)
                IconButton(
                  icon: const Icon(Icons.print),
                  tooltip: 'Print',
                  onPressed: () => _handleHistoricalPrint(cartState),
                ),
            ],
          ),
          body: Builder(
            builder: (context) {

          bool isChequeEnabled = false;
          bool isCreditEnabled = false;

          if (widget.isCreditNoteRefund) {
            // For refunds, we don't care about the customer's payment term status
            // because we are refunding them money, which adds to their credit balance.
            isCreditEnabled = true;
          } else {
            final customer = cartState.customer!;
            final statusStr = customer['statusFlag']?.toString() ?? '1';

            isChequeEnabled = (statusStr == '1');

            if (statusStr != '3') {
              final creditLimitStr = customer['creditLimit']?.toString() ?? '0';
              final outstandingStr =
                  customer['outstandingBalance']?.toString() ?? '0';
              double creditLimit = double.tryParse(creditLimitStr) ?? 0.0;
              double outstanding = double.tryParse(outstandingStr) ?? 0.0;

              // Calculate existing credit payments in the cart
              double cartCreditTotal = _payments
                  .where((p) => p.method == 'CREDIT')
                  .fold(0.0, (sum, p) => sum + p.amount);

              if (creditLimit > 0 &&
                  (creditLimit - outstanding - cartCreditTotal) > 0) {
                isCreditEnabled = true;
              }
            }
          }

          final grandTotal = cartState.grandTotal;
          final totalPaid = _getTotalPaid();
          final remaining = grandTotal - totalPaid;
          final isFullyPaid = grandTotal > 0 && remaining <= 0;
          final changeDue = remaining < 0 ? remaining.abs() : 0.0;

          // Set default amount input if empty and not fully paid
          if (!isFullyPaid && _amountController.text.isEmpty) {
            _amountController.text = remaining.toStringAsFixed(2);
          }

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.isCreditNoteRefund ? 'CREDIT NOTE DETAILS' : 'INVOICE DETAILS',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _referenceController,
                        decoration: InputDecoration(
                          labelText: 'Reference Number (Optional)',
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.grey.withOpacity(0.05),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (!isFullyPaid) ...[
                        Text(
                          widget.isCreditNoteRefund ? 'ADD REFUND METHOD' : 'ADD PAYMENT',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _buildMethodButton('CASH', Icons.money, 'CASH'),
                            if (!widget.isCreditNoteRefund)
                              _buildMethodButton(
                                'CHEQUE',
                                Icons.receipt_long,
                                'CHEQUE',
                                isEnabled: isChequeEnabled,
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _buildMethodButton(
                              'CREDIT',
                              Icons.account_balance_wallet,
                              'CREDIT',
                              isEnabled: isCreditEnabled,
                            ),
                            if (!widget.isCreditNoteRefund)
                              _buildMethodButton(
                                'QR CODE',
                                Icons.qr_code_scanner,
                                'QR PAY',
                                isEnabled: true,
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        TextField(
                          controller: _amountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText:
                                'Amount (${currencyFormat.currencySymbol})',
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.grey.withOpacity(0.05),
                          ),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Dynamic Fields
                        if (_selectedMethod == 'CHEQUE') ...[
                          TextField(
                            controller: _bankNameController,
                            decoration: const InputDecoration(
                              labelText: 'Bank Name *',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _bankCodeController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Bank Code (Optional)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _chequeNumController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Cheque Number *',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _chequeDateController,
                            readOnly: true,
                            onTap: () async {
                              final pickedDate = await showDatePicker(
                                context: context,
                                initialDate: DateTime.now(),
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (pickedDate != null) {
                                _chequeDateController.text = DateFormat(
                                  'dd/MM/yyyy',
                                ).format(pickedDate);
                              }
                            },
                            decoration: const InputDecoration(
                              labelText: 'Cheque Date *',
                              border: OutlineInputBorder(),
                              isDense: true,
                              suffixIcon: Icon(Icons.calendar_today),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (_selectedMethod == 'QR CODE') ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.blueGrey.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.blueGrey.withOpacity(0.2),
                              ),
                            ),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.qr_code_2,
                                  size: 80,
                                  color: Colors.blueGrey,
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Scan to Pay',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 16),
                                TextField(
                                  controller: _qrRefController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: 'Transaction Reference *',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    isDense: true,
                                    filled: true,
                                    fillColor: Theme.of(context).cardColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        ElevatedButton.icon(
                          onPressed: () => _addPayment(cartState),
                          icon: const Icon(Icons.add),
                          label: Text(widget.isCreditNoteRefund ? 'ADD REFUND METHOD' : 'ADD PAYMENT'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),
                      if (_payments.isNotEmpty) ...[
                        const Text(
                          'PAYMENT ENTRIES',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _payments.length,
                          itemBuilder: (context, index) {
                            final p = _payments[index];
                            String subtitle = '';
                            if (p.method == 'CHEQUE')
                              subtitle = '${p.bankName} - ${p.chequeNumber}';
                            if (p.method == 'QR CODE')
                              subtitle = 'Ref: ${p.qrTransactionRef}';

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppTheme.primaryAmber
                                      .withOpacity(0.2),
                                  child: Icon(
                                    p.method == 'CASH'
                                        ? Icons.money
                                        : p.method == 'CHEQUE'
                                        ? Icons.receipt_long
                                        : p.method == 'CREDIT'
                                        ? Icons.account_balance_wallet
                                        : Icons.qr_code,
                                    color: AppTheme.primaryAmber,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  '${p.method} - ${currencyFormat.format(p.amount)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: subtitle.isNotEmpty
                                    ? Text(subtitle)
                                    : null,
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => _removePayment(p),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Persistent Bottom Area
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 15,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  MediaQuery.of(context).padding.bottom + 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'GRAND TOTAL',
                          style: TextStyle(
                            color: Theme.of(context).textTheme.bodySmall?.color,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          currencyFormat.format(grandTotal),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'TOTAL PAID',
                          style: TextStyle(
                            color: Theme.of(context).textTheme.bodySmall?.color,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          currencyFormat.format(totalPaid),
                          style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(height: 1),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          remaining < 0 ? 'CHANGE DUE' : 'REMAINING',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: remaining < 0 ? Colors.blue : Colors.red,
                          ),
                        ),
                        Text(
                          currencyFormat.format(
                            remaining < 0 ? changeDue : remaining,
                          ),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: remaining < 0 ? Colors.blue : Colors.red,
                          ),
                        ),
                      ],
                    ),
                    if (grandTotal <= 0)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.withOpacity(0.5)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.isCreditNoteRefund
                                    ? 'Credit note amount must be greater than zero.'
                                    : 'Invoice amount must be greater than zero.',
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),

                    ElevatedButton(
                      onPressed: (!isFullyPaid || grandTotal <= 0 || _isProcessing)
                          ? null
                          : () => _processPayment(state),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: _isProcessing
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(strokeWidth: 3),
                            )
                          : Text(
                              widget.isCreditNoteRefund
                                  ? 'CONFIRM CREDIT NOTE REFUND'
                                  : 'CONFIRM INVOICE',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          );
            },
          ),
        );
      },
    );
  }
}
