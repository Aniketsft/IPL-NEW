import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/sales_order.dart';

class SalesOrderCard extends StatelessWidget {
  final SalesOrder order;

  const SalesOrderCard({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121212), // Dark card color
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                order.orderNumber,
                style: const TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  letterSpacing: 1.1,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: order.isClosed
                      ? Colors.grey.withOpacity(0.2)
                      : Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: order.isClosed ? Colors.grey : Colors.orange,
                    width: 1,
                  ),
                ),
                child: Text(
                  order.isClosed ? 'CLOSED' : 'OPEN',
                  style: TextStyle(
                    color: order.isClosed ? Colors.grey : Colors.orange,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '${order.customerCode} - ${order.customerName}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 12),
          if (order.soDate != null) ...[
            _buildInfoRow(
              Icons.history_outlined,
              'SO Date',
              DateFormat('dd/MM/yyyy').format(order.soDate!),
            ),
            const SizedBox(height: 8),
          ],
          _buildInfoRow(
            Icons.description_outlined,
            'PO',
            order.purchaseOrderNumber ?? 'N/A',
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            Icons.calendar_month_outlined,
            'Del. Date',
            DateFormat('dd/MM/yyyy').format(order.date),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildInfoRow(
                  Icons.person_outline,
                  'SM1',
                  order.salesManCode1,
                ),
              ),
              Expanded(
                child: _buildInfoRow(
                  Icons.person_outline,
                  'SM2',
                  order.salesManCode2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.white38),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(color: Colors.white38, fontSize: 13),
        ),
        Flexible(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white70,
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
