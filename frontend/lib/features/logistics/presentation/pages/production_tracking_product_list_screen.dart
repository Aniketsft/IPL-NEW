import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:enterprise_auth_mobile/features/manufacturing/bloc/manufacturing_bloc.dart';
import 'package:enterprise_auth_mobile/features/manufacturing/bloc/manufacturing_event.dart';
import 'package:enterprise_auth_mobile/features/manufacturing/bloc/manufacturing_state.dart';
import '../../domain/entities/sales_order_detail.dart';
import 'production_tracking_so_breakdown_screen.dart';

class ProductionTrackingProductListScreen extends StatefulWidget {
  const ProductionTrackingProductListScreen({super.key});

  @override
  State<ProductionTrackingProductListScreen> createState() =>
      _ProductionTrackingProductListScreenState();
}

class _ProductionTrackingProductListScreenState
    extends State<ProductionTrackingProductListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    context.read<ManufacturingBloc>().add(const LoadProductionTrackingRequested());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Group flat list of SalesOrderDetail by itemCode
  Map<String, List<SalesOrderDetail>> _groupByProduct(
      List<SalesOrderDetail> items) {
    final Map<String, List<SalesOrderDetail>> grouped = {};
    for (final item in items) {
      grouped.putIfAbsent(item.itemCode, () => []).add(item);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Production Tracking',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: isDark ? Colors.white : Colors.black87,
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val),
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                hintText: 'Search by product code or name...',
                hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 14),
                prefixIcon: Icon(Icons.search, color: isDark ? Colors.grey : Colors.grey[600]),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          
          // Date selection filter
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                BlocBuilder<ManufacturingBloc, ManufacturingState>(
                  builder: (context, state) {
                    final selectedDate = state.selectedDate ?? DateTime.now();
                    final dateStr = DateFormat('EEE, d MMM yyyy').format(selectedDate);
                    
                    return GestureDetector(
                      onTap: () async {
                        final pickedDate = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime.now().subtract(const Duration(days: 365)),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: ColorScheme.fromSeed(
                                  seedColor: orange,
                                  primary: orange,
                                  onPrimary: Colors.white,
                                  surface: theme.cardColor,
                                  onSurface: isDark ? Colors.white : Colors.black87,
                                  brightness: theme.brightness,
                                ),
                                dialogBackgroundColor: theme.scaffoldBackgroundColor,
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (pickedDate != null && mounted) {
                          context.read<ManufacturingBloc>().add(
                            LoadProductionTrackingRequested(date: pickedDate)
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: orange.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today, color: orange, size: 14),
                            const SizedBox(width: 8),
                            Text(
                              dateStr,
                              style: TextStyle(
                                color: orange,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            Icon(Icons.arrow_drop_down, color: orange),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const Spacer(),
                Text(
                  'Filtering by Delivery Date',
                  style: TextStyle(color: isDark ? Colors.white24 : Colors.black26, fontSize: 10, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: BlocBuilder<ManufacturingBloc, ManufacturingState>(
              builder: (context, state) {
                if (state is ManufacturingLoadInProgress) {
                  return Center(
                    child: CircularProgressIndicator(color: orange),
                  );
                }
                if (state is ManufacturingFailure) {
                  return Center(
                    child: Text(
                      state.message,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  );
                }
                if (state is ProductionTrackingLoaded) {
                  final grouped = _groupByProduct(state.items);

                  // Filter by search query
                  final filteredKeys = grouped.keys.where((code) {
                    final desc =
                        grouped[code]!.first.description.toLowerCase();
                    return code.toLowerCase().contains(
                              _searchQuery.toLowerCase(),
                            ) ||
                        desc.contains(_searchQuery.toLowerCase());
                  }).toList()
                    ..sort();

                  if (filteredKeys.isEmpty) {
                    return Center(
                      child: Text(
                        'No products found',
                        style: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    itemCount: filteredKeys.length,
                    itemBuilder: (context, index) {
                      final code = filteredKeys[index];
                      final soItems = grouped[code]!;
                      return _buildProductCard(
                          context, code, soItems, theme, orange, state);
                    },
                  );
                }
                return Center(
                  child: Text(
                    'Loading production data...',
                    style: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(
    BuildContext context,
    String itemCode,
    List<SalesOrderDetail> soItems,
    ThemeData theme,
    Color orange,
    ManufacturingState state,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final description = soItems.first.description;
    final totalOrdered = soItems.fold<double>(0, (s, i) => s + i.quantity);
    final totalScanned =
        soItems.fold<double>(0, (s, i) => s + i.scannedQuantity);
    final totalManufactured =
        soItems.fold<double>(0, (s, i) => s + i.manufacturedQuantity);
    final aggProgress = totalOrdered > 0
        ? (totalManufactured / totalOrdered).clamp(0.0, 1.0)
        : (totalManufactured > 0 ? 1.0 : 0.0);
    final soCount = soItems.length;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProductionTrackingSoBreakdownScreen(
              itemCode: itemCode,
              description: description,
              soItems: soItems,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
          boxShadow: isDark ? null : [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            itemCode,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          if (state is ProductionTrackingLoaded &&
                              (state as ProductionTrackingLoaded)
                                      .excessPools[itemCode] !=
                                  null) ...[
                            const SizedBox(width: 8),
                            _buildPoolBadge(
                              (state as ProductionTrackingLoaded)
                                  .excessPools[itemCode]!,
                              soItems.first.unit,
                              isDark,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: TextStyle(
                          color: isDark ? Colors.white38 : Colors.black45,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$soCount SO${soCount != 1 ? 's' : ''}',
                    style: TextStyle(
                      color: orange,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: aggProgress,
                backgroundColor: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
                valueColor: AlwaysStoppedAnimation<Color>(orange),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 10),
            // Stats row (Ordered & Progress)
            Row(
              children: [
                Expanded(
                  child: _buildStat(
                    'Ordered',
                    '${soItems.first.formatQuantity(totalOrdered)} ${soItems.first.unit}',
                    isDark ? Colors.white70 : Colors.black87,
                    isDark,
                  ),
                ),
                Expanded(
                  child: _buildStat(
                    'Progress',
                    '${(aggProgress * 100).toStringAsFixed(0)}%',
                    aggProgress >= 1.0 ? Colors.green : (isDark ? Colors.white70 : Colors.black87),
                    isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Full-width Scanned & Manufactured row
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: orange.withValues(alpha: 0.15)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildStat(
                      'Produced (M)',
                      '${soItems.first.formatQuantity(totalManufactured)} / ${soItems.first.formatQuantity(totalOrdered)} ${soItems.first.unit}',
                      orange,
                      isDark,
                      isFullWidth: true,
                    ),
                  ),
                  _buildStat(
                    'Scanned (S)',
                    '${soItems.first.formatQuantity(totalScanned)} scans',
                    isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black45,
                    isDark,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value, Color color, bool isDark, {bool isFullWidth = false}) {
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
            fontSize: isFullWidth ? 15 : 13,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildPoolBadge(double amount, String unit, bool isDark) {
    final poolColor = isDark ? Colors.blueAccent : Colors.blue.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: poolColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: poolColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, color: poolColor, size: 10),
          const SizedBox(width: 4),
          Text(
            'POOL: ${amount.toStringAsFixed(1)} $unit',
            style: TextStyle(
              color: poolColor,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
