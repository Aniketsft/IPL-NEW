import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/models/open_invoice_model.dart';
import '../../data/local/local_database_helper.dart';

class OpenInvoiceCard extends StatelessWidget {
  final OpenInvoiceModel invoice;
  final bool isSelected;
  final double selectedAmount;
  final ValueChanged<bool> onToggleSelect;
  final ValueChanged<double> onAmountChanged;

  const OpenInvoiceCard({
    super.key,
    required this.invoice,
    required this.isSelected,
    required this.selectedAmount,
    required this.onToggleSelect,
    required this.onAmountChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currencyFormat = NumberFormat.currency(locale: 'en_US', symbol: 'RS ', decimalDigits: 2);

    final isCN = invoice.isCreditNote;
    final absRemaining = invoice.remainingAmtLCY.abs();

    DateTime? parsedDueDate;
    try {
      parsedDueDate = DateTime.tryParse(invoice.dueDate);
    } catch (_) {}

    final bool isOverdue = parsedDueDate != null &&
        parsedDueDate.isBefore(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day));

    final badgeColor = isCN ? Colors.amber.shade700 : Colors.teal.shade600;
    final borderColor = isSelected
        ? theme.primaryColor
        : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.1));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected
            ? (isDark ? theme.primaryColor.withValues(alpha: 0.12) : theme.primaryColor.withValues(alpha: 0.04))
            : theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: isSelected ? 1.5 : 1.0),
        boxShadow: isDark || isSelected
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: InkWell(
        onTap: () => onToggleSelect(!isSelected),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row: Type Badge, Document No, Due Date Badge, Checkbox
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      isCN ? 'CN' : 'INV',
                      style: TextStyle(
                        color: badgeColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      invoice.documentNo,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (invoice.allocatedAmount > 0.001)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                      ),
                      child: const Text(
                        'PARTIAL',
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  if (isOverdue)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'OVERDUE',
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  Checkbox(
                    value: isSelected,
                    onChanged: (val) => onToggleSelect(val ?? false),
                    activeColor: theme.primaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Customer Info: Name & Code
              Text(
                invoice.customerName.isNotEmpty ? invoice.customerName : 'Customer ${invoice.customerNo}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    'Code: ${invoice.customerNo}',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                  if (invoice.site.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Text(
                      'Site: ${invoice.site}',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    'Due: ${invoice.dueDate.split('T').first}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isOverdue ? FontWeight.bold : FontWeight.normal,
                      color: isOverdue ? Colors.red : theme.textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
              const Divider(height: 16),

              // Amount Row
              if (invoice.allocatedAmount > 0.001) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Original Due:',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textTheme.bodySmall?.color,
                      ),
                    ),
                    Text(
                      currencyFormat.format(absRemaining + invoice.allocatedAmount),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.textTheme.bodySmall?.color,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle_rounded, size: 13, color: Colors.green.shade600),
                        const SizedBox(width: 4),
                        Text(
                          'Already Collected:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      currencyFormat.format(invoice.allocatedAmount),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isCN
                        ? 'Available Credit:'
                        : (invoice.allocatedAmount > 0.001
                            ? 'Remaining Due:'
                            : 'Remaining Balance:'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: invoice.allocatedAmount > 0.001 ? FontWeight.bold : FontWeight.normal,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                  Text(
                    isCN
                        ? '-${currencyFormat.format(absRemaining)}'
                        : currencyFormat.format(absRemaining),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isCN ? Colors.amber.shade800 : theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              if (invoice.allocatedAmount > 0.001) ...[
                const SizedBox(height: 6),
                InkWell(
                  onTap: () => _showPaymentHistory(context, invoice.documentNo),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.primaryColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: theme.primaryColor.withOpacity(0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.receipt_rounded, size: 14, color: theme.primaryColor),
                        const SizedBox(width: 6),
                        Text(
                          'View Collection Trail',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: theme.primaryColor,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right_rounded, size: 14, color: theme.primaryColor),
                      ],
                    ),
                  ),
                ),
              ],

              // Interactive Allocation Controls when selected
              if (isSelected) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Allocated: ${currencyFormat.format(selectedAmount)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => onAmountChanged(absRemaining),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Full', style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 6),
                      TextButton(
                        onPressed: () async {
                          final custom = await _showAmountDialog(context, absRemaining, selectedAmount);
                          if (custom != null && custom > 0) {
                            onAmountChanged(custom);
                          }
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Custom', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<double?> _showAmountDialog(BuildContext context, double maxAmount, double currentAmount) async {
    final controller = TextEditingController(text: currentAmount.toStringAsFixed(2));
    return showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Enter Amount for ${invoice.documentNo}'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Allocation Amount',
            helperText: 'Maximum: ${maxAmount.toStringAsFixed(2)}',
            prefixText: 'RS ',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(controller.text.trim()) ?? 0.0;
              if (val > 0 && val <= maxAmount) {
                Navigator.pop(ctx, double.parse(val.toStringAsFixed(2)));
              } else if (val > maxAmount) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Amount cannot exceed remaining balance.')),
                );
              }
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _showPaymentHistory(BuildContext context, String documentNo) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currencyFormat = NumberFormat.currency(locale: 'en_US', symbol: 'RS ', decimalDigits: 2);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: LocalDatabaseHelper.instance.getOpenInvoicePaymentsForDocument(documentNo),
              builder: (ctx, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 180,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final payments = snapshot.data ?? [];
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.black12,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: theme.primaryColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.receipt_long_rounded, color: theme.primaryColor, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Collection History',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                                Text(
                                  'Document: $documentNo',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.textTheme.bodySmall?.color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 20),
                    if (payments.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Center(
                          child: Text(
                            'No payment records found on this device for this document.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.45,
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: payments.length,
                          separatorBuilder: (_, __) => const Divider(height: 12),
                          itemBuilder: (ctx, i) {
                            final p = payments[i];
                            final amount = (p['amount'] as num?)?.toDouble() ?? 0.0;
                            final method = (p['paymentMethod'] ?? 'CASH').toString().toUpperCase();
                            final createdAt = p['createdAt']?.toString() ?? '';
                            final userName = p['userName']?.toString() ?? '';
                            final isSynced = (p['isSynced'] ?? 0) == 1;
                            final chequeNo = p['chequeNumber']?.toString() ?? '';
                            final qrRef = p['qrTransactionRef']?.toString() ?? '';

                            String dateStr = createdAt;
                            try {
                              final dt = DateTime.parse(createdAt);
                              dateStr = DateFormat('dd MMM yyyy, HH:mm').format(dt);
                            } catch (_) {}

                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: method == 'CASH'
                                    ? Colors.green.withOpacity(0.12)
                                    : (method == 'CHEQUE'
                                        ? Colors.blue.withOpacity(0.12)
                                        : Colors.purple.withOpacity(0.12)),
                                child: Icon(
                                  method == 'CASH'
                                      ? Icons.payments_rounded
                                      : (method == 'CHEQUE'
                                          ? Icons.account_balance_rounded
                                          : Icons.qr_code_rounded),
                                  color: method == 'CASH'
                                      ? Colors.green
                                      : (method == 'CHEQUE' ? Colors.blue : Colors.purple),
                                  size: 18,
                                ),
                              ),
                              title: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    method,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  Text(
                                    currencyFormat.format(amount),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (chequeNo.isNotEmpty)
                                    Text('Cheque #: $chequeNo', style: const TextStyle(fontSize: 11)),
                                  if (qrRef.isNotEmpty)
                                    Text('Ref: $qrRef', style: const TextStyle(fontSize: 11)),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Text(dateStr, style: TextStyle(fontSize: 11, color: theme.textTheme.bodySmall?.color)),
                                      if (userName.isNotEmpty) ...[
                                        const Text(' • ', style: TextStyle(fontSize: 11)),
                                        Text(userName, style: TextStyle(fontSize: 11, color: theme.textTheme.bodySmall?.color)),
                                      ],
                                      const Spacer(),
                                      Icon(
                                        isSynced ? Icons.cloud_done_rounded : Icons.cloud_upload_outlined,
                                        size: 14,
                                        color: isSynced ? Colors.green : Colors.orange,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        isSynced ? 'Synced' : 'Pending',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: isSynced ? Colors.green : Colors.orange,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
