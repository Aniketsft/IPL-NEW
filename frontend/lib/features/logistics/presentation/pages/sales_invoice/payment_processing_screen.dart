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
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_cart_cubit.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/credit_note_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/credit_note_pdf_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/credit_note_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/models/stock_status.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/models/transaction_config.dart';

import 'package:enterprise_auth_mobile/features/logistics/domain/services/si_sales_order_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/sales_invoice_pdf_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/document_sequence_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/cash_collection_pdf_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/open_invoice_model.dart';
import 'package:enterprise_auth_mobile/core/utils/currency_formatter.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:enterprise_auth_mobile/core/services/printer_service.dart';
import 'pdf_preview_screen.dart';

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
  final List<OpenInvoiceModel>? openInvoiceDocuments;
  final Map<String, double>? openInvoiceAllocations;
  final double? openInvoiceNetPayable;
  final Map<String, dynamic>? customCustomer;

  const PaymentProcessingScreen({
    super.key,
    this.isCreditNoteRefund = false,
    this.openInvoiceDocuments,
    this.openInvoiceAllocations,
    this.openInvoiceNetPayable,
    this.customCustomer,
  });

  bool get isOpenInvoiceMode =>
      openInvoiceDocuments != null && openInvoiceDocuments!.isNotEmpty;

  @override
  State<PaymentProcessingScreen> createState() =>
      _PaymentProcessingScreenState();
}

class _PaymentProcessingScreenState extends State<PaymentProcessingScreen> {
  String _selectedMethod =
      'CASH'; // 'CASH', 'CHEQUE', 'CREDIT', 'MYT MONEY', 'BLINK'
  String _selectedRefundMethod =
      CreditNoteRefundMethod.cash; // 'CASH' (MRCAS) or 'CREDIT' (MRCRE)
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _reasonController = TextEditingController();

  // Dynamic Fields
  final _bankCodeController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _chequeNumController = TextEditingController();
  final _chequeDateController = TextEditingController();
  final _qrRefController = TextEditingController();
  final _reasonFocusNode = FocusNode();
  String? _reasonErrorText;
  List<Map<String, String>> _availableReasons = [];
  String? _selectedReasonCode;
  String? _selectedReasonDesc;

  final currencyFormat = CurrencyFormatter.currencyFormat;
  bool _isProcessing = false;

  List<PaymentEntry> _payments = [];

  List<Map<String, dynamic>> _availableBanks = [];

  @override
  void initState() {
    super.initState();
    if (widget.isOpenInvoiceMode) {
      final target = (widget.openInvoiceNetPayable ?? 0.0).abs();
      if (target <= 0.001) {
        _selectedMethod = 'CN_OFFSET';
      }
    }
    if (widget.isCreditNoteRefund) {
      _loadCreditNoteReasons();
    }
    _loadBanks();
  }

  Future<void> _loadBanks() async {
    // Banks are assigned on the backend per payment method.
    // Users do not see or manage bank accounts on mobile terminals.
  }

  Future<void> _loadCreditNoteReasons() async {
    final reasons = await LocalDatabaseHelper.instance.getCreditNoteReasons();
    if (!mounted) return;
    setState(() {
      _availableReasons = reasons;
      if (reasons.isNotEmpty) {
        final blocState = context.read<SalesInvoiceBloc>().state;
        String? targetCode;
        if (blocState is SalesInvoiceLoaded && blocState.returnCondition != null) {
          final cond = ReturnCondition.fromId(blocState.returnCondition);
          targetCode = cond.reasonCode;
        }
        final currentText = targetCode ?? _reasonController.text.trim();
        final match = reasons.firstWhere(
          (r) => r['code']?.toString().toUpperCase() == currentText.toUpperCase(),
          orElse: () => reasons.firstWhere(
            (r) => r['code'] == _reasonController.text.trim(),
            orElse: () => reasons.first,
          ),
        );
        _selectedReasonCode = match['code'];
        _selectedReasonDesc = match['description'];
        _reasonController.text = match['code']!;
      }
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _reasonController.dispose();
    _bankCodeController.dispose();
    _bankNameController.dispose();
    _chequeNumController.dispose();
    _chequeDateController.dispose();
    _qrRefController.dispose();
    _reasonFocusNode.dispose();
    super.dispose();
  }

  double _getTotalPaid() {
    return double.parse(_payments.fold(0.0, (sum, item) => sum + item.amount).toStringAsFixed(2));
  }

  Future<void> _addPayment({required double grandTotal, Map<String, dynamic>? customer}) async {
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
    final remaining = double.parse((grandTotal - totalPaid).toStringAsFixed(2));

    if (remaining <= 0.001) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Amount is already fully covered.')),
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
    if (amount > remaining + 0.005) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Amount cannot exceed the remaining balance.'),
        ),
      );
      return;
    }

    String resolvedBankCode = '';
    String resolvedBankName = '';

    if (_selectedMethod == 'CHEQUE') {
      resolvedBankName = _bankNameController.text.trim();
    }

