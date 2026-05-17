import 'package:flutter/material.dart';

// Components now rely on Theme.of(context) for dynamic styling

class ScanItemCard extends StatelessWidget {
  final int lineNumber;
  final Map<String, dynamic> scan;
  final VoidCallback onDelete;

  const ScanItemCard({
    super.key,
    required this.lineNumber,
    required this.scan,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    final barcode = scan['barcode'] as String;
    final timestamp = scan['timestamp'] as String;
    final weight = (scan['weight'] as num).toDouble();
    final status = scan['status'] ?? 'A'; // Default to 'A' if not present
    final productName = scan['productName'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? const Color(0xFF2C2C2E) : Colors.black.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          // Line Number Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C2C2E) : Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '#$lineNumber',
              style: TextStyle(
                color: isDark ? Colors.grey : Colors.grey[600],
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Barcode, Product Name and Timestamp
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  barcode,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                ),
                if (productName != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    productName,
                    style: TextStyle(
                      color: orange,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  timestamp.length > 16 
                      ? timestamp.substring(11, 16) 
                      : timestamp,
                  style: TextStyle(
                    color: isDark ? Colors.grey : Colors.grey[600],
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          // Weight and Status Badge
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${weight.toStringAsFixed(3)} KG',
                style: TextStyle(
                  color: orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              _buildStatusBadge(status),
            ],
          ),
          const SizedBox(width: 4),
          // Delete Action
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20),
            onPressed: onDelete,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    String label;
    
    switch (status) {
      case 'Q':
        color = Colors.blue;
        label = 'QC';
        break;
      case 'R':
        color = Colors.red;
        label = 'REJECT';
        break;
      case 'A':
      default:
        color = Colors.green;
        label = 'APP';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
