import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/sales_order_detail.dart';
import '../../../manufacturing/bloc/manufacturing_bloc.dart';
import '../../../manufacturing/bloc/manufacturing_event.dart';
class ProductionTrackingSoBreakdownScreen extends StatefulWidget {
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
  State<ProductionTrackingSoBreakdownScreen> createState() =>
      _ProductionTrackingSoBreakdownScreenState();
}

class _ProductionTrackingSoBreakdownScreenState
    extends State<ProductionTrackingSoBreakdownScreen> {
  late List<SalesOrderDetail> _currentItems;

  @override
  void initState() {
    super.initState();
    _currentItems = List.from(widget.soItems);
  }

  Future<void> _toggleItemPreparation(SalesOrderDetail item) async {
    // Check header locks
    if (item.headerIsPreparedForShipment) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shipment is finalized and cannot be modified.')),
      );
      return;
    }

    if (item.headerIsClosed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Production is closed and cannot be modified.')),
      );
      return;
    }

    final String title = item.isPrepared ? 'Remove Prepared Status' : 'Mark as Prepared';
    final String content = item.isPrepared
        ? 'Are you sure you want to remove the prepared status from this item?'
        : 'Are you sure you want to mark this item as prepared?';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(content, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm', style: TextStyle(color: Color(0xFFFF9800))),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      HapticFeedback.mediumImpact();
      context.read<ManufacturingBloc>().add(
            UpdateItemPreparationStatus(
              soNumber: item.soNumber,
              itemCode: item.itemCode,
              isPrepared: !item.isPrepared,
            ),
          );

      setState(() {
        final index = _currentItems.indexWhere((i) => i.soNumber == item.soNumber);
        if (index != -1) {
          _currentItems[index] = _currentItems[index].copyWith(isPrepared: !item.isPrepared);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF9800);
    const dark800 = Color(0xFF1E1E1E);
    const dark900 = Color(0xFF0D0D0D);

    final totalOrdered =
        _currentItems.fold<double>(0, (s, i) => s + i.quantity);
    final totalManufactured =
        _currentItems.fold<double>(0, (s, i) => s + i.manufacturedQuantity);
    final totalPrepared = _currentItems.where((i) => i.isPrepared).length;

    final aggProgress = totalOrdered > 0
        ? (totalManufactured / totalOrdered).clamp(0.0, 1.0)
        : (totalManufactured > 0 ? 1.0 : 0.0);

    return Scaffold(
      backgroundColor: dark900,
      appBar: AppBar(
        title: Text(
          widget.itemCode,
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
              border: Border.all(color: orange.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.description,
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
                  children: [
                    Expanded(
                      child: _statChip(
                        label: 'Ordered',
                        value: '${_currentItems.first.formatQuantity(totalOrdered)} ${_currentItems.first.unit}',
                        color: Colors.white70
                      ),
                    ),
                    Expanded(
                      child: _statChip(
                        label: 'Prepared',
                        value: '$totalPrepared / ${_currentItems.length}',
                        color: Colors.blueAccent
                      ),
                    ),
                    Expanded(
                      child: _statChip(
                        label: 'Overall',
                        value: '${(aggProgress * 100).toStringAsFixed(0)}%',
                        color: aggProgress >= 1.0
                            ? Colors.greenAccent
                            : Colors.white70
                      ),
                    ),
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
                'Sales Orders (${_currentItems.length})',
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
              itemCount: _currentItems.length,
              itemBuilder: (context, index) {
                final item = _currentItems[index];
                return _buildSoCard(item, index, dark800, orange);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSoCard(
      SalesOrderDetail item, int index, Color dark, Color orange) {
    final progress = item.progress.clamp(0.0, 1.0);
    final progressPct = (progress * 100).toStringAsFixed(1);
    final isComplete = progress >= 1.0;
    final isPrepared = item.isPrepared;

    return InkWell(
      onLongPress: (item.headerIsClosed || item.headerIsPreparedForShipment) 
          ? null 
          : () => _toggleItemPreparation(item),
      onTap: () {
        if (item.headerIsClosed) {
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Production is closed and cannot be modified.')),
          );
        } else if (item.headerIsPreparedForShipment) {
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Shipment is finalized and cannot be modified.')),
          );
        }
      },
      child: Opacity(
        opacity: (isPrepared || item.headerIsClosed || item.headerIsPreparedForShipment) ? 0.6 : 1.0,
        child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: dark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isPrepared
                ? Colors.blueAccent.withValues(alpha: 0.5)
                : (isComplete
                    ? Colors.greenAccent.withValues(alpha: 0.3)
                    : Colors.white10),
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // SO Number
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.soNumber,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                if (item.customerName != null &&
                    item.customerName!.isNotEmpty)
                  Text(
                    item.customerName!,
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white10,
                valueColor: AlwaysStoppedAnimation<Color>(isPrepared
                    ? Colors.blueGrey
                    : (isComplete ? Colors.greenAccent : orange)),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 10),
            // Quantities
            Row(
              children: [
                Expanded(
                  child: _soStat(
                    'Ordered',
                    '${item.formatQuantity(item.quantity)} ${item.unit}',
                    Colors.white70,
                  ),
                ),
                Expanded(
                  child: _soStat(
                    'Produced (M)',
                    '${item.formatQuantity(item.manufacturedQuantity)} ${item.unit}',
                    orange,
                  ),
                ),
                Expanded(
                  child: _soStat(
                    'Scanned (S)',
                    '${item.formatQuantity(item.scannedQuantity)} scans',
                    Colors.white.withValues(alpha: 0.5),
                  ),
                ),
                Expanded(
                  child: _soStat(
                    'Status',
                    isPrepared
                        ? 'PREPARED'
                        : (isComplete ? 'COMPLETE' : '$progressPct%'),
                    isPrepared
                        ? Colors.blueAccent
                        : (isComplete ? Colors.greenAccent : Colors.white70),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
        Text(
          value,
          style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 13),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
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
        Text(
          value,
          style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
