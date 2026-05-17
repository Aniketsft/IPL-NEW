import 'package:flutter/material.dart';
import '../../../../core/widgets/industrial_module_layout.dart';
import '../../../../core/widgets/standard_filter.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/customer.dart';
import '../../data/repositories/sales_repository.dart';
import 'order_summary_screen.dart';




class ProductSelectionScreen extends StatefulWidget {
  final String transactionType;
  final Customer customer;
  const ProductSelectionScreen({super.key, required this.transactionType, required this.customer});

  @override
  State<ProductSelectionScreen> createState() => _ProductSelectionScreenState();
}

class _ProductSelectionScreenState extends State<ProductSelectionScreen> {
  final _searchController = TextEditingController();
  final Map<String, double> _selectedQuantities = {};

  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];
  bool _isLoading = true;
  final SalesRepository _repository = SalesRepository();

  @override
  void initState() {
    super.initState();
    _fetchProducts();
    _searchController.addListener(_onSearchChanged);
  }

  Future<void> _fetchProducts() async {
    try {
      final products = await _repository.getProducts();
      setState(() {
        _allProducts = products;
        _filteredProducts = products;
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
      _filteredProducts = _allProducts.where((p) {
        return p.name.toLowerCase().contains(query) ||
            p.code.toLowerCase().contains(query) ||
            p.category.toLowerCase().contains(query);
      }).toList();
    });
  }

  double get _totalAmount {
    double total = 0;
    _selectedQuantities.forEach((code, qty) {
      final product = _allProducts.firstWhere((p) => p.code == code);
      total += product.price * qty;
    });
    return total;
  }

  int get _selectedCount => _selectedQuantities.length;

  @override
  Widget build(BuildContext context) {



    return IndustrialModuleLayout(
      title: '${widget.transactionType.toUpperCase()} - ADD PRODUCTS',
      body: Stack(
        children: [
          Column(
            children: [
              StandardFilter(
                searchController: _searchController,
                searchHint: 'Search by SKU, name or category...',
                onSearchChanged: (_) => _onSearchChanged(),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _filteredProducts.isEmpty
                        ? const Center(child: Text('No products found.'))
                        : ListView.builder(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: _filteredProducts.length,
                            itemBuilder: (context, index) {
                              return _buildProductCard(context, _filteredProducts[index]);
                            },
                          ),
              ),
              const SizedBox(height: 100), // Space for bottom bar
            ],
          ),
          _buildBottomSummary(context),
        ],
      ),
    );
  }

  Widget _buildProductCard(BuildContext context, Product product) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.primaryColor;
    final currentQty = _selectedQuantities[product.code] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: currentQty > 0
              ? primaryColor.withValues(alpha: 0.5)
              : (isDark ? Colors.white10 : Colors.black12),
          width: currentQty > 0 ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 50,
                  width: 50,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.inventory_2_outlined,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            product.code,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: primaryColor,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white24 : Colors.black26,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            product.category,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white38 : Colors.black38,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PRICE / ${product.unit}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                    Text(
                      'Rs.${product.price.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ],
                ),
                _buildQuantitySelector(product),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuantitySelector(Product product) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.primaryColor;
    final currentQty = _selectedQuantities[product.code] ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black12,
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: currentQty > 0
                ? () {
                    setState(() {
                      if (currentQty <= 1) {
                        _selectedQuantities.remove(product.code);
                      } else {
                        _selectedQuantities[product.code] = currentQty - 1;
                      }
                    });
                  }
                : null,
            icon: const Icon(Icons.remove, size: 16),
            color: primaryColor,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              currentQty.toStringAsFixed(0),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _selectedQuantities[product.code] = currentQty + 1;
              });
            },
            icon: const Icon(Icons.add, size: 16),
            color: primaryColor,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSummary(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardColor,
          border: Border(
            top: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$_selectedCount ITEMS SELECTED',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                  Text(
                    'Rs.${_totalAmount.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: theme.primaryColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton(
                onPressed: _selectedCount > 0
                    ? () {
                        final items = _selectedQuantities.entries.map((e) {
                          final p = _allProducts.firstWhere((p) => p.code == e.key);
                          return {
                            'code': p.code,
                            'name': p.name,
                            'sku': p.code,
                            'price': p.price,
                            'qty': e.value.toInt(),
                            'total': p.price * e.value,
                          };
                        }).toList();
                        
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OrderSummaryScreen(
                              totalAmount: _totalAmount,
                              customer: widget.customer,
                              items: items,
                            ),
                          ),
                        );
                      }
                    : null,

                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'PREVIEW',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward, size: 18),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
