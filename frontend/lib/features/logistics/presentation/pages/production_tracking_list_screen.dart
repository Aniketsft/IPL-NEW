import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:enterprise_auth_mobile/features/manufacturing/bloc/manufacturing_bloc.dart';
import 'package:enterprise_auth_mobile/features/manufacturing/bloc/manufacturing_event.dart';
import 'package:enterprise_auth_mobile/features/manufacturing/bloc/manufacturing_state.dart';
import 'package:enterprise_auth_mobile/core/widgets/standard_filter.dart';
import 'package:enterprise_auth_mobile/core/widgets/filter_input_widgets.dart';
import '../widgets/sync_status_header.dart';
import '../widgets/sync_overlay.dart';
import 'production_tracking_screen.dart';
import '../../domain/entities/sales_order.dart';
import '../../data/repositories/delivery_repository.dart';
import '../../../settings/data/models/site.dart';

class ProductionTrackingListScreen extends StatefulWidget {
  final List<String> permissions;
  
  const ProductionTrackingListScreen({super.key, required this.permissions});

  @override
  State<ProductionTrackingListScreen> createState() =>
      _ProductionTrackingListScreenState();
}

class _ProductionTrackingListScreenState
    extends State<ProductionTrackingListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final String _lastSync = '2026-03-10 10:25'; // Mocked for UI demo
  String? _selectedSiteId; // Default to All Sites to show INTERNAL (dummy) orders
  List<Site> _sites = [];
  double _tolerancePercentage = 0.0;

  @override
  void initState() {
    super.initState();
    _sites = Site.mockSites;
    _fetchAppSettings();
    _applyFilters();
  }

  Future<void> _fetchAppSettings() async {
    try {
      final repository = context.read<DeliveryRepository>();
      final settings = await repository.getAppSettings();
      if (mounted) {
        setState(() {
          _tolerancePercentage = settings.tolerancePercentage ?? 0.0;
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch app settings: $e');
    }
  }

  void _applyFilters() {
    context.read<ManufacturingBloc>().add(
      LoadProductionTrackingRequested(siteCode: _selectedSiteId),
    );
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
          'Production Tracking List',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: BlocBuilder<ManufacturingBloc, ManufacturingState>(
                builder: (context, state) {
                  String siteName = 'All Sites';
                  if (state is ProductionTrackingLoaded && state.currentSiteCode != null) {
                    final site = _sites.firstWhere(
                      (s) => s.id == state.currentSiteCode,
                      orElse: () => Site(id: '', companyId: '', name: state.currentSiteCode!),
                    );
                    siteName = site.name;
                  }
                  return Text(
                    siteName,
                    style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 12),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              SyncStatusHeader(lastSync: _lastSync),
              _buildFilters(),
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
                          style: const TextStyle(color: Colors.red),
                        ),
                      );
                    }
                    if (state is ProductionTrackingLoaded) {
                      final filteredItems = state.items.where((it) {
                        final code = it.itemCode.toLowerCase();
                        final desc = it.description.toLowerCase();
                        return code.contains(_searchQuery.toLowerCase()) ||
                            desc.contains(_searchQuery.toLowerCase());
                      }).toList();

                      if (filteredItems.isEmpty) {
                        return Center(
                          child: Text(
                            'No items found',
                            style: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                          ),
                        );
                      }

                      return ListView.builder(
                        itemCount: filteredItems.length,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        itemBuilder: (context, index) {
                          final item = filteredItems[index];
                          return _buildProductCard(item, theme, orange);
                        },
                      );
                    }
                    return Center(
                      child: Text(
                        'Initialize tracking...',
                        style: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SyncOverlay(),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: StandardFilter(
        searchController: _searchController,
        searchHint: 'Search Product...',
        onSearchChanged: (val) => setState(() => _searchQuery = val),
        onApply: _applyFilters,
        onReset: () {
          setState(() {
            _searchController.clear();
            _searchQuery = '';
            _selectedSiteId = null;
          });
          _applyFilters();
        },
        filterBuilder: (context, setModalState) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FilterDropdown(
                label: 'Production Site',
                value: _selectedSiteId ?? 'All Sites',
                options: ['All Sites', ..._sites.map((s) => s.id)],
                onChanged: (val) {
                  setState(() {
                    _selectedSiteId = val == 'All Sites' ? null : val;
                  });
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProductCard(dynamic item, ThemeData theme, Color orange) {
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08)),
        boxShadow: isDark ? null : [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(
          item.itemCode,
          style: TextStyle(
            color: orange,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              item.description,
              style: TextStyle(color: isDark ? Colors.white38 : Colors.black45, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStat('Ordered', '${item.formatQuantity(item.quantity ?? 0)} ${item.unit}', isDark),
                ),
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final bool isEA = (item.unit ?? '').toUpperCase() == 'EA' ||
                                        (item.unit ?? '').toUpperCase() == 'PCS';
                      final double tolerance = isEA ? 0.0 : _tolerancePercentage;
                      final effectiveLimit = (item.quantity ?? 0) * (1 + tolerance / 100);
                      return _buildStat(
                        'Max Allowed',
                        '${item.formatQuantity(effectiveLimit)} ${item.unit}',
                        isDark,
                        color: isDark ? Colors.white70 : Colors.black87,
                      );
                    },
                  ),
                ),
                Expanded(
                  child: _buildStat(
                    'Scanned',
                    '${item.formatQuantity(item.scannedQuantity ?? 0)} ${item.unit}',
                    isDark,
                    color: orange,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: Icon(Icons.chevron_right, color: isDark ? Colors.white24 : Colors.black26),
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProductionTrackingScreen(
                order: SalesOrder(
                  id: item.soNumber,
                  orderNumber: item.soNumber,
                  customerCode: item.customerCode ?? 'N/A',
                  customerName: item.customerName ?? 'N/A',
                  deliveryDate: '',
                  date: DateTime.now(),
                  salesManCode1: '',
                  salesManCode2: '',
                  site: item.site,
                ),
                product: item,
                permissions: widget.permissions,
              ),
            ),
          );
          if (result == true) {
            _applyFilters();
          }
        },
      ),
    );
  }

  Widget _buildStat(
    String label,
    String value,
    bool isDark, {
    Color color = Colors.white70,
  }) {
    // If not dark, default to black87 instead of white70
    final displayColor = (color == Colors.white70 && !isDark) ? Colors.black87 : color;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: isDark ? Colors.white24 : Colors.black38, fontSize: 11)),
        Text(
          value,
          style: TextStyle(
            color: displayColor,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
