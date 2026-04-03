import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'barcode_scanner_widget.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../features/logistics/data/repositories/delivery_repository.dart';
import '../../../features/logistics/domain/entities/location_lookup.dart';
import 'package:enterprise_auth_mobile/core/utils/audio/audio_service.dart';
import '../../../features/logistics/data/local/local_database_helper.dart';
import 'barcode_processor.dart';
import 'dart:ui' show ImageFilter;
import '../../app_theme.dart';


class ProductScanFloatingScreen extends StatefulWidget {
  final Map<String, dynamic> product;
  final List<Map<String, dynamic>> initialScans;
  final Function(List<Map<String, dynamic>>) onConfirm;

  const ProductScanFloatingScreen({
    super.key,
    required this.product,
    required this.initialScans,
    required this.onConfirm,
  });

  @override
  State<ProductScanFloatingScreen> createState() => _ProductScanFloatingScreenState();
}

class _ProductScanFloatingScreenState extends State<ProductScanFloatingScreen> {
  late List<Map<String, dynamic>> _scans;
  Map<String, dynamic>? _pendingScan;


  String? _selectedSite;
  List<String> _sites = [];
  bool _isLoadingSites = false;
  bool _isProcessingScan = false;
  
  List<LocationLookup> _locations = [];
  LocationLookup? _selectedLocationEntity;
  bool _isLoadingLocations = false;
  String? _selectedLot;

  final TextEditingController _lotController = TextEditingController();

  // Location and Lot controllers

  @override
  void initState() {
    super.initState();
    _scans = List.from(widget.initialScans);
    _loadPreferences();
    _fetchSites();
  }

  Future<void> _fetchSites() async {
    setState(() => _isLoadingSites = true);
    try {
      final repository = context.read<DeliveryRepository>();
      final sites = await repository.getProductionSites();
      if (mounted) {
        setState(() {
          _sites = sites;
          if (_sites.contains('IPL')) {
            _selectedSite = 'IPL';
          } else if (_selectedSite == null || !_sites.contains(_selectedSite)) {
            _selectedSite = _sites.isNotEmpty ? _sites.first : 'IPL';
          }
          _isLoadingSites = false;
        });
        _fetchLocations();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingSites = false);
    }
  }

  Future<void> _fetchLocations() async {
    if (_selectedSite == null) return;
    setState(() => _isLoadingLocations = true);
    try {
      final repository = context.read<DeliveryRepository>();
      final itemCode = widget.product['code']?.toString() ?? widget.product['productId']?.toString() ?? '';
      final locations = await repository.getTargetLocations(_selectedSite!, itemCode);
      
      if (mounted) {
        setState(() {
          _locations = locations;
          // Try to restore previous selection if it exists in the new list
          final lastLoc = _selectedLocationEntity?.location;
          if (lastLoc != null) {
             final found = _locations.where((l) => l.location == lastLoc);
             if (found.isNotEmpty) {
               _selectedLocationEntity = found.first;
             }
          } else if (_locations.isNotEmpty) {
            // Default to IPLCH if available
            final iplch = _locations.where((l) => l.location == 'IPLCH');
            _selectedLocationEntity = iplch.isNotEmpty ? iplch.first : _locations.first;
          }
          _isLoadingLocations = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingLocations = false);
    }
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedSite = prefs.getString('scan_site') ?? 'IPL';
      final lastLoc = prefs.getString('scan_location');
      if (lastLoc != null) {
        // We only have the string, entity will be resolved once locations are fetched
        _selectedLocationEntity = LocationLookup(
          location: lastLoc,
          warehouse: '',
          warehouseName: '',
          locationType: '',
          locationTypeName: '',
        );
      }
      _selectedLot = prefs.getString('scan_lot');
      _lotController.text = _selectedLot ?? '';
    });
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (_selectedSite != null) await prefs.setString('scan_site', _selectedSite!);
    if (_selectedLocationEntity != null) await prefs.setString('scan_location', _selectedLocationEntity!.location!);
    if (_selectedLot != null) await prefs.setString('scan_lot', _selectedLot!);
  }

  @override
  void dispose() {
    _lotController.dispose();
    super.dispose();
  }

