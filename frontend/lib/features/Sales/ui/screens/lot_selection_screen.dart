import 'package:flutter/material.dart';
import '../../../../core/widgets/industrial_module_layout.dart';
import '../../../../core/widgets/standard_filter.dart';
import '../../domain/entities/lot.dart';
import '../../data/repositories/sales_repository.dart';

class LotSelectionScreen extends StatefulWidget {
  final String productCode;
  const LotSelectionScreen({super.key, required this.productCode});

  @override
  State<LotSelectionScreen> createState() => _LotSelectionScreenState();
}

class _LotSelectionScreenState extends State<LotSelectionScreen> {
  final _searchController = TextEditingController();
  
  List<Lot> _allLots = [];
  List<Lot> _filteredLots = [];
  bool _isLoading = true;
  final SalesRepository _repository = SalesRepository();

  @override
  void initState() {
    super.initState();
    _fetchLots();
    _searchController.addListener(_onSearchChanged);
  }

  Future<void> _fetchLots() async {
    try {
      final lots = await _repository.getLotsForProduct(widget.productCode);
      setState(() {
        _allLots = lots;
        _filteredLots = lots;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredLots = _allLots.where((l) {
        return l.lotNumber.toLowerCase().contains(query) ||
            l.location.toLowerCase().contains(query) ||
            l.warehouse.toLowerCase().contains(query);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {



    return IndustrialModuleLayout(
      title: 'LOT SELECTION',
      body: Column(
        children: [
          StandardFilter(
            searchController: _searchController,
            searchHint: 'Search Lot Number or Location...',
            onSearchChanged: (_) => _onSearchChanged(),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredLots.isEmpty
                    ? const Center(child: Text('No lots available.'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: _filteredLots.length,
                        itemBuilder: (context, index) {
                          return _buildLotCard(context, _filteredLots[index]);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildLotCard(BuildContext context, Lot lot) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondaryColor = theme.colorScheme.secondary;

    return Opacity(
      opacity: lot.isDepleted ? 0.6 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark ? Colors.white10 : Colors.black12,
          ),
        ),
        child: InkWell(
          onTap: lot.isDepleted ? null : () {
            Navigator.pop(context, lot);
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'LOT NUMBER',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                        ),
                        Text(
                          lot.lotNumber,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                            decoration: lot.isDepleted ? TextDecoration.lineThrough : null,
                            decorationColor: Colors.red,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    if (lot.isDepleted)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Depleted',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: secondaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warehouse, size: 12, color: secondaryColor),
                            const SizedBox(width: 4),
                            Text(
                              lot.warehouse,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: secondaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoItem(context, 'LOCATION', lot.location),
                    ),
                    Expanded(
                      child: _buildInfoItem(context, 'TYPE', lot.type),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoItem(BuildContext context, String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
      ],
    );
  }
}
