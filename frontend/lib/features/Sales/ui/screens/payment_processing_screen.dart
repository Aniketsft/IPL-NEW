import 'package:flutter/material.dart';
import '../../../../core/widgets/industrial_module_layout.dart';
import 'invoice_preview_screen.dart';
import '../../domain/entities/customer.dart';
import '../../data/repositories/sales_repository.dart';

enum PaymentMethod { cheque, qrCode, cash }

class PaymentProcessingScreen extends StatefulWidget {
  final double totalAmount;
  final Customer customer;
  final List<Map<String, dynamic>> items;
  const PaymentProcessingScreen({super.key, required this.totalAmount, required this.customer, required this.items});

  @override
  State<PaymentProcessingScreen> createState() => _PaymentProcessingScreenState();
}

class _PaymentProcessingScreenState extends State<PaymentProcessingScreen> {
  PaymentMethod _selectedMethod = PaymentMethod.cheque;
  final TextEditingController _bankCodeController = TextEditingController(text: '004');
  final TextEditingController _bankNameController = TextEditingController(text: 'HSBC Corporate');
  late final TextEditingController _amountController;
  final TextEditingController _cashReceivedController = TextEditingController();
  final SalesRepository _repository = SalesRepository();
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(text: widget.totalAmount.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _bankCodeController.dispose();
    _bankNameController.dispose();
    _amountController.dispose();
    _cashReceivedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {



    return IndustrialModuleLayout(
      title: 'PAYMENT PROCESSING',
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSummaryCard(context),
                const SizedBox(height: 24),
                const Text(
                  'SELECT METHOD',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                _buildMethodSelector(context),
                const SizedBox(height: 24),
                _buildDetailsSection(context),
              ],
            ),
          ),
          _buildBottomAction(context),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'TOTAL AMOUNT',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'UNPAID',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Rs.${widget.totalAmount.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSummaryLabel(context, 'Invoice #', 'INV-8892'),
              _buildSummaryLabel(context, 'Date', 'Oct 24, 2023'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryLabel(BuildContext context, String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildMethodSelector(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _buildMethodCard(
            context,
            PaymentMethod.cheque,
            Icons.receipt_long,
            'CHEQUE',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMethodCard(
            context,
            PaymentMethod.qrCode,
            Icons.qr_code_2,
            'QR CODE',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMethodCard(
            context,
            PaymentMethod.cash,
            Icons.payments,
            'CASH',
          ),
        ),
      ],
    );
  }

  Widget _buildMethodCard(BuildContext context, PaymentMethod method, IconData icon, String label) {
    final theme = Theme.of(context);
    final isSelected = _selectedMethod == method;
    final primaryColor = theme.primaryColor;

    return GestureDetector(
      onTap: () => setState(() => _selectedMethod = method),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor.withValues(alpha: 0.1) : theme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? primaryColor : (theme.brightness == Brightness.dark ? Colors.white10 : Colors.black12),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? primaryColor : (theme.brightness == Brightness.dark ? Colors.white38 : Colors.black38),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isSelected ? primaryColor : (theme.brightness == Brightness.dark ? Colors.white54 : Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsSection(BuildContext context) {
    switch (_selectedMethod) {
      case PaymentMethod.cheque:
        return _buildChequeDetails(context);
      case PaymentMethod.qrCode:
        return _buildQrDetails(context);
      case PaymentMethod.cash:
        return _buildCashDetails(context);
    }
  }

  Widget _buildChequeDetails(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'CHEQUE DETAILS',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Bal: Rs.0.00',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: theme.primaryColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildInputCard(context, [
          _buildInputField(context, 'Bank Code', _bankCodeController, hint: 'e.g. 004'),
          const SizedBox(height: 12),
          _buildInputField(context, 'Bank Name', _bankNameController, hint: 'e.g. Chase Bank'),
          const SizedBox(height: 12),
          _buildInputField(context, 'Amount', _amountController, prefix: 'Rs.'),
        ]),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.add),
          label: const Text('ADD ANOTHER CHEQUE'),
          style: TextButton.styleFrom(foregroundColor: theme.primaryColor),
        ),
      ],
    );
  }

  Widget _buildQrDetails(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: Column(
        children: [
          const Text(
            'QR PAYMENT',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black12),
            ),
            child: const Icon(Icons.qr_code_2, size: 160, color: Colors.black),
          ),
          const SizedBox(height: 24),
          Text(
            'Scan the QR code to complete your payment securely.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCashDetails(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'CASH PAYMENT',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        _buildInputCard(context, [
          _buildInputField(context, 'Cash Amount Received', _cashReceivedController, prefix: 'Rs.', hint: '0.00'),
        ]),
      ],
    );
  }

  Widget _buildInputCard(BuildContext context, List<Widget> children) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildInputField(BuildContext context, String label, TextEditingController controller, {String? prefix, String? hint}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
          ),
          child: Row(
            children: [
              if (prefix != null) ...[
                Text(
                  prefix,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: hint,
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomAction(BuildContext context) {
    final theme = Theme.of(context);

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardColor,
          border: Border(
            top: BorderSide(color: theme.brightness == Brightness.dark ? Colors.white10 : Colors.black12),
          ),
        ),
        child: ElevatedButton.icon(
          onPressed: _isProcessing ? null : () async {
            setState(() => _isProcessing = true);
            try {
              await _repository.saveSalesTransaction(
                customer: widget.customer,
                items: widget.items,
                totalAmount: widget.totalAmount,
                paymentMethod: _selectedMethod.name,
              );
              
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Payment Processed & Saved Offline Successfully!')),
              );
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const InvoicePreviewScreen()),
              );
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error saving transaction: $e')),
              );
              setState(() => _isProcessing = false);
            }
          },
          icon: _isProcessing 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.check_circle),
          label: Text(_isProcessing ? 'PROCESSING...' : 'PROCESS PAYMENT'),
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
  }
}