    if (_selectedMethod == 'CHEQUE') {
      if (_bankNameController.text.trim().isEmpty ||
          _chequeNumController.text.trim().isEmpty ||
          _chequeDateController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please fill all required cheque details (Bank Name, Cheque Number, Cheque Date).'),
          ),
        );
        return;
      }
    } else if (_selectedMethod == 'QR CODE' ||
        _selectedMethod == 'BLINK' ||
        _selectedMethod == 'JUICE' ||
        _selectedMethod == 'MYT MONEY') {
      if (_qrRefController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transaction reference is required for digital/QR payments.'),
          ),
        );
        return;
      }
    } else if (_selectedMethod == 'CREDIT') {
      if (customer != null) {
        final creditLimitStr = customer['creditLimit']?.toString() ?? '0';
        final outstandingStr = customer['outstandingBalance']?.toString() ?? '0';
        double creditLimit = double.tryParse(creditLimitStr) ?? 0.0;
        double outstanding = double.tryParse(outstandingStr) ?? 0.0;

        // Query unsynced offline invoices for this customer to prevent offline credit evasion
        double unsyncedInvoicesTotal = 0.0;
        try {
          final db = await LocalDatabaseHelper.instance.database;
          final unsyncedRes = await db.rawQuery(
            '''
            SELECT IFNULL(SUM(grandTotal), 0.0) as total
            FROM ${LocalDatabaseHelper.tableSiInvoices}
            WHERE customerCode = ? AND (isSynced = 0 OR isSynced IS NULL)
            ''',
            [customer['code']],
          );
          if (unsyncedRes.isNotEmpty) {
            unsyncedInvoicesTotal = (unsyncedRes.first['total'] as num?)?.toDouble() ?? 0.0;
          }
        } catch (_) {}

        // Calculate existing credit payments in the cart
        double cartCreditTotal = _payments
            .where((p) => p.method == 'CREDIT')
            .fold(0.0, (sum, p) => sum + p.amount);

        final totalExposure = outstanding + unsyncedInvoicesTotal + cartCreditTotal + amount;
        if (creditLimit > 0 && totalExposure > creditLimit) {
          final availableCredit = creditLimit - (outstanding + unsyncedInvoicesTotal + cartCreditTotal);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Credit limit exceeded! Limit: ${CurrencyFormatter.format(creditLimit)}, Available: ${CurrencyFormatter.format(availableCredit > 0 ? availableCredit : 0.0)}',
              ),
              backgroundColor: Colors.red[800],
            ),
          );
          return;
        }
      }
    }

    setState(() {
      _payments.add(
        PaymentEntry(
          id: const Uuid().v4(),
          method: _selectedMethod,
          amount: amount,
          bankCode: resolvedBankCode,
          bankName: resolvedBankName,
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
    Map<String, dynamic>? customer = cartState.customer;
    if (customer == null && cartState.originalDocumentId != null) {
      final db = await LocalDatabaseHelper.instance.database;
      final invRows = await db.query(
        LocalDatabaseHelper.tableSiInvoices,
        where: 'invoiceId = ?',
        whereArgs: [cartState.originalDocumentId!],
        limit: 1,
      );
      if (invRows.isNotEmpty) {
        customer = {
          'code': invRows.first['customerCode'] ?? '',
          'name': invRows.first['customerName'] ?? '',
        };
      }
    }

    if (customer == null || (cartState.cartItems.isEmpty && !widget.isOpenInvoiceMode)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot process: Customer or item information is missing.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final grandTotal = double.parse(cartState.grandTotal.toStringAsFixed(2));
    final isReturn = cartState.transactionType == 'RETURN' ||
        cartState.transactionType == 'CUSTOMER_RETURN' ||
        cartState.config.mode == AppTransactionMode.customerReturn ||
        cartState.config.category == TransactionTypeCategory.customerReturn;
    final isRefund = widget.isCreditNoteRefund ||
        isReturn ||
        cartState.config.isReturnOrCreditNote ||
        cartState.config.mode.isCreditNote;

    if (grandTotal <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isRefund
                ? 'Refund amount must be greater than zero.'
                : 'Invoice amount must be greater than zero.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!isRefund) {
      final totalPaid = _getTotalPaid();

      if (totalPaid < grandTotal - 0.005) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Full payment is required to process the invoice.'),
          ),
        );
        return;
      }
    }

    if (isRefund && _reasonController.text.trim().isEmpty) {
      setState(() {
        _reasonErrorText = isReturn
            ? 'Return reason is mandatory to proceed'
            : 'Credit note reason is mandatory to proceed';
      });
      _reasonFocusNode.requestFocus();
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('Reason Required'),
            ],
          ),
          content: Text(
            isReturn
                ? 'Customer Return Reason is mandatory in Sage X3.\n\nPlease input a reason to proceed with this return refund.'
                : 'Credit Note Reason is mandatory in Sage X3.\n\nPlease input a credit note reason to proceed with this refund.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _reasonFocusNode.requestFocus();
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final db = await LocalDatabaseHelper.instance.database;
      final batch = db.batch();
      // Read user assigned site from AuthBloc synchronously before async gaps
      final authState = context.read<AuthBloc>().state;
      String userSiteCode = (authState is Authenticated &&
              authState.siteCode != null &&
              authState.siteCode!.isNotEmpty &&
              authState.siteCode != 'ALL')
          ? authState.siteCode!
          : 'POD';

      if (userSiteCode == 'IPL') {
        userSiteCode = 'POD';
      }

      // Fetch audit details
      final secureStorage = SecureStorageService();
      final username = await secureStorage.getUsername() ?? 'Unknown User';
      final deviceId = DeviceInfoService.instance.deviceId.isNotEmpty
          ? DeviceInfoService.instance.deviceId
          : DeviceInfoService.instance.deviceName;
      final appVersion = '1.0.0';

      final selectedReps = await LocalDatabaseHelper.instance.getSelectedSalesReps(username: username);
      final salesRepString = selectedReps.isNotEmpty
          ? selectedReps.map((r) => (r['code'] ?? '').toString().trim()).where((c) => c.isNotEmpty).join(',')
          : username;

      // Handle Credit Note / Return Refund flow
      if (isRefund) {
        final refundMethod = _selectedRefundMethod;

        final isReturnTransaction = cartState.transactionType == 'RETURN' ||
            cartState.transactionType == 'CUSTOMER_RETURN' ||
            (cartState.config.isReturnOrCreditNote &&
                cartState.config.screenTitle.toLowerCase().contains('return'));
        final stockTransaction = isReturnTransaction ? 1 : 0;

        final condition = ReturnCondition.fromId(cartState.returnCondition);
        final stockStatus = cartState.returnStockStatus ?? condition.stockStatus;
        final resolvedReason = _reasonController.text.trim().isNotEmpty
            ? _reasonController.text.trim()
            : condition.reasonCode;

        // Resolve original sales site from X3 history header if this is a linked reversal/return
        String effectiveSiteCode = userSiteCode;
        if (cartState.originalDocumentId != null && cartState.originalDocumentId!.isNotEmpty) {
          try {
            final x3Header = await db.query(
              LocalDatabaseHelper.tableX3HistoryHeader,
              columns: ['salesSite'],
              where: 'invoiceNumber = ?',
              whereArgs: [cartState.originalDocumentId!],
              limit: 1,
            );
            if (x3Header.isNotEmpty && x3Header.first['salesSite'] != null) {
              final site = x3Header.first['salesSite']?.toString().trim();
              if (site != null && site.isNotEmpty) {
                effectiveSiteCode = site;
              }
            }
          } catch (_) {}
        }

        String deviceLorry = (DeviceInfoService.instance.assignedLocation ?? '').trim();
        if (deviceLorry.isEmpty) {
          try {
            final devLoc = await LocalDatabaseHelper.instance.getDeviceLocation(deviceId);
            deviceLorry = devLoc?['locationCode']?.toString().trim() ?? '';
          } catch (_) {}
        }

        final creditNote = await CreditNoteService().createStandaloneCreditNote(
          salesSite: effectiveSiteCode,
          customerCode: customer['code'],
          customerName: customer['name'],
          refundMethod: refundMethod,
          refundAmount: grandTotal,
          createdBy: username,
          deviceId: deviceId,
          reference: _referenceController.text.trim(),
          reason: resolvedReason,
          salesRep: salesRepString,
          originInvoiceId: cartState.originalDocumentId,
          stockTransaction: stockTransaction,
          stockStatus: stockStatus,
          items: cartState.cartItems.asMap().entries.map((entry) {
            final item = entry.value;
            final itemWarehouse = item.warehouse.isNotEmpty ? item.warehouse : effectiveSiteCode;
            final rawItemLoc = item.location.trim();
            final bool hasValidItemLoc = rawItemLoc.isNotEmpty &&
                rawItemLoc.toUpperCase() != 'LOC1' &&
                rawItemLoc.toUpperCase() != effectiveSiteCode.toUpperCase();
            final itemLocation = deviceLorry.isNotEmpty
                ? deviceLorry
                : (hasValidItemLoc
                    ? rawItemLoc
                    : (isReturnTransaction ? (effectiveSiteCode == 'IPL' ? 'IPLCH' : effectiveSiteCode) : null));
            return CreditNoteLineModel(
              creditNoteId: '',
              lineNo: (entry.key + 1) * 1000,
              quantity: item.quantity,
              standaloneSku: item.product.sku,
              standaloneName: item.product.name,
              standaloneSalesUnit: item.product.salesUnit,
              standalonePrice: item.basePrice,
              standaloneTaxRule: item.taxRule,
              standaloneLot: item.lotNumber,
              standaloneWarehouse: itemWarehouse,
              standaloneCce0: item.product.cce0,
              stockStatus: stockStatus,
              returnCondition: resolvedReason,
              location: itemLocation,
            );
          }).toList(),
        );

        if (!mounted) return;

        final cartItems = List<CartItem>.from(cartState.cartItems);
        final subtotal = cartState.subtotal;
        final totalDiscount = cartState.totalDiscount;
        final totalVat = cartState.totalVat;
        final reasonCode = _reasonController.text.trim();
        final reasonDisplay = _selectedReasonDesc != null && _selectedReasonDesc!.isNotEmpty
            ? '$_selectedReasonDesc ($reasonCode)'
            : reasonCode;

        context.read<SalesInvoiceBloc>().add(ClearCart());

        final bool isCreditRefund = refundMethod == CreditNoteRefundMethod.credit;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => InvoicePreviewScreen(
              invoiceId: creditNote.creditNoteId,
              customer: customer!,
              subtotal: subtotal,
              discountAmount: totalDiscount,
              vatAmount: totalVat,
              grandTotal: grandTotal,
              paymentMethod: isCreditRefund ? 'CREDIT ON ACCOUNT' : 'CASH REFUND',
              paymentStatus: isCreditRefund ? 'ON ACCOUNT' : 'REFUNDED',
              items: cartItems,
              isCreditNote: true,
              creditNoteReason: reasonDisplay,
              creditNoteModel: creditNote,
            ),
          ),
        );
        return;
      }

      // Pre-allocate invoice sequence number strictly for standard invoices (never for refunds/returns)
      final invoiceId = await DocumentSequenceService().generateDocumentNumber(
        docType: 'INV',
        salesSite: userSiteCode,
        lorryCode: DeviceInfoService.instance.assignedLocation,
        deviceId: deviceId,
      );

      // Determine main invoice status
      bool hasCredit = _payments.any((p) => p.method == 'CREDIT');
      String mainStatus = hasCredit ? 'CREDIT' : 'PAID';

        // Resolve the pricing rule: use the first matched pricelist code from any cart item.
        // Falls back to empty string if all items were manually priced.
        final resolvedPricingRule = cartState.cartItems
            .map((i) => i.pricingSource)
            .where((s) => s.isNotEmpty && s != 'MANUAL' && !s.contains('discount-only'))
            .firstOrNull ?? '';

      // Safe defensive schema verification for paymentTerm and line promotion fields before inserting
      try {
        await db.execute('ALTER TABLE ${LocalDatabaseHelper.tableSiInvoices} ADD COLUMN paymentTerm TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE ${LocalDatabaseHelper.tableSiInvoiceLines} ADD COLUMN mainItemSku TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE ${LocalDatabaseHelper.tableSiInvoiceLines} ADD COLUMN discountPercent REAL');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE ${LocalDatabaseHelper.tableSiInvoiceLines} ADD COLUMN discount3 REAL');
      } catch (_) {}

      // 1. Insert Invoice with Active Selected Sales Rep(s)
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
        'paymentTerm': (cartState.customer?['paymentTerm'] ?? '').toString().trim(),
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
          'mainItemSku': item.mainItemSku ?? '',
          'discountPercent': item.discountPercent,
          'discount3': item.discountAmount,
          'pricingSource': item.pricingSource,
          'discountAmountFlat': item.discountAmountFlat,
          'priceListCode': item.priceListCode,
          'reasonType': item.reasonType,
        });

        // Deduct from local stock to prevent overselling offline (strictly sellable stock A)
        batch.rawUpdate(
          '''
          UPDATE ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails} 
          SET totalQty = totalQty - ? 
          WHERE itemCode = ? AND lotNumber = ? AND warehouse = ? AND location = ? AND (stockStatus = 'A' OR stockStatus IS NULL OR stockStatus = '')
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
          'isSynced': 0,
          'x3PaymentId': null,
          'x3InvoiceDocumentId': null,
          'syncError': null,
          'createdAt': DateTime.now().toIso8601String(),
          'deviceId': deviceId,
          'userName': username,
          'salesSite': userSiteCode,
          'customerCode': cartState.customer?['code'],
        });
      }

      await batch.commit(noResult: true);

      if (cartState.originalDocumentId != null) {
        final service = SISalesOrderService();
        final orderId = int.tryParse(cartState.originalDocumentId!);
        if (orderId != null) {
          await service.markOrderAsConverted(orderId);
        }
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

  Future<void> _processOpenInvoicePayment() async {
    if (widget.openInvoiceDocuments == null || widget.openInvoiceDocuments!.isEmpty) return;

    final targetTotal = double.parse((widget.openInvoiceNetPayable ?? 0.0).abs().toStringAsFixed(2));
    final isZeroOffset = targetTotal <= 0.001;
    final totalPaid = _getTotalPaid();

    if (!isZeroOffset && totalPaid < targetTotal - 0.005) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Full payment is required to process the settlement.'),
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final authState = context.read<AuthBloc>().state;
      final userName = authState is Authenticated ? authState.username : 'OfflineUser';
      final siteCode = authState is Authenticated ? (authState.siteCode ?? '') : '';
      final deviceId = DeviceInfoService.instance.deviceInfo;
      final now = DateTime.now().toIso8601String();

      if (isZeroOffset) {
        for (final doc in widget.openInvoiceDocuments!) {
          final allocated = widget.openInvoiceAllocations?[doc.documentNo] ?? 0.0;
          if (allocated <= 0.001) continue;

          final paymentData = {
            'paymentId': const Uuid().v4(),
            'documentNo': doc.documentNo,
            'customerNo': doc.customerNo,
            'amount': allocated,
            'paymentMethod': 'CN_OFFSET',
            'bankCode': '',
            'bankName': '',
            'chequeNumber': '',
            'chequeDate': '',
            'qrTransactionRef': _referenceController.text.trim(),
            'siteCode': doc.site.isNotEmpty ? doc.site : siteCode,
            'company': doc.company,
            'createdAt': now,
            'userName': userName,
            'deviceId': deviceId,
            'isSynced': 0,
          };

          await LocalDatabaseHelper.instance.recordOpenInvoicePayment(paymentData);
        }
      } else {
        // Distribute payment entries across allocated documents
        final remainingDocNeeds = <Map<String, dynamic>>[];
        for (final doc in widget.openInvoiceDocuments!) {
          final allocated = widget.openInvoiceAllocations?[doc.documentNo] ?? 0.0;
          if (allocated > 0.001) {
            remainingDocNeeds.add({
              'doc': doc,
              'remaining': allocated,
            });
          }
        }

        int docIdx = 0;
        for (final payment in _payments) {
          double tenderRemaining = payment.amount;
          while (tenderRemaining > 0.001 && docIdx < remainingDocNeeds.length) {
            final curDocItem = remainingDocNeeds[docIdx];
            final doc = curDocItem['doc'] as OpenInvoiceModel;
            final double docNeed = curDocItem['remaining'] as double;

            final double applyAmount = tenderRemaining < docNeed ? tenderRemaining : docNeed;

            final paymentData = {
              'paymentId': const Uuid().v4(),
              'documentNo': doc.documentNo,
              'customerNo': doc.customerNo,
              'amount': double.parse(applyAmount.toStringAsFixed(2)),
              'paymentMethod': payment.method,
              'bankCode': payment.bankCode,
              'bankName': payment.bankName,
              'chequeNumber': payment.chequeNumber,
              'chequeDate': payment.chequeDate,
              'qrTransactionRef': payment.qrTransactionRef.isNotEmpty
                  ? payment.qrTransactionRef
                  : _referenceController.text.trim(),
              'siteCode': doc.site.isNotEmpty ? doc.site : siteCode,
              'company': doc.company,
              'createdAt': now,
              'userName': userName,
              'deviceId': deviceId,
              'isSynced': 0,
            };

            await LocalDatabaseHelper.instance.recordOpenInvoicePayment(paymentData);

            tenderRemaining -= applyAmount;
            curDocItem['remaining'] = docNeed - applyAmount;

            if ((curDocItem['remaining'] as double) <= 0.001) {
              docIdx++;
            }
          }
        }
      }

      if (!mounted) return;

      final custCode = widget.customCustomer?['code'] ??
          (widget.openInvoiceDocuments!.isNotEmpty
              ? widget.openInvoiceDocuments!.first.customerNo
              : '');
      final custName = widget.customCustomer?['name'] ??
          (widget.openInvoiceDocuments!.isNotEmpty
              ? widget.openInvoiceDocuments!.first.customerName
              : '');
      final docSiteCode = widget.openInvoiceDocuments!.isNotEmpty
          ? widget.openInvoiceDocuments!.first.site
          : siteCode;
      final docCompany = widget.openInvoiceDocuments!.isNotEmpty
          ? widget.openInvoiceDocuments!.first.company
          : 'INNODIS LTD';

      final settledDocsData = <Map<String, dynamic>>[];
      for (final doc in widget.openInvoiceDocuments!) {
        final allocated = widget.openInvoiceAllocations?[doc.documentNo] ?? 0.0;
        if (allocated > 0.001) {
          settledDocsData.add({
            'documentNo': doc.documentNo,
            'docType': doc.docType,
            'originalDue': doc.remainingAmtLCY,
            'settledAmount': allocated,
          });
        }
      }

      final tendersData = _payments.map((p) => {
        'method': p.method,
        'amount': p.amount,
        'bankCode': p.bankCode,
        'bankName': p.bankName,
        'chequeNumber': p.chequeNumber,
        'chequeDate': p.chequeDate,
        'reference': p.qrTransactionRef,
      }).toList();

      final receiptRef = 'REC-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.green, size: 28),
              SizedBox(width: 8),
              Text('Payment Recorded', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Successfully recorded settlement across ${settledDocsData.length} document(s).',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              if (custName.isNotEmpty || custCode.isNotEmpty) ...[
                Text(
                  'Customer: ${custName.isNotEmpty ? custName : custCode} ($custCode)',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 4),
              ],
              if (!isZeroOffset) ...[
                Text(
                  'Payment Methods: ${_payments.map((p) => p.method).toSet().join(", ")}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  'Total Paid: ${currencyFormat.format(totalPaid)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.green.shade700,
                  ),
                ),
              ] else ...[
                const Text(
                  'Offset: Balance cleared via Credit Notes.',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.cloud_upload_outlined, size: 16, color: Colors.orange),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Saved locally offline. Ready to print slip and will synchronize on next sync.',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        final pdfBytes = await CashCollectionPdfService().generateCollectionReceiptPdf(
                          pageFormat: PdfPageFormat.a4,
                          receiptRef: receiptRef,
                          customerCode: custCode,
                          customerName: custName,
                          dateTime: DateTime.now(),
                          salesRep: userName,
                          siteCode: docSiteCode,
                          company: docCompany,
                          settledDocuments: settledDocsData,
                          paymentTenders: tendersData,
                          totalCollected: isZeroOffset ? targetTotal : totalPaid,
                          isZeroOffset: isZeroOffset,
                        );
                        if (context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PdfPreviewScreen(
                                title: 'Receipt $receiptRef',
                                pdfBytes: pdfBytes,
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Preview error: $e'), backgroundColor: Colors.red),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                    label: const Text('Preview PDF', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        final pdfBytes = await CashCollectionPdfService().generateCollectionReceiptPdf(
                          pageFormat: PdfPageFormat.roll80,
                          receiptRef: receiptRef,
                          customerCode: custCode,
                          customerName: custName,
                          dateTime: DateTime.now(),
                          salesRep: userName,
                          siteCode: docSiteCode,
                          company: docCompany,
                          settledDocuments: settledDocsData,
                          paymentTenders: tendersData,
                          totalCollected: isZeroOffset ? targetTotal : totalPaid,
                          isZeroOffset: isZeroOffset,
                        );
                        await PrinterService.instance.printPdfViaBluetooth(
                          pdfBytes: pdfBytes,
                          documentName: 'Receipt_${receiptRef}.pdf',
                        );
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Print error: $e'), backgroundColor: Colors.red),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.print_rounded, size: 16),
                    label: const Text('Print (BT)', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: AppTheme.primaryAmber,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pop(context, true);
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Widget _buildRefundOptionTile({
    required String method,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final bool isSelected = _selectedRefundMethod == method;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color accent = method == CreditNoteRefundMethod.credit
        ? Colors.blue
        : AppTheme.primaryAmber;

    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedRefundMethod = method),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? accent.withOpacity(0.14)
                : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? accent
                  : (isDark ? Colors.white12 : Colors.black12),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 22,
                color: isSelected
                    ? accent
                    : (isDark ? Colors.white70 : Colors.black54),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? accent
                            : (isDark ? Colors.white : Colors.black87),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle_rounded, size: 18, color: accent),
            ],
          ),
        ),
      ),
    );
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
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sending to Sewoo Bluetooth printer...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

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

        final pdfBytes = await CreditNotePdfService().generateCreditNotePdf(
          pageFormat: PdfPageFormat.roll80,
          creditNote: creditNote,
          resolvedLines: cartState.cartItems.map((i) => {
            'sku': i.product.sku,
            'name': i.product.name,
            'quantity': i.quantity,
            'basePrice': i.basePrice,
          }).toList(),
        );

        await PrinterService.instance.printPdfViaBluetooth(
          pdfBytes: pdfBytes,
          documentName: 'CreditNote_${creditNote.creditNoteId}.pdf',
        );
      } else {
        final pdfService = SalesInvoicePdfService();
        final pdfBytes = await pdfService.generateInvoicePdf(
          pageFormat: PdfPageFormat.roll80,
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

        await PrinterService.instance.printPdfViaBluetooth(
          pdfBytes: pdfBytes,
          documentName: 'Invoice_${cartState.originalDocumentId ?? ""}.pdf',
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Document printed successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Print failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isOpenInvoiceMode) {
      final customer = widget.customCustomer ?? {
        'code': widget.openInvoiceDocuments!.first.customerNo,
        'name': widget.openInvoiceDocuments!.first.customerName,
      };
      final netPayable = widget.openInvoiceNetPayable ?? 0.0;
      final isRefund = netPayable < -0.001;
      final isZeroOffset = netPayable.abs() <= 0.001;
      final grandTotal = netPayable.abs();

      return _buildScaffold(
        context: context,
        title: isRefund ? 'Credit Refund' : 'Receipt (Cash Collection)',
        customer: customer,
        grandTotal: grandTotal,
        isChequeEnabled: true,
        isCreditEnabled: false,
        isZeroOffset: isZeroOffset,
        onConfirm: _processOpenInvoicePayment,
        confirmButtonLabel: isZeroOffset
            ? 'COMPLETE OFFSET'
            : (isRefund
                ? 'CONFIRM REFUND OF ${currencyFormat.format(grandTotal)}'
                : 'CONFIRM PAYMENT OF ${currencyFormat.format(grandTotal)}'),
      );
    }

    return BlocBuilder<SalesInvoiceBloc, SalesInvoiceState>(
      builder: (context, state) {
        if (state is! SalesInvoiceLoaded) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final cartState = state;
        final isPreview = cartState.transactionType.startsWith('PREVIEW');
        final isReturn = cartState.transactionType == 'RETURN' || cartState.transactionType == 'CUSTOMER_RETURN';
        final isRefund = widget.isCreditNoteRefund || isReturn || cartState.config.isReturnOrCreditNote;

        if (cartState.customer == null && !isRefund) {
          return const Scaffold(body: Center(child: Text('No Customer')));
        }

        bool isChequeEnabled = false;
        bool isCreditEnabled = false;

        if (isRefund) {
          isCreditEnabled = true;
        } else {
          final customer = cartState.customer!;
          final statusStr = customer['statusFlag']?.toString() ?? '1';
          isChequeEnabled = (statusStr == '1');

          if (statusStr != '3') {
            final creditLimitStr = customer['creditLimit']?.toString() ?? '0';
            final outstandingStr = customer['outstandingBalance']?.toString() ?? '0';
            double creditLimit = double.tryParse(creditLimitStr) ?? 0.0;
            double outstanding = double.tryParse(outstandingStr) ?? 0.0;
            double cartCreditTotal = _payments
                .where((p) => p.method == 'CREDIT')
                .fold(0.0, (sum, p) => sum + p.amount);

            if (creditLimit > 0 &&
                (creditLimit - outstanding - cartCreditTotal) > 0) {
              isCreditEnabled = true;
            }
          }
        }

        return _buildScaffold(
          context: context,
          title: isReturn
              ? 'Customer Return Refund'
              : (isRefund
                  ? 'Refund Processing'
                  : (isPreview ? 'Transaction Details' : 'Payment Processing')),
          customer: cartState.customer ?? {'code': '', 'name': ''},
          grandTotal: cartState.grandTotal,
          isChequeEnabled: isChequeEnabled,
          isCreditEnabled: isCreditEnabled,
          isZeroOffset: false,
          isPreview: isPreview,
          isReturn: isReturn,
          onPrint: isPreview ? () => _handleHistoricalPrint(cartState) : null,
          onConfirm: () => _processPayment(cartState),
          confirmButtonLabel: isReturn
              ? 'CONFIRM RETURN REFUND'
              : (isRefund
                  ? 'CONFIRM CREDIT NOTE REFUND'
                  : 'CONFIRM INVOICE'),
        );
      },
    );
  }

  Widget _buildScaffold({
    required BuildContext context,
    required String title,
    required Map<String, dynamic> customer,
    required double grandTotal,
    required bool isChequeEnabled,
    required bool isCreditEnabled,
    required bool isZeroOffset,
    required VoidCallback onConfirm,
    required String confirmButtonLabel,
    bool isPreview = false,
    bool isReturn = false,
    VoidCallback? onPrint,
  }) {
    final isCreditNote = widget.isCreditNoteRefund || isReturn;
    final roundedGrandTotal = double.parse(grandTotal.toStringAsFixed(2));
    final totalPaid = isCreditNote ? roundedGrandTotal : _getTotalPaid();
    final remaining = isCreditNote ? 0.0 : double.parse((roundedGrandTotal - totalPaid).toStringAsFixed(2));
    final isFullyPaid = isCreditNote || isZeroOffset || (roundedGrandTotal > 0 && remaining <= 0.001);
    final changeDue = remaining < -0.001 ? remaining.abs() : 0.0;

    // Set default amount input if empty and not fully paid
    if (!isCreditNote && !isFullyPaid && _amountController.text.isEmpty && !isZeroOffset && remaining > 0.001) {
      _amountController.text = remaining.toStringAsFixed(2);
    }

    final authState = context.read<AuthBloc>().state;
    final perms = authState is Authenticated ? authState.permissions : <String>[];
    final bool canTenderCash = perms.isEmpty ||
        perms.contains('logistics.sales.tender_cash.read') ||
        perms.contains('logistics.sales.tender_cash.create') ||
        perms.contains('logistics.salesman.read');
    final bool canTenderCheque = perms.isEmpty ||
        perms.contains('logistics.sales.tender_cheque.read') ||
        perms.contains('logistics.sales.tender_cheque.create') ||
        perms.contains('logistics.salesman.read');
    final bool canTenderCredit = perms.isEmpty ||
        perms.contains('logistics.sales.tender_credit.read') ||
        perms.contains('logistics.sales.tender_credit.create') ||
        perms.contains('logistics.salesman.read');
    final bool canTenderDigital = perms.isEmpty ||
        perms.contains('logistics.sales.tender_digital.read') ||
        perms.contains('logistics.sales.tender_digital.create') ||
        perms.contains('logistics.salesman.read');

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
        actions: [
          if (isPreview && onPrint != null)
            IconButton(
              icon: const Icon(Icons.print),
              tooltip: 'Print',
              onPressed: onPrint,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.isOpenInvoiceMode
                        ? 'RECEIPT / COLLECTION SUMMARY'
                        : (isReturn
                            ? 'CUSTOMER RETURN DETAILS'
                            : (widget.isCreditNoteRefund ? 'CREDIT NOTE DETAILS' : 'INVOICE DETAILS')),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (widget.isOpenInvoiceMode && widget.openInvoiceDocuments != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.withOpacity(0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.person_outline, size: 18, color: AppTheme.primaryAmber),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${customer['name']} (${customer['code']})',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${widget.openInvoiceDocuments!.length} Document(s) Allocated',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                              Text(
                                'Net: ${currencyFormat.format(grandTotal)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryAmber,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (widget.isOpenInvoiceMode && isZeroOffset) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.withOpacity(0.3)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.swap_horiz_rounded, color: Colors.green, size: 28),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Invoice and Credit Note amounts match exactly. Balance will be fully cleared with zero cash required.',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
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
                  if (widget.isCreditNoteRefund) ...[
                    Builder(
                      builder: (ctx) {
                        final blocState = ctx.read<SalesInvoiceBloc>().state;
                        final condId = blocState is SalesInvoiceLoaded ? blocState.returnCondition : null;
                        if (condId == null && !isReturn) return const SizedBox.shrink();
                        final cond = ReturnCondition.fromId(condId);
                        final isSellable = cond.stockStatus == 'A';
                        final isDark = Theme.of(ctx).brightness == Brightness.dark;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: cond.color.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: cond.color.withOpacity(0.4)),
                          ),
                          child: Row(
                            children: [
                              Icon(cond.icon, color: cond.color, size: 22),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'RETURN CONDITION: ${cond.label.toUpperCase()}',
                                          style: TextStyle(
                                            color: cond.color,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isSellable
                                                ? Colors.green.withOpacity(0.15)
                                                : Colors.amber.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            isSellable ? 'Stock A (Sellable)' : 'Stock Q (Quarantine)',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: isSellable ? Colors.green : Colors.amber.shade800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      cond.description,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark ? Colors.white60 : Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    DropdownButtonFormField<String>(
                      value: _selectedReasonCode,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Credit Note Reason *',
                        hintText: 'Select credit note reason',
                        errorText: _reasonErrorText,
                        prefixIcon: const Icon(Icons.rule_rounded, color: AppTheme.primaryAmber),
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.grey.withOpacity(0.05),
                      ),
                      items: _availableReasons.map((r) {
                        final code = r['code'] ?? '';
                        final desc = r['description'] ?? code;
                        return DropdownMenuItem<String>(
                          value: code,
                          child: Text(
                            '$desc ($code)',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedReasonCode = val;
                            final match = _availableReasons.firstWhere(
                              (r) => r['code'] == val,
                              orElse: () => {'code': val, 'description': val},
                            );
                            _selectedReasonDesc = match['description'];
                            _reasonController.text = val;
                            _reasonErrorText = null;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'REFUND METHOD *',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _buildRefundOptionTile(
                              method: CreditNoteRefundMethod.cash,
                              title: 'Cash Refund',
                              subtitle: 'Disburse cash (MRCAS)',
                              icon: Icons.payments_outlined,
                            ),
                            const SizedBox(width: 10),
                            _buildRefundOptionTile(
                              method: CreditNoteRefundMethod.credit,
                              title: 'Credit on Account',
                              subtitle: 'Apply to balance (MRCRE)',
                              icon: Icons.account_balance_wallet_outlined,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: (_selectedRefundMethod == CreditNoteRefundMethod.credit
                                    ? Colors.blue
                                    : AppTheme.primaryAmber)
                                .withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: (_selectedRefundMethod == CreditNoteRefundMethod.credit
                                      ? Colors.blue
                                      : AppTheme.primaryAmber)
                                  .withOpacity(0.35),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _selectedRefundMethod == CreditNoteRefundMethod.credit
                                    ? Icons.account_balance_wallet_outlined
                                    : Icons.payments_outlined,
                                size: 20,
                                color: _selectedRefundMethod == CreditNoteRefundMethod.credit
                                    ? Colors.blue
                                    : AppTheme.primaryAmber,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _selectedRefundMethod == CreditNoteRefundMethod.credit
                                      ? (isReturn
                                          ? 'Customer return refund of ${currencyFormat.format(grandTotal)} will be credited to customer account (MRCRE).'
                                          : 'Credit note of ${currencyFormat.format(grandTotal)} will be credited to customer account (MRCRE).')
                                      : (isReturn
                                          ? 'Customer return refund of ${currencyFormat.format(grandTotal)} will be disbursed in Cash (MRCAS).'
                                          : 'Credit note refund of ${currencyFormat.format(grandTotal)} will be disbursed in Cash (MRCAS).'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).textTheme.bodySmall?.color,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (!isFullyPaid && !isZeroOffset) ...[
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
                        _buildMethodButton(
                          'CASH',
                          Icons.payments_outlined,
                          'CASH',
                          isEnabled: canTenderCash,
                        ),
                        if (!widget.isCreditNoteRefund)
                          _buildMethodButton(
                            'CHEQUE',
                            Icons.receipt_long,
                            'CHEQUE',
                            isEnabled: isChequeEnabled && canTenderCheque,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (!widget.isCreditNoteRefund && !widget.isOpenInvoiceMode)
                          _buildMethodButton(
                            'CREDIT',
                            Icons.account_balance_wallet,
                            'CREDIT',
                            isEnabled: isCreditEnabled && canTenderCredit,
                          ),
                        if (!widget.isCreditNoteRefund)
                          _buildMethodButton(
                            'BLINK',
                            Icons.qr_code_2,
                            'BLINK',
                            isEnabled: canTenderDigital,
                          ),
                        if (!widget.isCreditNoteRefund)
                          _buildMethodButton(
                            'JUICE',
                            Icons.bolt_rounded,
                            'JUICE',
                            isEnabled: canTenderDigital,
                          ),
                        if (!widget.isCreditNoteRefund)
                          _buildMethodButton(
                            'MYT MONEY',
                            Icons.phone_android,
                            'MYT MONEY',
                            isEnabled: canTenderDigital,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: _amountController,
                      textAlign: TextAlign.right,
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
                          hintText: 'e.g. MCB, SBM, Absa',
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
                    if (_selectedMethod == 'QR CODE' ||
                        _selectedMethod == 'BLINK' ||
                        _selectedMethod == 'JUICE' ||
                        _selectedMethod == 'MYT MONEY') ...[
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
                            Icon(
                              _selectedMethod == 'MYT MONEY'
                                  ? Icons.phone_android
                                  : (_selectedMethod == 'JUICE'
                                      ? Icons.bolt_rounded
                                      : Icons.qr_code_2),
                              size: 64,
                              color: AppTheme.primaryAmber,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$_selectedMethod Payment',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _qrRefController,
                              keyboardType: TextInputType.text,
                              decoration: InputDecoration(
                                labelText: 'Transaction Reference *',
                                hintText: 'Enter receipt / approval code',
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
                      onPressed: () => _addPayment(grandTotal: grandTotal, customer: customer),
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
                        if (p.method == 'QR CODE' || p.method == 'BLINK' || p.method == 'JUICE' || p.method == 'MYT MONEY')
                          subtitle = 'Ref: ${p.qrTransactionRef}';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppTheme.primaryAmber
                                  .withOpacity(0.2),
                              child: Icon(
                                p.method == 'CASH'
                                    ? Icons.payments_outlined
                                    : p.method == 'CHEQUE'
                                    ? Icons.receipt_long
                                    : p.method == 'CREDIT'
                                    ? Icons.account_balance_wallet
                                    : p.method == 'MYT MONEY'
                                    ? Icons.phone_android
                                    : p.method == 'JUICE'
                                    ? Icons.bolt_rounded
                                    : Icons.qr_code_2,
                                color: AppTheme.primaryAmber,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              p.method,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: subtitle.isNotEmpty
                                ? Text(subtitle)
                                : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  currencyFormat.format(p.amount),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => _removePayment(p),
                                ),
                              ],
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
                    Expanded(
                      child: Text(
                        'GRAND TOTAL',
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodySmall?.color,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    Text(
                      currencyFormat.format(grandTotal),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
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
                        widget.isCreditNoteRefund
                            ? (_selectedRefundMethod == CreditNoteRefundMethod.credit
                                ? 'REFUND (ON ACCOUNT)'
                                : 'TOTAL REFUND (CASH)')
                            : 'TOTAL PAID',
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodySmall?.color,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    Text(
                      currencyFormat.format(isZeroOffset || widget.isCreditNoteRefund ? grandTotal : totalPaid),
                      style: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.right,
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
                    Expanded(
                      child: Text(
                        remaining < -0.001 ? 'CHANGE DUE' : 'REMAINING',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          color: remaining < -0.001 ? Colors.blue : ((isZeroOffset || widget.isCreditNoteRefund || isFullyPaid || remaining.abs() <= 0.001) ? Colors.green : Colors.red),
                        ),
                      ),
                    ),
                    Text(
                      currencyFormat.format(
                        (isZeroOffset || widget.isCreditNoteRefund || remaining.abs() <= 0.001) ? 0.0 : (remaining < -0.001 ? changeDue : remaining),
                      ),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: remaining < -0.001 ? Colors.blue : ((isZeroOffset || widget.isCreditNoteRefund || isFullyPaid || remaining.abs() <= 0.001) ? Colors.green : Colors.red),
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ],
                ),
                if (!widget.isOpenInvoiceMode && grandTotal <= 0)
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
                  onPressed: (!isFullyPaid || (!isZeroOffset && grandTotal <= 0) || _isProcessing)
                      ? null
                      : onConfirm,
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
                          confirmButtonLabel,
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
      ),
    );
  }
}
