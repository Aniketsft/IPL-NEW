import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'barcode_processor.dart';

class ProductScanBottomSheet extends StatefulWidget {
  final Map<String, dynamic> product;
  final List<Map<String, dynamic>> initialScans;
  final Function(List<Map<String, dynamic>>) onConfirm;

  const ProductScanBottomSheet({
    super.key,
    required this.product,
    required this.initialScans,
    required this.onConfirm,
  });

  @override
  State<ProductScanBottomSheet> createState() => _ProductScanBottomSheetState();
}

class _ProductScanBottomSheetState extends State<ProductScanBottomSheet> {
  late List<Map<String, dynamic>> _scans;
  MobileScannerController? _scannerController;
  bool _isScannerVisible = false;

  String? _selectedSite;
  String? _selectedLocation;
  String? _selectedLot;

  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _lotController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scans = List.from(widget.initialScans);
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedSite = prefs.getString('scan_site') ?? 'IPL';
      _selectedLocation = prefs.getString('scan_location');
      _selectedLot = prefs.getString('scan_lot');
      _locationController.text = _selectedLocation ?? '';
      _lotController.text = _selectedLot ?? '';
    });
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (_selectedSite != null) await prefs.setString('scan_site', _selectedSite!);
    if (_selectedLocation != null) await prefs.setString('scan_location', _selectedLocation!);
    if (_selectedLot != null) await prefs.setString('scan_lot', _selectedLot!);
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    _locationController.dispose();
    _lotController.dispose();
    super.dispose();
  }

  double get _totalWeight {
    return _scans.fold(0.0, (sum, item) => sum + (double.tryParse(item['weight'].toString()) ?? 0.0));
  }

  Future<void> _toggleScanner() async {
    if (!_isScannerVisible) {
      final status = await Permission.camera.request();
      if (status.isGranted) {
        setState(() {
          _isScannerVisible = true;
          _scannerController?.dispose();
          _scannerController = MobileScannerController(
            formats: [
              BarcodeFormat.ean13,
              BarcodeFormat.code128,
              BarcodeFormat.qrCode,
            ],
          );
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Camera permission is required to scan')),
          );
        }
      }
    } else {
      setState(() {
        _isScannerVisible = false;
        _scannerController?.dispose();
        _scannerController = null;
      });
    }
  }

  void _handleScan(BarcodeCapture capture) {
    final List<Barcode> barcodes = capture.barcodes;
    final packingUnit = (widget.product['packingUnit'] ?? '').toString();
    final standardWeight = double.tryParse((widget.product['standardWeight'] ?? '0').toString()) ?? 0.0;

    for (final barcode in barcodes) {
      final String? code = barcode.rawValue;
      if (code != null && BarcodeProcessor.isValidBarcode(code)) {
        if (!_scans.any((s) => s['barcode'] == code)) {
          final weight = BarcodeProcessor.calculateQuantity(
            barcode: code,
            packingUnit: packingUnit,
            standardWeight: standardWeight,
          );
          setState(() {
            _scans.insert(0, {
              'barcode': code,
              'productName': widget.product['productName'],
              'weight': weight,
              'site': _selectedSite,
              'location': _selectedLocation,
              'lot': _selectedLot,
              'timestamp': DateTime.now().toIso8601String(),
              'status': 'A',
            });
          });
          
          Feedback.forLongPress(context);
        }
      }
    }
  }

  void _addManualOneKg() {
    setState(() {
      _scans.insert(0, {
        'barcode': 'MANUAL-${DateTime.now().millisecondsSinceEpoch}',
        'productName': widget.product['productName'],
        'weight': 1.0,
        'site': _selectedSite,
        'location': _selectedLocation,
        'lot': _selectedLot,
        'timestamp': DateTime.now().toIso8601String(),
        'status': 'A',
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // final theme = Theme.of(context);
    final orange = const Color(0xFFFF9800);
    final darkBg = const Color(0xFF121212);
    final darkCard = const Color(0xFF1E1E1E);

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: darkBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.product['productName'] ?? 'Product Scan',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Product ID: ${widget.product['productId']}',
                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 10),
          
          // Site, Location, Lot Fields
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                Row(
                  children: [
                    // Site Selection
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            dropdownColor: const Color(0xFF1E1E1E),
                            value: _selectedSite,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            items: const [
                              DropdownMenuItem(value: 'IPL', child: Text('Site: IPL')),
                              DropdownMenuItem(value: 'SFT', child: Text('Site: SFT')),
                            ],
                            onChanged: (val) {
                              setState(() {
                                _selectedSite = val;
                                _savePreferences();
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Location
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _locationController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Location',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                          filled: true,
                          fillColor: const Color(0xFF1E1E1E),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                          ),
                        ),
                        onChanged: (val) {
                          _selectedLocation = val;
                          _savePreferences();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Lot
                TextField(
                  controller: _lotController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Lot Number',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                    ),
                  ),
                  onChanged: (val) {
                    _selectedLot = val;
                    _savePreferences();
                  },
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Summary Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _buildSummaryStat('TOTAL WEIGHT', '${_totalWeight.toStringAsFixed(2)} KG', orange),
                const SizedBox(width: 12),
                _buildSummaryStat('COUNT', '${_scans.length} Items', Colors.white),
              ],
            ),
          ),
          
          const SizedBox(height: 20),

          // Scanner Area
          if (_isScannerVisible)
            Container(
              height: 200,
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: orange.withOpacity(0.5), width: 1.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14.5),
                child: MobileScanner(
                  controller: _scannerController!,
                  onDetect: _handleScan,
                ),
              ),
            ),
          
          const SizedBox(height: 12),
          
          // Action Buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _toggleScanner,
                    icon: Icon(_isScannerVisible ? Icons.power_settings_new : Icons.qr_code_scanner),
                    label: Text(_isScannerVisible ? 'STOP SCAN' : 'START SCAN'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isScannerVisible ? Colors.red.withOpacity(0.2) : orange,
                      foregroundColor: _isScannerVisible ? Colors.red : Colors.black,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: _isScannerVisible ? const BorderSide(color: Colors.red) : BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _addManualOneKg,
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('SCAN 1KG'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.05),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.white.withOpacity(0.1)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          // List Header
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'SCANNED HISTORY',
                style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ),
          ),
          
          const SizedBox(height: 8),

          // Scanned List
          Expanded(
            child: _scans.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.qr_code_2, size: 64, color: Colors.white.withOpacity(0.05)),
                        const SizedBox(height: 12),
                        Text('No items scanned yet', style: TextStyle(color: Colors.white.withOpacity(0.2))),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _scans.length,
                    itemBuilder: (context, index) {
                      final scan = _scans[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: darkCard,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.05)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(Icons.qr_code, color: orange, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    scan['barcode'] ?? 'N/A',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                  Text(
                                    'Standard Entry',
                                    style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${scan['weight']} KG',
                                  style: TextStyle(color: orange, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _scans.removeAt(index);
                                    });
                                  },
                                  child: const Text('REMOVE', style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          
          // Footer
          Container(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              bottom: MediaQuery.of(context).padding.bottom + 20,
              top: 20,
            ),
            decoration: BoxDecoration(
              color: darkBg,
              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      widget.onConfirm(_scans);
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('CONFIRM AND CLOSE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryStat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
