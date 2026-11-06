import 'package:flutter/material.dart';

/// Global Stock Status Parameter (Sage X3 STOCK.STA_0 mapping)
/// - A: Approved / Prime Sellable Stock (Strictly available for sales invoices)
/// - Q: Quarantine / Returned Goods (Customer returns awaiting quality check/inspection)
/// - R: Rejected / Issue in Stock (Damaged, expired, or defective goods)
enum StockStatus {
  approved('A', 'Approved / Sellable', 'Prime sellable inventory'),
  quarantine('Q', 'Returned (Quarantine)', 'Customer returns under inspection'),
  rejected('R', 'Issue in Stock', 'Damaged or defective inventory');

  final String code;
  final String label;
  final String description;

  const StockStatus(this.code, this.label, this.description);

  static StockStatus fromCode(String? code) {
    if (code == null || code.trim().isEmpty) return StockStatus.approved;
    final normalized = code.trim().toUpperCase();
    for (final status in StockStatus.values) {
      if (status.code == normalized) return status;
    }
    return StockStatus.approved;
  }

  bool get isSellable => this == StockStatus.approved;

  static const String codeApproved = 'A';
  static const String codeQuarantine = 'Q';
  static const String codeRejected = 'R';
}

/// Prompt condition chosen by the user when creating a Customer Return:
/// - Normal -> Restocked to Approved (A) and can be sold again
/// - Damaged -> Quarantined (Q) and cannot be sold
/// - Expired -> Quarantined (Q) and cannot be sold
enum ReturnCondition {
  normal('NORMAL', 'Normal', 'A', 'RET', 'Good condition / Back to sellable stock (A)', Icons.check_circle_outline, Colors.green),
  damaged('DAMAGED', 'Damaged', 'Q', 'DEF', 'Defective / Damaged (Quarantine Q)', Icons.broken_image_outlined, Colors.redAccent),
  expired('EXPIRED', 'Expired', 'Q', 'EXP', 'Expired date (Quarantine Q)', Icons.event_busy_outlined, Colors.orange);

  final String id;
  final String label;
  final String stockStatus; // 'A' or 'Q'
  final String reasonCode;  // 'RET', 'DEF', 'EXP'
  final String description;
  final IconData icon;
  final Color color;

  const ReturnCondition(
    this.id,
    this.label,
    this.stockStatus,
    this.reasonCode,
    this.description,
    this.icon,
    this.color,
  );

  static ReturnCondition fromId(String? id) {
    if (id == null) return ReturnCondition.normal;
    final normalized = id.trim().toUpperCase();
    for (final c in ReturnCondition.values) {
      if (c.id == normalized || c.name.toUpperCase() == normalized) return c;
    }
    return ReturnCondition.normal;
  }
}

/// Bottom sheet dialog prompting the user to select the Return Condition
Future<ReturnCondition?> showReturnConditionDialog(BuildContext context) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;

  return showModalBottomSheet<ReturnCondition>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      return Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Icon(Icons.assignment_return_rounded, color: theme.primaryColor, size: 24),
                const SizedBox(width: 10),
                const Text(
                  'Select Return Condition',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Specify return condition for inventory replenishment:',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
            const SizedBox(height: 18),
            ...ReturnCondition.values.map((cond) {
              final isSellable = cond.stockStatus == 'A';
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Material(
                  color: isDark ? const Color(0xFF1E222A) : Colors.white,
                  elevation: isDark ? 0 : 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.pop(ctx, cond),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: cond.color.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(cond.icon, color: cond.color, size: 26),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      cond.label,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isSellable
                                            ? Colors.green.withOpacity(0.15)
                                            : Colors.amber.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(6),
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
                                const SizedBox(height: 4),
                                Text(
                                  cond.description,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? Colors.white54 : Colors.black45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: isDark ? Colors.white30 : Colors.black26,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      );
    },
  );
}
