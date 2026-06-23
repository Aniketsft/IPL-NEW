import 'package:flutter/material.dart';
import '../../../data/models/sales_invoice_item_stock_model.dart';
import '../../../data/repositories/sales_invoice_product_repository.dart';
import '../../../../../core/network_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/sales_invoice_cart_cubit.dart';

class LotSelectionScreen extends StatefulWidget {
  final String itemCode;
  final String salesUnit;

  const LotSelectionScreen({
    super.key, 
    required this.itemCode, 
    required this.salesUnit,
  });

  @override
  State<LotSelectionScreen> createState() => _LotSelectionScreenState();
}

class _LotSelectionScreenState extends State<LotSelectionScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<SalesInvoiceItemStockModel> _allLots = [];
  List<SalesInvoiceItemStockModel> _filteredLots = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLots();
    _searchController.addListener(_filterLots);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLots() async {
    try {
      final repository = SalesInvoiceProductRepository(context.read<NetworkService>());
      final stocks = await repository.getSalesInvoiceItemStockDetails(widget.itemCode);
      
      final cartItems = context.read<SalesInvoiceCartCubit>().state.items;
      final lots = stocks.map((stock) {
        double cartQty = 0;
        for (var item in cartItems) {
          if (item.product.sku == widget.itemCode && 
              item.lotNumber == stock.lotNumber && 
              item.location == stock.location && 
              item.warehouse == stock.warehouse) {
            cartQty += item.quantity;
          }
        }
        return stock.copyWith(totalQty: stock.totalQty - cartQty);
      }).toList();
      if (mounted) {
        setState(() {
          _allLots = lots;
          _filteredLots = lots;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _filterLots() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredLots = _allLots;
      } else {
        _filteredLots = _allLots.where((lot) {
          return lot.lotNumber.toLowerCase().contains(query) ||
                 lot.warehouse.toLowerCase().contains(query) ||
                 lot.location.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: theme.primaryColor),
        title: Text(
          'Lot Selection',
          style: TextStyle(
            color: theme.primaryColor,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
            color: isDark ? Colors.grey[800] : Colors.grey[300],
            height: 1.0,
          ),
        ),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[850] : Colors.white,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey.withOpacity(0.3)),
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search Lot',
                  hintStyle: TextStyle(color: Colors.grey[500]),
                  prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              ),
            ),
          ),
          
          // List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredLots.isEmpty
                    ? const Center(child: Text('No lots found.'))
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: _filteredLots.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final lot = _filteredLots[index];
                          return _buildLotCard(lot, isDark, theme);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildLotCard(SalesInvoiceItemStockModel lot, bool isDark, ThemeData theme) {
    return InkWell(
      onTap: () {
        Navigator.pop(context, lot);
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[900] : Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.grey.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'LOT NUMBER',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey[400],
                    letterSpacing: 0.5,
                  ),
                ),
                Flexible(
                  child: Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warehouse_outlined, size: 14, color: Colors.blueGrey[600]),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            lot.warehouseName.isNotEmpty 
                                ? '${lot.warehouse} - ${lot.warehouseName}' 
                                : (lot.warehouse.isNotEmpty ? lot.warehouse : 'N/A'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.blueGrey[600],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              lot.lotNumber.isNotEmpty ? lot.lotNumber : 'N/A',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'LOCATION',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey[400],
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        lot.location.isNotEmpty ? lot.location : 'N/A',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.grey[300] : Colors.blueGrey[800],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'TYPE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey[400],
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        lot.locationType.isNotEmpty ? lot.locationType : 'Standard Storage',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.grey[400] : Colors.blueGrey[700],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.primaryColor.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'QUANTITY',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: theme.primaryColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${lot.totalQty.toInt()} ${widget.salesUnit}',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: theme.primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
