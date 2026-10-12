import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../../../../core/widgets/industrial_module_layout.dart';
import '../../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../../auth/presentation/bloc/auth_state.dart';
import '../../../data/local/local_database_helper.dart';
import '../../../data/models/open_invoice_model.dart';
import '../../../../../core/services/device_info_service.dart';

class OpenInvoicePaymentScreen extends StatefulWidget {
  final List<OpenInvoiceModel> selectedDocuments;
  final Map<String, double> allocations;
  final double netPayable;

  const OpenInvoicePaymentScreen({
    super.key,
    required this.selectedDocuments,
    required this.allocations,
    required this.netPayable,
  });

  @override
  State<OpenInvoicePaymentScreen> createState() => _OpenInvoicePaymentScreenState();
}

class _OpenInvoicePaymentScreenState extends State<OpenInvoicePaymentScreen> {
  String _selectedMethod = 'CASH'; // 'CASH', 'CHEQUE', 'BLINK', 'MYT MONEY', 'CN_OFFSET'
  final _bankCodeController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _chequeNumController = TextEditingController();
  final _chequeDateController = TextEditingController();
  final _qrRefController = TextEditingController();
  bool _isProcessing = false;

  final currencyFormat = NumberFormat.currency(locale: 'en_US', symbol: 'RS ', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    if (widget.netPayable.abs() <= 0.001) {
      _selectedMethod = 'CN_OFFSET';
    }
  }

  @override
  void dispose() {
    _bankCodeController.dispose();
    _bankNameController.dispose();
    _chequeNumController.dispose();
    _chequeDateController.dispose();
    _qrRefController.dispose();
    super.dispose();
  }

  Future<void> _processPayment() async {
    if (_isProcessing) return;

    if (_selectedMethod == 'CHEQUE') {
      if (_bankNameController.text.trim().isEmpty ||
          _chequeNumController.text.trim().isEmpty ||
          _chequeDateController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill all required cheque details.')),
        );
        return;
      }
    }

    if ((_selectedMethod == 'BLINK' || _selectedMethod == 'MYT MONEY') &&
        _qrRefController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transaction reference is required for digital payments.')),
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

      // Record payments in SQLite for each allocated document
      for (final doc in widget.selectedDocuments) {
        final allocated = widget.allocations[doc.documentNo] ?? 0.0;
        if (allocated <= 0.001) continue;

        final paymentData = {
          'paymentId': const Uuid().v4(),
          'documentNo': doc.documentNo,
          'customerNo': doc.customerNo,
          'amount': allocated,
          'paymentMethod': _selectedMethod,
          'bankCode': _bankCodeController.text.trim(),
          'bankName': _bankNameController.text.trim(),
          'chequeNumber': _chequeNumController.text.trim(),
          'chequeDate': _chequeDateController.text.trim(),
          'qrTransactionRef': _qrRefController.text.trim(),
          'siteCode': doc.site.isNotEmpty ? doc.site : siteCode,
          'company': doc.company,
          'createdAt': now,
          'userName': userName,
          'deviceId': deviceId,
          'isSynced': 0,
        };

        await LocalDatabaseHelper.instance.recordOpenInvoicePayment(paymentData);
      }

      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.green, size: 28),
              SizedBox(width: 8),
              Text('Payment Recorded'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Successfully allocated payment across ${widget.selectedDocuments.length} document(s).'),
              const SizedBox(height: 12),
              Text('Method: $_selectedMethod', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('Amount: ${currencyFormat.format(widget.netPayable.abs())}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              const Text(
                'Record saved to local offline database. Will synchronize automatically on next sync.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx); // Close dialog
                Navigator.pop(context, true); // Return success to OpenInvoicesScreen
              },
              child: const Text('Done'),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final double totalInvoices = widget.selectedDocuments
        .where((d) => d.isInvoice)
        .fold(0.0, (sum, d) => sum + (widget.allocations[d.documentNo] ?? 0.0));
    final double totalCN = widget.selectedDocuments
        .where((d) => d.isCreditNote)
        .fold(0.0, (sum, d) => sum + (widget.allocations[d.documentNo] ?? 0.0));

    final isRefund = widget.netPayable < -0.001;
    final isZeroOffset = widget.netPayable.abs() <= 0.001;

    return IndustrialModuleLayout(
      title: isRefund ? 'Credit Refund' : 'Invoice Payment',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Allocation Breakdown Card
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              color: isDark ? theme.cardColor : Colors.grey.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Allocation Summary', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    if (widget.selectedDocuments.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.person_outline, size: 18, color: theme.primaryColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${widget.selectedDocuments.first.customerName} (${widget.selectedDocuments.first.customerNo})',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const Divider(height: 20),
                    if (totalInvoices > 0)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total Invoices:'),
                          Text(currencyFormat.format(totalInvoices), style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    if (totalCN > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Credit Note Offset:'),
                          Text('-${currencyFormat.format(totalCN)}',
                              style: TextStyle(fontWeight: FontWeight.w600, color: Colors.amber.shade800)),
                        ],
                      ),
                    ],
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isRefund ? 'Net Refund Due:' : 'Net Payable:',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          currencyFormat.format(widget.netPayable.abs()),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isRefund ? Colors.amber.shade800 : theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Payment Method Selection (if not exact offset)
            if (!isZeroOffset) ...[
              const Text('Payment Method', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildMethodChip('CASH', Icons.payments_rounded),
                  _buildMethodChip('CHEQUE', Icons.account_balance_rounded),
                  _buildMethodChip('BLINK', Icons.qr_code_2_rounded),
                  _buildMethodChip('MYT MONEY', Icons.phone_android_rounded),
                ],
              ),
              const SizedBox(height: 16),

              // Dynamic fields for Cheque
              if (_selectedMethod == 'CHEQUE') ...[
                TextField(
                  controller: _bankNameController,
                  decoration: const InputDecoration(labelText: 'Bank Name *', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _chequeNumController,
                  decoration: const InputDecoration(labelText: 'Cheque Number *', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _chequeDateController,
                  decoration: InputDecoration(
                    labelText: 'Cheque Date (YYYY-MM-DD) *',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.calendar_today_rounded),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) {
                          _chequeDateController.text = DateFormat('yyyy-MM-dd').format(picked);
                        }
                      },
                    ),
                  ),
                ),
              ],

              // Dynamic fields for digital / QR
              if (_selectedMethod == 'BLINK' || _selectedMethod == 'MYT MONEY') ...[
                TextField(
                  controller: _qrRefController,
                  decoration: const InputDecoration(
                    labelText: 'Transaction Reference *',
                    border: OutlineInputBorder(),
                    hintText: 'Enter payment receipt / approval code',
                  ),
                ),
              ],
            ] else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
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
            ],

            const SizedBox(height: 32),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _processPayment,
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isProcessing
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        isZeroOffset
                            ? 'Complete Offset'
                            : (isRefund
                                ? 'Process Refund of ${currencyFormat.format(widget.netPayable.abs())}'
                                : 'Confirm Payment of ${currencyFormat.format(widget.netPayable.abs())}'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMethodChip(String method, IconData icon) {
    final isSelected = _selectedMethod == method;
    final theme = Theme.of(context);

    return ChoiceChip(
      selected: isSelected,
      onSelected: (val) {
        if (val) setState(() => _selectedMethod = method);
      },
      avatar: Icon(icon, size: 18, color: isSelected ? Colors.white : theme.textTheme.bodyMedium?.color),
      label: Text(method),
      selectedColor: theme.primaryColor,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : theme.textTheme.bodyMedium?.color,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }
}
