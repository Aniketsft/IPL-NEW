import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../widgets/label_printing_handler.dart';
import '../../domain/entities/sales_order_detail.dart';
import '../../../manufacturing/bloc/manufacturing_bloc.dart';
import '../../../manufacturing/bloc/manufacturing_event.dart';
import '../../../manufacturing/bloc/manufacturing_state.dart';
class ProductionTrackingSoBreakdownScreen extends StatefulWidget {
  final String itemCode;
  final String description;
  final List<SalesOrderDetail> soItems;
  final List<String> permissions;
  final double tolerancePercentage;

  const ProductionTrackingSoBreakdownScreen({
    super.key,
    required this.itemCode,
    required this.description,
    required this.soItems,
    required this.permissions,
    this.tolerancePercentage = 0.0,
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
    if (!widget.permissions.contains('manufacturing.all.update')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You do not have permission to update manufacturing tracking.')),
      );
      return;
    }

    // Check header locks
    if (item.headerIsPreparedForShipment) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shipment is finalized and cannot be modified.')),
      );
      return;
    }

    if (item.headerIsClosed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preparation is closed and cannot be modified.')),
      );
      return;
    }

    if (item.isPrepared) {
      // Logic for REMOVING prepared status (Simpler flow)
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          final theme = Theme.of(context);
          final isDark = theme.brightness == Brightness.dark;
          return AlertDialog(
            backgroundColor: theme.cardColor,
            title: Text('Remove Prepared Status', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
            content: Text('Remove the prepared status for this item?', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('CONFIRM', style: TextStyle(color: Theme.of(context).primaryColor)),
              ),
            ],
          );
        },
      );

      if (confirmed == true) {
        _applyPreparationUpdate(item, false);
      }
    } else {
      // Logic for MARKING AS PREPARED (Consolidated with Printing Options)
      final choice = await LabelPrintingHandler.showPreparationPrompt(
        context: context,
        item: item,
      );

      if (choice != null && choice != 'cancel') {
        // Step 1: Apply the status update
        _applyPreparationUpdate(item, true);

        if (!mounted) return;

        // Step 2: Handle follow-up action
        if (choice == 'preview') {
          if (item.manufacturedQuantity <= 0) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Print aborted: Product has 0 manufactured quantity.'),
                  backgroundColor: Colors.redAccent,
                ),
              );
            }
          } else {
            await LabelPrintingHandler.showLabelPreview(
              context: context,
              item: item,
              onPrintRequested: (item, auditId) => LabelPrintingHandler.printLabel(
                context: context,
                item: item,
                auditId: auditId,
              ),
            );
          }
        } else if (choice == 'print') {
          if (item.manufacturedQuantity <= 0) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Print aborted: Product has 0 manufactured quantity.'),
                  backgroundColor: Colors.redAccent,
                ),
              );
            }
          } else {
            await LabelPrintingHandler.printLabel(
              context: context,
              item: item,
            );
          }
        }
      }
    }
  }

  void _applyPreparationUpdate(SalesOrderDetail item, bool willBePrepared) {
    HapticFeedback.mediumImpact();
    
    context.read<ManufacturingBloc>().add(
          UpdateItemPreparationStatus(
            soNumber: item.soNumber,
            itemCode: item.itemCode,
            isPrepared: willBePrepared,
          ),
        );

    setState(() {
      final index = _currentItems.indexWhere((i) => i.soNumber == item.soNumber);
      if (index != -1) {
        _currentItems[index] = _currentItems[index].copyWith(isPrepared: willBePrepared);
      }
    });
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    final totalOrdered =
        _currentItems.fold<double>(0, (s, i) => s + i.quantity);
    final bool isEA = _currentItems.first.unit.toUpperCase() == 'EA' || _currentItems.first.unit.toUpperCase() == 'PCS';
    final totalProduced = isEA 
        ? _currentItems.fold<double>(0, (s, i) => s + i.eaScannedQuantity)
        : _currentItems.fold<double>(0, (s, i) => s + i.manufacturedQuantity);
    final totalPrepared = _currentItems.where((i) => i.isPrepared).length;

    final aggProgress = totalOrdered > 0
        ? (totalProduced / totalOrdered).clamp(0.0, 1.0)
        : (totalProduced > 0 ? 1.0 : 0.0);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          widget.itemCode,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: isDark ? Colors.white : Colors.black87,
      ),
      body: Column(
        children: [
          // ── Aggregate summary card ──────────────────────────────────────
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: orange.withValues(alpha: 0.3)),
              boxShadow: isDark ? null : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        widget.description,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    BlocBuilder<ManufacturingBloc, ManufacturingState>(
                      builder: (context, state) {
                        if (state is ProductionTrackingLoaded &&
                            state.excessPools[widget.itemCode] != null) {
                          return _buildPoolBadge(
                            state.excessPools[widget.itemCode]!,
                            widget.soItems.first.unit,
                            isDark,
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: aggProgress,
                    backgroundColor: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
                    valueColor: AlwaysStoppedAnimation<Color>(orange),
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
                        color: isDark ? Colors.white70 : Colors.black87,
                        isDark: isDark,
                      ),
                    ),
                    Expanded(
                      child: _statChip(
                        label: 'Prepared',
                        value: '$totalPrepared / ${_currentItems.length}',
                        color: isDark ? Colors.blueAccent : Colors.blue.shade700,
                        isDark: isDark,
                      ),
                    ),
                    Expanded(
                      child: _statChip(
                        label: 'Overall',
                        value: '${(aggProgress * 100).toStringAsFixed(0)}%',
                        color: aggProgress >= 1.0
                            ? Colors.green
                            : (isDark ? Colors.white70 : Colors.black87),
                        isDark: isDark,
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
                style: TextStyle(
                  color: isDark ? Colors.white38 : Colors.black38,
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
                return _buildSoCard(item, index, theme, orange);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSoCard(
      SalesOrderDetail item, int index, ThemeData theme, Color orange) {
    final isDark = theme.brightness == Brightness.dark;
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
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isPrepared
                ? (isDark ? Colors.blueAccent.withValues(alpha: 0.5) : Colors.blue.withValues(alpha: 0.3))
                : (isComplete
                    ? (isDark ? Colors.greenAccent.withValues(alpha: 0.3) : Colors.green.withValues(alpha: 0.2))
                    : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08))),
          ),
          boxShadow: isDark ? null : [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
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
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                if (item.customerName != null &&
                    item.customerName!.isNotEmpty)
                  Text(
                    item.customerName!,
                    style:
                        TextStyle(color: isDark ? Colors.white38 : Colors.black45, fontSize: 12),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
                valueColor: AlwaysStoppedAnimation<Color>(isPrepared
                    ? Colors.blueGrey
                    : (isComplete ? Colors.green : orange)),
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
                    isDark ? Colors.white70 : Colors.black87,
                    isDark,
                  ),
                ),
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final bool isEA = item.unit.toUpperCase() == 'EA' || item.unit.toUpperCase() == 'PCS';
                      final double tolerance = isEA ? 0.0 : widget.tolerancePercentage;
                      final effectiveLimit = item.quantity * (1 + tolerance / 100);
                      return _soStat(
                        'Max Allowed',
                        '${item.formatQuantity(effectiveLimit)} ${item.unit}',
                        isDark ? Colors.white70 : Colors.black87,
                        isDark,
                      );
                    },
                  ),
                ),
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final bool isEA = item.unit.toUpperCase() == 'EA' || item.unit.toUpperCase() == 'PCS';
                      final double scannedQty = isEA ? item.eaScannedQuantity : item.manufacturedQuantity;
                      return _soStat(
                        'Scanned',
                        '${item.formatQuantity(scannedQty)} ${item.unit}',
                        orange,
                        isDark,
                      );
                    },
                  ),
                ),
                Expanded(
                  child: _soStat(
                    'Status',
                    isPrepared
                        ? 'PREPARED'
                        : (isComplete ? 'COMPLETE' : '$progressPct%'),
                    isPrepared
                        ? (isDark ? Colors.blueAccent : Colors.blue.shade700)
                        : (isComplete ? Colors.green : (isDark ? Colors.white70 : Colors.black87)),
                    isDark,
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
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 11)),
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

  Widget _soStat(String label, String value, Color color, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 11)),
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

  Widget _buildPoolBadge(double amount, String unit, bool isDark) {
    final poolColor = isDark ? Colors.blueAccent : Colors.blue.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: poolColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: poolColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, color: poolColor, size: 12),
          const SizedBox(width: 6),
          Text(
            'POOL: ${amount.toStringAsFixed(1)} $unit',
            style: TextStyle(
              color: poolColor,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