  double get _totalWeight {
    return _scans.fold(0.0, (sum, item) => sum + (double.tryParse(item['weight'].toString()) ?? 0.0));
  }

  String _formatQuantity(double qty, [String? overrideUnit]) {
    final unit = (overrideUnit ?? widget.product['unit'] ?? widget.product['stockUnit'] ?? 'KG').toString().toUpperCase();
    if (unit == 'EA' || unit == 'PCS') {
      return qty.toInt().toString();
    }
    return qty.toStringAsFixed(3);
  }

  String get _unitLabel {
    return (widget.product['unit'] ?? widget.product['stockUnit'] ?? 'KG').toString().toUpperCase();
  }

  Future<void> _handleScan(String barcode, {bool isManual = false}) async {
    if (barcode.isEmpty) return;
    if (_isProcessingScan && !isManual) return;
    _isProcessingScan = true;

    if (_pendingScan != null && !isManual) {
      if (_pendingScan!['barcode'] == barcode) {
        _isProcessingScan = false;
        return;
      }
      AudioService.instance.playError(); // Scan Pending Reject
      HapticFeedback.heavyImpact(); // ERROR TACTILE
      _isProcessingScan = false;
      return;
    }

    try {
      final repository = context.read<DeliveryRepository>();
      
      // 1. Lookup Product by Barcode (matches tbl_products.barcode)
      final matchedProduct = await repository.getProductByBarcode(barcode);
      
      String targetItemCode;
      String targetUnit;
      double targetStdWeight;

      if (matchedProduct != null) {
        targetItemCode = matchedProduct[LocalDatabaseHelper.colProdCode] ?? '';
        targetUnit = matchedProduct[LocalDatabaseHelper.colProdStu] ?? 'KG';
        targetStdWeight = (matchedProduct[LocalDatabaseHelper.colProdStandardWeight] as num?)?.toDouble() ?? 0.0;
      } else {
        // Fallback to current selected product metadata
        targetItemCode = widget.product['code']?.toString() ?? widget.product['productId']?.toString() ?? '';
        targetUnit = _unitLabel;
        targetStdWeight = (widget.product['standardWeight'] as num?)?.toDouble() ?? 
                         (widget.product['itemWeight'] as num?)?.toDouble() ?? 0.0;
      }

      // 2. Process with specialised rule-set
      final result = BarcodeProcessor.process(
        barcode: barcode,
        itemCode: targetItemCode,
        unit: targetUnit,
        standardWeight: targetStdWeight,
      );

      if (mounted) {
        if (result.isValid) {
          // Validate product match if we are in a product-specific screen
          final expectedCode = widget.product['code']?.toString() ?? widget.product['productId']?.toString();
          if (result.itemCode != expectedCode) {
            AudioService.instance.playError(); // WRONG PRODUCT
            HapticFeedback.heavyImpact(); // ERROR TACTILE
            _showErrorDialog(
              'Wrong Product',
              'Scanned: ${result.itemCode}\nExpected: $expectedCode',
            );
            return;
          }

          setState(() {
            _pendingScan = {
              'barcode': result.processedBarcode,
              'originalBarcode': result.originalBarcode,
              'productCode': result.itemCode,
              'scannedQty': result.scannedQty,
              'manufacturedQty': result.manufacturedQty,
              'weight': result.manufacturedQty, // For backwards compatibility if needed
              'unit': targetUnit,
              'timestamp': DateTime.now().toIso8601String(),
            };
          });

          AudioService.instance.playSuccess(); // VALID SCAN - Synchronized with display
          HapticFeedback.lightImpact(); // SUCCESS TACTILE

          if (isManual) {
            _showConfirmationPrompt(result);
          }
        } else {
          AudioService.instance.playError(); // INVALID FORMAT
          HapticFeedback.heavyImpact(); // ERROR TACTILE
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid barcode format'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingScan = false;
        });
      }
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _savePendingScan() {
    if (_pendingScan == null) return;
    setState(() {
      final scanWithMetadata = Map<String, dynamic>.from(_pendingScan!);
      scanWithMetadata['site'] = _selectedSite;
      scanWithMetadata['location'] = _selectedLocationEntity?.location;
      scanWithMetadata['lot'] = _selectedLot;
      scanWithMetadata['status'] = 'A';
      
      _scans.insert(0, scanWithMetadata);
      _pendingScan = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Scan saved'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 1),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    // final theme = Theme.of(context);
    final orange = const Color(0xFFFF9800);
    final darkBg = const Color(0xFF121212);
    final darkCard = const Color(0xFF1E1E1E);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
          maxWidth: 600,
        ),
        decoration: BoxDecoration(
          color: darkBg,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.product['name'] ?? widget.product['productName'] ?? 'Product Scan',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: orange.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: orange.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              _unitLabel,
                              style: TextStyle(color: orange, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                        Text(
                          'Product ID: ${widget.product['productId']}',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
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
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            dropdownColor: const Color(0xFF1E1E1E),
                            value: _selectedSite,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            items: _sites.isEmpty 
                              ? [DropdownMenuItem(value: _selectedSite ?? 'IPL', child: Text(_selectedSite ?? "IPL"))]
                              : _sites.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                            onChanged: _isLoadingSites ? null : (val) {
                              if (val != null) {
                                setState(() {
                                  _selectedSite = val;
                                  _selectedLocationEntity = null;
                                  _savePreferences();
                                });
                                _fetchLocations();
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Location selection as a Picker/Dropdown
                    Expanded(
                      flex: 3,
                      child: InkWell(
                        onTap: _isLoadingLocations ? null : _showLocationPicker,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: _isLoadingLocations 
                                  ? const Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange)))
                                  : Text(
                                      _selectedLocationEntity?.location ?? 'Location',
                                      style: TextStyle(
                                        color: _selectedLocationEntity == null ? Colors.white.withValues(alpha: 0.3) : Colors.white,
                                        fontSize: 13,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                              ),
                              Icon(Icons.arrow_drop_down, color: Colors.white.withValues(alpha: 0.5)),
                            ],
                          ),
                        ),
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
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
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
                _buildSummaryStat('TOTAL $_unitLabel', '${_formatQuantity(_totalWeight)} $_unitLabel', orange),
                const SizedBox(width: 12),
                _buildSummaryStat('COUNT', '${_scans.length} Items', Colors.white),
              ],
            ),
          ),
          
          const SizedBox(height: 20),

          // Scanner and Pending Scan Result Area
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                Stack(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: AppBarcodeScanner(
                        onScan: _handleScan,
                        onManualAdd: (weight) {
                          setState(() {
                            _scans.insert(0, {
                              'barcode': 'MANUAL-${DateTime.now().millisecondsSinceEpoch}',
                              'productName': widget.product['productName'],
                              'weight': weight,
                              'site': _selectedSite,
                              'location': _selectedLocationEntity?.location,
                              'lot': _selectedLot,
                              'timestamp': DateTime.now().toIso8601String(),
                              'status': 'A',
                            });
                          });
                        },
                        manualEntries: const {'1KG': 1.0},
                        themeColor: orange,
                      ),
                    ),
                    if (_pendingScan != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: AppTheme.darkSurface.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: AppTheme.primaryAmber.withValues(alpha: 0.3),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  blurRadius: 20,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryAmber.withValues(alpha: 0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.qr_code_scanner, color: AppTheme.primaryAmber, size: 20),
                                    ),
                                    const SizedBox(width: 12),
                                    const Text(
                                      'Scan Result',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'READY',
                                        style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildOverlayStat(
                                        'SCANNED',
                                        _formatQuantity(_pendingScan!['scannedQty'] ?? 0.0, _pendingScan!['unit']),
                                        _pendingScan!['unit'],
                                        Colors.white70,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: _buildOverlayStat(
                                        'MANUFACTURED',
                                        _formatQuantity(_pendingScan!['manufacturedQty'] ?? 0.0, _pendingScan!['unit']),
                                        _pendingScan!['unit'],
                                        AppTheme.primaryAmber,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  'Barcode: ${_pendingScan!['barcode']}',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11, fontStyle: FontStyle.italic),
                                ),
                                const SizedBox(height: 24),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextButton(
                                        onPressed: () => setState(() => _pendingScan = null),
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.white54,
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                        ),
                                        child: const Text('Discard', style: TextStyle(fontWeight: FontWeight.w500)),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: _savePendingScan,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.primaryAmber,
                                          foregroundColor: Colors.black,
                                          elevation: 4,
                                          shadowColor: AppTheme.primaryAmber.withValues(alpha: 0.4),
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                        child: const Text('SAVE SCAN', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    onPressed: _showManualScanDialog,
                    icon: const Icon(Icons.keyboard_outlined, color: AppTheme.primaryAmber, size: 16),
                    label: const Text(
                      'Enter Barcode Manually',
                      style: TextStyle(
                        color: AppTheme.primaryAmber,
                        fontSize: 12,
                        decoration: TextDecoration.underline,
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
          Flexible(
            child: _scans.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.qr_code_2, size: 40, color: Colors.white.withValues(alpha: 0.05)),
                        const SizedBox(height: 8),
                        Text('No items scanned yet', style: TextStyle(color: Colors.white.withValues(alpha: 0.2))),
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
                          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: orange.withValues(alpha: 0.1),
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
                                      style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                             Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'M: ${_formatQuantity(double.tryParse(scan['manufacturedQty']?.toString() ?? scan['weight']?.toString() ?? '0') ?? 0.0, scan['unit'])}',
                                  style: TextStyle(color: orange, fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                Text(
                                  'S: ${_formatQuantity(double.tryParse(scan['scannedQty']?.toString() ?? '0') ?? 0.0, scan['unit'])}',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
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
              color: const Color(0xFF121212),
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
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
    ),
  );
}

  void _showManualScanDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Manual Entry', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter barcode number',
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          ),
          onSubmitted: (v) {
            Navigator.pop(context);
            _handleScan(v, isManual: true);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _handleScan(controller.text, isManual: true);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showConfirmationPrompt(BarcodeModel result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.orange),
            const SizedBox(width: 8),
            const Text('Confirm Scan', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPromptRow('Product:', result.itemCode),
            const SizedBox(height: 8),
            _buildPromptRow('Barcode:', result.processedBarcode),
            const SizedBox(height: 8),
            _buildPromptRow(
              'Weight:',
              '${BarcodeProcessor.formatQuantity(result.manufacturedQty, widget.product['unit'] ?? 'KG')} ${widget.product['unit'] ?? 'KG'}',
              isBold: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _pendingScan = null);
              Navigator.pop(context);
            },
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _savePendingScan();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Widget _buildPromptRow(String label, String value, {bool isBold = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: isBold ? Colors.orange : Colors.white,
              fontSize: 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOverlayStat(String label, String value, String unit, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              unit,
              style: TextStyle(
                color: color.withValues(alpha: 0.5),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryStat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
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

  void _showLocationPicker() {
    final TextEditingController searchController = TextEditingController();
    List<LocationLookup> filteredLocations = List.from(_locations);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.7,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Select Target Location',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search locations...',
                  hintStyle: const TextStyle(color: Colors.grey),
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  filled: true,
                  fillColor: const Color(0xFF2C2C2E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (value) {
                  setModalState(() {
                    filteredLocations = _locations
                        .where(
                          (l) => (l.location ?? '').toLowerCase().contains(
                            value.toLowerCase(),
                          ),
                        )
                        .toList();
                  });
                },
              ),
              const SizedBox(height: 16),
              Expanded(
                child: filteredLocations.isEmpty
                    ? Center(child: Text('No locations found', style: TextStyle(color: Colors.white.withValues(alpha: 0.3))))
                    : ListView.builder(
                        itemCount: filteredLocations.length,
                        itemBuilder: (context, index) {
                          final loc = filteredLocations[index];
                          final isSelected = _selectedLocationEntity?.location == loc.location;
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                            title: Text(
                              loc.location ?? '',
                              style: TextStyle(
                                color: isSelected ? const Color(0xFFFF9800) : Colors.white,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text(
                              '${loc.locationTypeName} - ${loc.warehouseName}',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 12,
                              ),
                            ),
                            trailing: isSelected ? const Icon(Icons.check, color: Color(0xFFFF9800)) : null,
                            onTap: () {
                              setState(() {
                                _selectedLocationEntity = loc;
                                _savePreferences();
                              });
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
