import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:enterprise_auth_mobile/core/utils/currency_formatter.dart';
import '../../data/models/open_invoice_model.dart';
import '../../data/local/local_database_helper.dart';

class OpenInvoiceCard extends StatelessWidget {
  final OpenInvoiceModel invoice;
  final bool isSelected;
  final double selectedAmount;
  final double? maxAllowedAllocation;
  final bool isSelectable;
  final ValueChanged<bool>? onToggleSelect;
  final ValueChanged<double>? onAmountChanged;

  const OpenInvoiceCard({
    super.key,
    required this.invoice,
    this.isSelected = false,
    this.selectedAmount = 0.0,
    this.maxAllowedAllocation,
    this.isSelectable = true,
    this.onToggleSelect,
    this.onAmountChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currencyFormat = CurrencyFormatter.currencyFormat;

    final absRemaining = invoice.remainingAmtLCY.abs();

    DateTime? parsedDueDate;
    try {
      parsedDueDate = DateTime.tryParse(invoice.dueDate);
    } catch (_) {}

    final bool isOverdue = parsedDueDate != null &&
        parsedDueDate.isBefore(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day));

    String formattedDueDate = invoice.dueDate.split('T').first;
    if (parsedDueDate != null) {
      try {
        formattedDueDate = DateFormat('dd MMM yyyy').format(parsedDueDate);
      } catch (_) {}
    }

    const Color iconColor = Colors.green;
    const IconData iconData = Icons.receipt_long_rounded;

    final bool isFullyPaid = isSelected && (selectedAmount >= (absRemaining - 0.01));

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected
              ? theme.primaryColor
              : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08)),
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      color: isSelected
          ? (isDark ? theme.primaryColor.withValues(alpha: 0.12) : theme.primaryColor.withValues(alpha: 0.04))
          : theme.cardColor,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (isSelectable && onToggleSelect != null) {
            onToggleSelect!(!isSelected);
          }
        },
        onLongPress: () {
          if (isSelectable && onToggleSelect != null) {
            HapticFeedback.selectionClick();
            onToggleSelect!(!isSelected);
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Icon + Document No (Full width) + Badges + Selection indicator
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: iconColor.withValues(alpha: 0.12),
                    child: Icon(iconData, color: iconColor, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Text(
                          invoice.documentNo,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        if (invoice.allocatedAmount > 0.001)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                            ),
                            child: const Text(
                              'PARTIAL',
                              style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        if (isOverdue)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                            ),
                            child: const Text(
                              'OVERDUE',
                              style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (isSelectable && isSelected) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.check_circle_rounded,
                      color: theme.primaryColor,
                      size: 20,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),

              // Row 2: Customer Name
              Text(
                invoice.customerName.isNotEmpty ? invoice.customerName : 'Customer ${invoice.customerNo}',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),

              // Row 3: Metadata (Due, Site, Trail) on left + Balance Amount on right
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 3,
                      children: [
                        Text(
                          'Due: $formattedDueDate',
                          style: TextStyle(
                            fontSize: 11,
                            color: isOverdue ? Colors.red : Colors.grey,
                            fontWeight: isOverdue ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        if (invoice.site.isNotEmpty)
                          Text(
                            '• Site: ${invoice.site}',
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        if (invoice.allocatedAmount > 0.001)
                          InkWell(
                            onTap: () => _showPaymentHistory(context, invoice.documentNo),
                            child: Text(
                              '• Trail (${CurrencyFormatter.format(invoice.allocatedAmount)})',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.primaryColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        CurrencyFormatter.format(absRemaining),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: isSelected ? theme.primaryColor : (isDark ? Colors.white : Colors.black87),
                        ),
                        textAlign: TextAlign.right,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        invoice.allocatedAmount > 0.001 ? 'Rem. Due' : 'Balance',
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),

              // Row 4: Allocation Chip if selected
              if (isSelected && selectedAmount > 0.001) ...[
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: onAmountChanged != null
                      ? () async {
                          final maxVal = maxAllowedAllocation ?? absRemaining;
                          final custom = await _showAmountDialog(context, maxVal, selectedAmount);
                          if (custom != null && custom > 0) {
                            onAmountChanged!(custom);
                          }
                        }
                      : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (isFullyPaid ? Colors.green : Colors.amber).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: (isFullyPaid ? Colors.green : Colors.amber).withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isFullyPaid ? Icons.check_circle_rounded : Icons.pie_chart_rounded,
                          size: 13,
                          color: isFullyPaid ? Colors.green : Colors.amber.shade800,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isFullyPaid
                              ? 'Paid: ${CurrencyFormatter.format(selectedAmount)} (Full)'
                              : 'Allocated: ${CurrencyFormatter.format(selectedAmount)} (Tap to edit)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isFullyPaid ? Colors.green : Colors.amber.shade900,
                          ),
                        ),
                      ],
                    ),
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
        title: Text('Allocation for ${invoice.documentNo}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Remaining Due: ${CurrencyFormatter.format(invoice.remainingAmtLCY.abs())}',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Allocated Amount',
                helperText: 'Max Available: ${CurrencyFormatter.format(maxAmount)}',
                prefixText: '${CurrencyFormatter.currencySymbol} ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(controller.text.trim()) ?? 0.0;
              if (val > 0 && val <= maxAmount + 0.01) {
                Navigator.pop(ctx, double.parse(val.toStringAsFixed(2)));
              } else if (val > maxAmount + 0.01) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Amount cannot exceed ${CurrencyFormatter.format(maxAmount)}.'),
                  ),
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
    final currencyFormat = CurrencyFormatter.currencyFormat;

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
                              color: theme.primaryColor.withValues(alpha: 0.12),
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
                                    ? Colors.green.withValues(alpha: 0.12)
                                    : (method == 'CHEQUE'
                                        ? Colors.blue.withValues(alpha: 0.12)
                                        : Colors.purple.withValues(alpha: 0.12)),
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
                                  Expanded(
                                    child: Text(
                                      method,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ),
                                  Text(
                                    currencyFormat.format(amount),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Colors.green.shade700,
                                    ),
                                    textAlign: TextAlign.right,
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
