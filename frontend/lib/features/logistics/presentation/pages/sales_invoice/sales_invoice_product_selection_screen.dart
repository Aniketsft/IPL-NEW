import 'package:flutter/material.dart';
import '../../../../../core/widgets/industrial_module_layout.dart';
import '../../../data/models/sales_invoice_product_model.dart';
import '../../../data/repositories/sales_invoice_product_repository.dart';
import '../../../../../core/network_service.dart';
import '../../../../../core/widgets/filter_input_widgets.dart';
import '../../../../../core/widgets/standard_filter.dart';
import '../../../../../core/widgets/search_picker_sheet.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/sales_invoice_cart_cubit.dart';
import 'add_item_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SalesInvoiceProductSelectionScreen extends StatefulWidget {
  final String siteCode; // passed from previous screens

  const SalesInvoiceProductSelectionScreen({super.key, required this.siteCode});

  @override
  State<SalesInvoiceProductSelectionScreen> createState() =>
      _SalesInvoiceProductSelectionScreenState();
}

class _SalesInvoiceProductSelectionScreenState
    extends State<SalesInvoiceProductSelectionScreen> {
  late SalesInvoiceProductRepository _repository;
  final TextEditingController _searchController = TextEditingController();
  String _stockFilter = 'in stock'; // Default to in stock as requested
  String? _selectedWarehouse;
  List<String> _warehouses = [];
  bool _isInit = false;
  SharedPreferences? _prefs;

  List<SalesInvoiceProductModel> _products = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _offset = 0;
  final int _limit = 20;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreProducts();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _repository = SalesInvoiceProductRepository(context.read<NetworkService>());
    if (!_isInit) {
      _isInit = true;
      _initData();
    }
  }

  Future<void> _initData() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    if (mounted) {
      setState(() {
        _searchController.text = prefs.getString('si_product_search') ?? '';
        _stockFilter = prefs.getString('si_product_stock_filter') ?? 'in stock';
        _selectedWarehouse = prefs.getString('si_product_warehouse');
      });
    }
    _loadWarehouses();
  }

  Future<void> _loadWarehouses() async {
    final whs = await _repository.getDistinctWarehouses();
    setState(() {
      _warehouses = whs;
    });
    _resetAndFetch();
  }

  void _savePrefs() {
    if (_prefs != null) {
      _prefs!.setString('si_product_search', _searchController.text);
      _prefs!.setString('si_product_stock_filter', _stockFilter);
      if (_selectedWarehouse != null) {
        _prefs!.setString('si_product_warehouse', _selectedWarehouse!);
      } else {
        _prefs!.remove('si_product_warehouse');
      }
    }
  }

  void _resetAndFetch() {
    _savePrefs();
    setState(() {
      _products.clear();
      _offset = 0;
      _hasMore = true;
    });
    _loadMoreProducts();
  }

  Future<void> _loadMoreProducts() async {
    if (_isLoading || !_hasMore) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final newProducts = await _repository.getSalesInvoiceProducts(
        warehouse: _selectedWarehouse,
        query: _searchController.text.trim().toLowerCase(),
        stockFilter: _stockFilter,
        limit: _limit,
        offset: _offset,
      );

      setState(() {
        _offset += newProducts.length;
        _products.addAll(newProducts);
        if (newProducts.length < _limit) {
          _hasMore = false;
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      debugPrint('Error loading products: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return IndustrialModuleLayout(
      title: 'Select Product',
      body: Column(
        children: [
          StandardFilter(
            onApply: _resetAndFetch,
            searchController: _searchController,
            onSearchChanged: (val) => _resetAndFetch(),
            hasActiveFilters:
                _selectedWarehouse != null || _stockFilter != 'all',
            onReset: () {
              setState(() {
                _searchController.clear();
                _selectedWarehouse = null;
                _stockFilter = 'all';
              });
              _resetAndFetch();
            },
            filterBuilder: (context, setModalState) {
              return Column(
                children: [
                  Row(
                    children: [
                      FilterPickerTile(
                        label: 'Warehouse',
                        value: _selectedWarehouse,
                        icon: Icons.location_on_outlined,
                        onTap: () => SearchPickerSheet.show(
                          context: context,
                          title: 'Warehouse',
                          items: _warehouses
                              .map((w) => {'code': w, 'name': 'Warehouse $w'})
                              .toList(),
                          onSelected: (code) {
                            setState(() => _selectedWarehouse = code);
                            setModalState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilterSegmentedToggle(
                    label: 'Stock Status',
                    value: _stockFilter,
                    options: const ['in stock', 'out of stock', 'all'],
                    onChanged: (value) {
                      setState(() => _stockFilter = value);
                      setModalState(() {});
                    },
                  ),
                ],
              );
            },
          ),
          // Product List
          Expanded(
            child: _products.isEmpty && _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _products.isEmpty
                ? const Center(child: Text('No products found.'))
                : ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _products.length + (_hasMore ? 1 : 0),
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      if (index == _products.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      final product = _products[index];
                      return _buildProductCard(context, product, isDark);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(
    BuildContext context,
    SalesInvoiceProductModel product,
    bool isDark,
  ) {
    final cartItems = context.watch<SalesInvoiceCartCubit>().state.items;
    double cartQty = 0;
    CartItem? existingItem;
    int? editingIndex;
    for (int i = 0; i < cartItems.length; i++) {
      var item = cartItems[i];
      if (item.product.sku == product.sku) {
        cartQty += item.quantity;
        existingItem = item;
        editingIndex = i;
      }
    }

    final actualStock = product.stockQty - cartQty;
    final isInStock = actualStock > 0;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AddItemDetailScreen(
              product: product,
              existingItem: existingItem,
              editingIndex: editingIndex,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    product.sku,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '${actualStock.toStringAsFixed(0)} ',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      TextSpan(
                        text: product.salesUnit.isNotEmpty
                            ? product.salesUnit
                            : 'units',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              product.name,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isInStock
                        ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
                        : Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isInStock
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        size: 14,
                        color: isInStock
                            ? Theme.of(context).primaryColor
                            : Colors.red[700],
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isInStock ? 'In Stock' : 'Out of Stock',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isInStock
                              ? Theme.of(context).primaryColor
                              : Colors.red[700],
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
