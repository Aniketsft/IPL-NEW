import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:enterprise_auth_mobile/core/widgets/industrial_module_layout.dart';
import '../widgets/sync_status_header.dart';
import '../../domain/entities/sales_order.dart';
import '../widgets/sales_order_card.dart';
import '../../data/repositories/delivery_repository.dart';
import '../widgets/sync_overlay.dart';
import 'package:enterprise_auth_mobile/core/utils/barcode_scanner/barcode_scanner_widget.dart';
import '../widgets/label_qr_generator.dart';

class DeliveryScreen extends StatefulWidget {
  final List<String> permissions;

  const DeliveryScreen({super.key, required this.permissions});

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  final String _lastSync = '2026-03-10 10:25'; // Mocked for UI demo
  List<SalesOrder> _orders = [];
  List<SalesOrder> _filteredOrders = [];
  bool _isLoading = false;
  String? _errorMessage;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _fetchOrders();
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
      if (query.isEmpty) {
        _filteredOrders = List.from(_orders);
      } else {
        _filteredOrders = _orders.where((o) {
          return o.orderNumber.toLowerCase().contains(query) ||
                 o.customerName.toLowerCase().contains(query) ||
                 o.customerCode.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  Future<void> _fetchOrders() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repository = context.read<DeliveryRepository>();
      final soNumbers = await repository.getScannedDeliveryOrderNumbers();
      final results = await repository.fetchSalesOrderHeadersByNumbers(soNumbers);

      setState(() {
        _orders = results;
        _filteredOrders = results;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _scanManifest() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(
          color: Color(0xFF1D1D1D),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(margin: const EdgeInsets.symmetric(vertical: 12), width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'SCAN CRATE OR PALETTE',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5),
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: AppBarcodeScanner(
                  onScan: (code) {
                    Navigator.pop(context);
                    _processScan(code);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _processScan(String rawData) async {
    setState(() => _isLoading = true);
    try {
      final parsed = LabelQrGenerator.parse(rawData);
      if (parsed.isEmpty || (parsed['type'] != 'CRATE' && parsed['type'] != 'PALETTE')) {
        throw 'Invalid label for delivery dispatch. Please scan a CRATE or PALETTE label.';
      }

      List<String> soList = [];
      if (parsed['type'] == 'CRATE') {
        final so = parsed['soNumber'] ?? '';
        if (so.isNotEmpty && so != 'N/A') soList.add(so);
      } else if (parsed['type'] == 'PALETTE') {
        final manifest = parsed['manifest'] ?? '';
        final parts = manifest.split(';');
        for (var part in parts) {
          final chunks = part.split(':');
          if (chunks.isNotEmpty && chunks[0].isNotEmpty) {
            soList.add(chunks[0]);
          }
        }
      }

      if (soList.isEmpty) throw 'No matching Sales Orders found in this QR payload.';

      final repository = context.read<DeliveryRepository>();
      await repository.addDeliveryScan(soList, rawData);

      await _fetchOrders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Successfully added to Manifest', style: TextStyle(color: Colors.green)), backgroundColor: Colors.black)
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context, 
          builder: (_) => AlertDialog(
            backgroundColor: Colors.red[900], 
            title: const Text('SCAN REJECTED', style: TextStyle(color: Colors.white)), 
            content: Text(e.toString(), style: const TextStyle(color: Colors.white)), 
            actions: [TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('OK', style: TextStyle(color: Colors.white)))]
          )
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _clearManifest() async {
    final repository = context.read<DeliveryRepository>();
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1D1D1D),
        title: const Text('Clear Manifest?', style: TextStyle(color: Colors.white)),
        content: const Text('This will clear the current unloading queue. Proceed?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true), 
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('CLEAR', style: TextStyle(color: Colors.white))
          ),
        ],
      ),
    );

    if (confirm == true) {
      await repository.clearDeliveryScans();
      await _fetchOrders();
    }
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF9800);

    return IndustrialModuleLayout(
      title: 'DELIVERY',
      body: Stack(
        children: [
          Column(
            children: [
              SyncStatusHeader(lastSync: _lastSync),
              
              // Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search Scanned Manifest...',
                    hintStyle: const TextStyle(color: Colors.white24),
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    filled: true,
                    fillColor: const Color(0xFF2C2C2E),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                ),
              ),

              // Scanner / Empty State OR List
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: orange))
                    : _errorMessage != null
                    ? Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)))
                    : _filteredOrders.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.qr_code_scanner, size: 80, color: Colors.grey[800]),
                            const SizedBox(height: 16),
                            const Text('No Items in Manifest', style: TextStyle(color: Colors.grey, fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            const Text('Scan a Crate or Palette sequence to begin loading.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: _scanManifest,
                              icon: const Icon(Icons.camera_alt),
                              label: const Text('START SCANNING'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: orange,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              ),
                            )
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filteredOrders.length,
                        padding: const EdgeInsets.all(16),
                        itemBuilder: (context, index) {
                          return SalesOrderCard(
                            order: _filteredOrders[index],
                            onRefresh: _fetchOrders,
                            isDeliveryMode: true,
                          );
                        },
                      ),
              ),
              
              // Bottom Action Bar for active manifests
              if (_filteredOrders.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E1E1E),
                    border: Border(top: BorderSide(color: Colors.white10)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _clearManifest,
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('CLEAR QUEUE'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red[300],
                            side: BorderSide(color: Colors.red[900]!),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _scanManifest,
                          icon: const Icon(Icons.add_a_photo),
                          label: const Text('SCAN NEXT'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SyncOverlay(),
        ],
      ),
    );
  }
}
