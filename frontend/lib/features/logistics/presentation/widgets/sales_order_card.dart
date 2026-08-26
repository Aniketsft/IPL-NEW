import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../pages/sales_order_detail_screen.dart';
import '../../domain/entities/sales_order.dart';

class SalesOrderCard extends StatelessWidget {
  final SalesOrder order;
  final VoidCallback? onRefresh;
  final bool isDeliveryMode;
  final List<String> permissions;
  final bool hasBulkAvailable;
  final bool hasFppAvailable;

  const SalesOrderCard({
    super.key,
    required this.order,
    required this.permissions,
    this.onRefresh,
    this.isDeliveryMode = false,
    this.hasBulkAvailable = false,
    this.hasFppAvailable = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.1)),
        boxShadow: isDark ? null : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: (!isDeliveryMode && 
                !permissions.contains('manufacturing.all.update') && 
                permissions.contains('manufacturing.bulk_allocate.read') && 
                !(hasBulkAvailable || hasFppAvailable)) 
            ? null 
            : () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SalesOrderDetailScreen(
                order: order,
                isDeliveryMode: isDeliveryMode,
                permissions: permissions,
              ),
            ),
          );
          if (result == true && onRefresh != null) {
            onRefresh!();
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            order.orderNumber,
                            style: TextStyle(
                              color: orange,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              letterSpacing: 1.1,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (order.isRolledOverActive) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.deepPurpleAccent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.next_plan_outlined, size: 10, color: isDark ? Colors.deepPurple[300] : Colors.deepPurple[700]),
                                const SizedBox(width: 4),
                                Text(
                                  'Rolled Over',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.deepPurple[300] : Colors.deepPurple[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else if (hasBulkAvailable) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blueAccent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.inventory_2_outlined, size: 10, color: isDark ? Colors.blue[300] : Colors.blue[700]),
                                const SizedBox(width: 4),
                                Text(
                                  'Bulk',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.blue[300] : Colors.blue[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        /*
                        if (hasFppAvailable) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.indigoAccent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.indigoAccent.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.category_outlined, size: 10, color: isDark ? Colors.indigo[300] : Colors.indigo[700]),
                                const SizedBox(width: 4),
                                Text(
                                  'FPP',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.indigo[300] : Colors.indigo[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        */
                      ],
                    ),
                  ),
                    if (isDeliveryMode && order.isProcessed)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.teal.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.teal.withValues(alpha: 0.5),
                          width: 1,
                        ),
                      ),
                      child: const Text(
                        'PROCESSED',
                        style: TextStyle(
                          color: Colors.teal,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    )
                  else if (isDeliveryMode && order.isPreparedForShipment)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.green.withValues(alpha: 0.5),
                          width: 1,
                        ),
                      ),
                      child: const Text(
                        'PREPARED',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    )
                  else if (!isDeliveryMode)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: order.isClosed
                            ? Colors.grey.withValues(alpha: 0.2)
                            : orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: order.isClosed
                              ? Colors.grey
                              : orange.withValues(alpha: 0.5),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        order.isClosed ? 'CLOSED' : 'OPEN',
                        style: TextStyle(
                          color: order.isClosed 
                              ? (isDark ? Colors.grey : Colors.grey[700]) 
                              : orange,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                order.customerName.trim().isNotEmpty
                  ? '${order.customerCode} - ${order.customerName}'
                  : order.customerCode,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              if (order.soDate != null) ...[
                _buildInfoRow(
                  Icons.history_outlined,
                  'SO Date',
                  DateFormat('dd.MM.yy').format(order.soDate!),
                  isDark,
                ),
                const SizedBox(height: 8),
              ],
              _buildInfoRow(
                Icons.description_outlined,
                'PO',
                order.purchaseOrderNumber ?? 'N/A',
                isDark,
              ),
              const SizedBox(height: 8),
              _buildInfoRow(
                Icons.calendar_month_outlined,
                'Del. Date',
                order.deliveryDate,
                isDark,
              ),
              const SizedBox(height: 12),
              _buildInfoRow(
                Icons.person_outline,
                'Salesman',
                order.salesManCode2.isNotEmpty 
                  ? (order.salesmanName != null && order.salesmanName!.isNotEmpty
                      ? '${order.salesManCode2} - ${order.salesmanName}'
                      : order.salesManCode2)
                  : (order.salesmanName ?? 'N/A'),
                isDark,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, bool isDark) {
    return Row(
      children: [
        Icon(icon, size: 16, color: isDark ? Colors.white38 : Colors.black38),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            color: isDark ? Colors.white38 : Colors.black45, 
            fontSize: 13,
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black87,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
