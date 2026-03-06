import 'package:flutter/material.dart';
import 'package:enterprise_auth_mobile/core/widgets/industrial_module_layout.dart';

class ByIdentifierScreen extends StatefulWidget {
  const ByIdentifierScreen({super.key});

  @override
  State<ByIdentifierScreen> createState() => _ByIdentifierScreenState();
}

class _ByIdentifierScreenState extends State<ByIdentifierScreen> {
  final _idController = TextEditingController();
  bool _isScanning = false;
  ProductInfo? _scannedProduct;

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  void _simulateScan() {
    setState(() => _isScanning = true);
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _scannedProduct = ProductInfo(
          id: _idController.text.isNotEmpty ? _idController.text : 'SKU-7729',
          name: 'Precision Gear Shaft 12mm',
          category: 'Mechanical / Parts',
          specs:
              'Material: Hardened Steel\nFinish: Chrome Plated\nWeight: 0.45kg',
          stock: 42.0,
          location: 'SEC-04-B',
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return IndustrialModuleLayout(
      title: 'IDENTIFY ASSET',
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildScannerUI(),
            if (_scannedProduct != null) _buildProductDetails(),
            if (_scannedProduct == null && !_isScanning) _buildPlaceholder(),
          ],
        ),
      ),
    );
  }

  Widget _buildScannerUI() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(bottom: BorderSide(color: Color(0xFF2C2C2E))),
      ),
      child: Column(
        children: [
          Container(
            height: 180,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isScanning ? const Color(0xFFFF9800) : Colors.white10,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_isScanning)
                  const CircularProgressIndicator(color: Color(0xFFFF9800))
                else
                  const Icon(
                    Icons.qr_code_scanner,
                    size: 64,
                    color: Colors.white10,
                  ),
                if (_isScanning)
                  Positioned(
                    top: 40,
                    left: 20,
                    right: 20,
                    child: Container(
                      height: 2,
                      color: Colors.orange.withOpacity(0.5),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _idController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Manual ID Entry...',
                    hintStyle: const TextStyle(color: Colors.white24),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _isScanning ? null : _simulateScan,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF9800),
                  padding: const EdgeInsets.all(16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Icon(Icons.search, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProductDetails() {
    final p = _scannedProduct!;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9800).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  p.id,
                  style: const TextStyle(
                    color: Color(0xFFFF9800),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              const Text(
                'Active SKU',
                style: TextStyle(color: Colors.green, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            p.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            p.category,
            style: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
          const SizedBox(height: 24),
          _buildDetailRow(
            Icons.description_outlined,
            'Specifications',
            p.specs,
          ),
          const Divider(height: 32, color: Colors.white10),
          Row(
            children: [
              Expanded(
                child: _buildDetailRow(
                  Icons.inventory_2_outlined,
                  'Stock Level',
                  '${p.stock.toInt()} UNITS',
                ),
              ),
              Expanded(
                child: _buildDetailRow(
                  Icons.location_on_outlined,
                  'Last Location',
                  p.location,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: Colors.white38),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholder() {
    return const Padding(
      padding: EdgeInsets.only(top: 80),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.inventory_2_outlined, size: 48, color: Colors.white10),
            SizedBox(height: 16),
            Text(
              'Scan or enter an identifier to begin lookup',
              style: TextStyle(color: Colors.white24),
            ),
          ],
        ),
      ),
    );
  }
}

class ProductInfo {
  final String id;
  final String name;
  final String category;
  final String specs;
  final double stock;
  final String location;

  ProductInfo({
    required this.id,
    required this.name,
    required this.category,
    required this.specs,
    required this.stock,
    required this.location,
  });
}
