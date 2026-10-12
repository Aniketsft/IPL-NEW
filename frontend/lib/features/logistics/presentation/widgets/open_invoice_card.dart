import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/models/open_invoice_model.dart';

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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isCN ? 'Available Credit:' : 'Remaining Balance:',
                    style: TextStyle(
                      fontSize: 13,
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
}
