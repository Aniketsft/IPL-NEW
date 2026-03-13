import 'package:flutter/material.dart';
import '../../domain/entities/sales_order_detail.dart';

class ProductionTrackingSoBreakdownScreen extends StatelessWidget {
  final String itemCode;
  final String description;
  final List<SalesOrderDetail> soItems;

  const ProductionTrackingSoBreakdownScreen({
    super.key,
    required this.itemCode,
    required this.description,
    required this.soItems,
  });

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF9800);
    const dark800 = Color(0xFF1E1E1E);
    const dark900 = Color(0xFF0D0D0D);

    final totalOrdered =
        soItems.fold<double>(0, (s, i) => s + i.quantity);
    final totalManufactured =
        soItems.fold<double>(0, (s, i) => s + i.manufacturedQuantity);
    final aggProgress = totalOrdered > 0
        ? (totalManufactured / totalOrdered).clamp(0.0, 1.0)
        : (totalManufactured > 0 ? 1.0 : 0.0);

    return Scaffold(
      backgroundColor: dark900,
      appBar: AppBar(
        title: Text(
          itemCode,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // ── Aggregate summary card ──────────────────────────────────────
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: dark800,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: orange.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: aggProgress,
                    backgroundColor: Colors.white10,
                    valueColor: const AlwaysStoppedAnimation<Color>(orange),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _statChip(
                        label: 'Total Ordered',
                        value: totalOrdered.toStringAsFixed(0),
                        color: Colors.white70),
                    _statChip(
                        label: 'Total Produced',
                        value: totalManufactured.toStringAsFixed(0),
                        color: orange),
                    _statChip(
                        label: 'Overall',
                        value: '${(aggProgress * 100).toStringAsFixed(1)}%',
                        color: aggProgress >= 1.0
                            ? Colors.greenAccent
                            : Colors.white70),
                  ],
                ),
              ],
            ),
          ),

          // ── SO breakdown list ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Sales Orders (${soItems.length})',
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              itemCount: soItems.length,
              itemBuilder: (context, index) {
                final item = soItems[index];
                return _buildSoCard(item, dark800, orange);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSoCard(
      SalesOrderDetail item, Color dark, Color orange) {
    final progress = item.progress.clamp(0.0, 1.0);
    final progressPct = (progress * 100).toStringAsFixed(1);
    final isComplete = progress >= 1.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: dark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isComplete
              ? Colors.greenAccent.withOpacity(0.3)
              : Colors.white10,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // SO Number + Customer
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                item.soNumber,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              if (isComplete)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'COMPLETE',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          if (item.customerName != null && item.customerName!.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              item.customerName!,
              style:
                  const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
          const SizedBox(height: 14),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(
                  isComplete ? Colors.greenAccent : orange),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 10),
          // Quantities
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _soStat(
                  'Ordered',
                  '${item.quantity.toStringAsFixed(0)} KG',
                  Colors.white70),
              _soStat(
                  'Produced',
                  '${item.manufacturedQuantity.toStringAsFixed(0)} KG',
                  orange),
              _soStat(
                  'Progress',
                  '$progressPct%',
                  isComplete ? Colors.greenAccent : Colors.white70),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statChip({
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 14)),
      ],
    );
  }

  Widget _soStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 13)),
      ],
    );
  }
}
