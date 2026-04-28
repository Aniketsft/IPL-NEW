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
import '../../../features/logistics/presentation/widgets/scan_item_card.dart';
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
          final lastLoc = _selectedLocationEntity?.location;
          if (lastLoc != null) {
             final found = _locations.where((l) => l.location == lastLoc);
             if (found.isNotEmpty) {
               _selectedLocationEntity = found.first;
             }
          } else if (_locations.isNotEmpty) {
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
      return qty.toStringAsFixed(2);
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
      AudioService.instance.playError();
      HapticFeedback.heavyImpact();
      _isProcessingScan = false;
      return;
    }

    try {
      final repository = context.read<DeliveryRepository>();
      final matchedProduct = await repository.getProductByBarcode(barcode);
      
      if (matchedProduct == null) {
        AudioService.instance.playError();
        HapticFeedback.heavyImpact();
        if (mounted) {
          _showErrorDialog('Barcode Not Found', 'This barcode is not registered in the system.');
        }
        return;
      }

      final String targetItemCode = matchedProduct[LocalDatabaseHelper.colProdCode] ?? '';
      final String targetUnit = matchedProduct[LocalDatabaseHelper.colProdSau] ?? 'KG';
      final double targetStdWeight = (matchedProduct[LocalDatabaseHelper.colProdStandardWeight] as num?)?.toDouble() ?? 0.0;

      final result = BarcodeProcessor.process(
        barcode: barcode,
        itemCode: targetItemCode,
        unit: targetUnit,
        standardWeight: targetStdWeight,
      );

      if (mounted) {
        if (result.isValid) {
          final expectedCode = widget.product['code']?.toString() ?? widget.product['productId']?.toString();
          if (result.itemCode != expectedCode) {
            AudioService.instance.playError();
            HapticFeedback.heavyImpact();
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
              'weight': result.manufacturedQty,
              'unit': targetUnit,
              'timestamp': DateTime.now().toIso8601String(),
            };
          });

          AudioService.instance.playSuccess();
          HapticFeedback.lightImpact();

          if (isManual) {
            _showConfirmationPrompt(result);
          }
        } else {
          AudioService.instance.playError();
          HapticFeedback.heavyImpact();
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 8),
            Text(title, style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
          ],
        ),
        content: Text(message, style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;
    final darkBg = theme.scaffoldBackgroundColor;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Material(
        color: Colors.transparent,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
            maxWidth: 500,
          ),
          decoration: BoxDecoration(
            color: darkBg,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.1),
                blurRadius: 30,
                spreadRadius: 10,
              ),
            ],
            border: Border.all(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Column(
              children: [
                Expanded(
                  child: CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 12),
                            Center(
                              child: Container(
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.white12,
                                  borderRadius: BorderRadius.circular(2),
                                ),
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
                                                style: TextStyle(
                                                  color: isDark ? Colors.white : Colors.black87,
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
                                    icon: Icon(Icons.close, color: isDark ? Colors.white54 : Colors.black45),
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
                                      Expanded(
                                        flex: 2,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12),
                                          decoration: BoxDecoration(
                                            color: isDark ? Colors.black.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.03),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05)),
                                          ),
                                          child: DropdownButtonHideUnderline(
                                            child: DropdownButton<String>(
                                              isExpanded: true,
                                              dropdownColor: theme.cardColor,
                                              value: _selectedSite,
                                              style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
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
                                      Expanded(
                                        flex: 3,
                                        child: InkWell(
                                          onTap: _isLoadingLocations ? null : _showLocationPicker,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                            decoration: BoxDecoration(
                                              color: isDark ? Colors.black.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.03),
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05)),
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    _selectedLocationEntity?.location ?? 'Select Location',
                                                    style: TextStyle(
                                                      color: _selectedLocationEntity == null ? Colors.white38 : Colors.white,
                                                      fontSize: 13,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                _isLoadingLocations 
                                                  ? SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: orange))
                                                  : const Icon(Icons.arrow_drop_down, color: Colors.white54),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _lotController,
                                    style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                                    decoration: InputDecoration(
                                      hintText: 'Enter Lot ID',
                                      hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.black26),
                                      filled: true,
                                      fillColor: isDark ? Colors.black.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.03),
                                      prefixIcon: Icon(Icons.pin_outlined, color: isDark ? Colors.white54 : Colors.black45, size: 18),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1)),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05)),
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                                  _buildSummaryStat(context, 'TOTAL $_unitLabel', '${_formatQuantity(_totalWeight)} $_unitLabel', orange),
                                  const SizedBox(width: 12),
                                  _buildSummaryStat(context, 'COUNT', '${_scans.length} Items', isDark ? Colors.white : Colors.black87),
                                ],
                              ),
                            ),
                            
                            const SizedBox(height: 20),

                            // Scanner Area
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: Stack(
                                children: [
                                  SizedBox(
                                    width: double.infinity,
                                    child: AppBarcodeScanner(
                                      onScan: _handleScan,
                                      onManualAdd: (weight) {
                                        double finalWeight = weight;
                                        final unit = _unitLabel;
                                        if (unit == 'EA' || unit == 'PCS') {
                                          // Use standard weight for EA products if manual add is used as "+1 Unit"
                                          final stdWeight = (widget.product['standardWeight'] as num?)?.toDouble() ?? 
                                                           (widget.product['conversion'] as num?)?.toDouble() ?? 1.0;
                                          finalWeight = stdWeight;
                                        }

                                        setState(() {
                                          _scans.insert(0, {
                                            'barcode': 'MANUAL-${DateTime.now().millisecondsSinceEpoch}',
                                            'productName': widget.product['productName'],
                                            'weight': finalWeight,
                                            'site': _selectedSite,
                                            'location': _selectedLocationEntity?.location,
                                            'lot': _selectedLot,
                                            'timestamp': DateTime.now().toIso8601String(),
                                            'status': 'A',
                                          });
                                        });
                                      },
                                      manualEntries: _unitLabel == 'EA' || _unitLabel == 'PCS' ? const {'+1 EA': 1.0} : const {'+1 KG': 1.0},
                                      themeColor: orange,
                                    ),
                                  ),
                                  if (_pendingScan != null)
                                    Positioned.fill(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(16),
                                        child: BackdropFilter(
                                          filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                                          child: Container(
                                            color: theme.cardColor.withValues(alpha: 0.85),
                                            padding: const EdgeInsets.all(20),
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                const Text(
                                                  'SCAN SUCCESSFUL',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: 16,
                                                    letterSpacing: 1.5,
                                                  ),
                                                ),
                                                const SizedBox(height: 16),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: _buildOverlayStat(
                                                        _unitLabel == 'EA' || _unitLabel == 'PCS' ? 'QTY (EA)' : 'SCANNED',
                                                        BarcodeProcessor.formatQuantity(_pendingScan!['scannedQty'] ?? 0.0, _pendingScan!['unit']),
                                                        _pendingScan!['unit'],
                                                        Colors.white70,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: _buildOverlayStat(
                                                        _unitLabel == 'EA' || _unitLabel == 'PCS' ? 'WEIGHT (KG)' : 'TOTAL (KG)',
                                                        BarcodeProcessor.formatQuantity(_pendingScan!['manufacturedQty'] ?? 0.0, 'KG'),
                                                        'KG',
                                                        AppTheme.primaryAmber,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 24),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: TextButton(
                                                        onPressed: () => setState(() => _pendingScan = null),
                                                        child: Text('DISCARD', style: TextStyle(color: isDark ? Colors.white54 : Colors.black45, fontWeight: FontWeight.bold)),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: ElevatedButton(
                                                        onPressed: _savePendingScan,
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor: AppTheme.primaryAmber,
                                                          foregroundColor: Colors.black,
                                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                        ),
                                                        child: const Text('SAVE', style: TextStyle(fontWeight: FontWeight.bold)),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            
                            const SizedBox(height: 8),
                            Center(
                              child: TextButton.icon(
                                onPressed: _showManualScanDialog,
                                icon: const Icon(Icons.keyboard_outlined, color: AppTheme.primaryAmber, size: 16),
                                label: const Text(
                                  'Enter Barcode Manually',
                                  style: TextStyle(color: AppTheme.primaryAmber, fontSize: 12, decoration: TextDecoration.underline),
                                ),
                              ),
                            ),
                            
                            const Padding(
                              padding: EdgeInsets.fromLTRB(20, 24, 20, 8),
                              child: Text(
                                'SCANNED HISTORY',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      if (_scans.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.qr_code_2, size: 48, color: Colors.white.withValues(alpha: 0.05)),
                                const SizedBox(height: 12),
                                Text(
                                  'No items scanned yet',
                                  style: TextStyle(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.2), fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final scan = _scans[index];
                                return ScanItemCard(
                                  lineNumber: _scans.length - index,
                                  scan: scan,
                                  unit: _unitLabel,
                                  onDelete: () {
                                    setState(() {
                                      _scans.removeAt(index);
                                    });
                                  },
                                );
                              },
                              childCount: _scans.length,
                            ),
                          ),
                        ),
                      const SliverToBoxAdapter(child: SizedBox(height: 20)),
                    ],
                  ),
                ),
                
                // Footer
                Container(
                  padding: EdgeInsets.fromLTRB(
                    20, 20, 20, MediaQuery.of(context).padding.bottom + 20
                  ),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    border: Border(top: BorderSide(color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05))),
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
                            backgroundColor: orange,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: const Text('CONFIRM AND CLOSE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showManualScanDialog() {
    final TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: theme.cardColor,
          title: Text('Manual Entry', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
          content: TextField(
            controller: controller,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Enter barcode number',
              hintStyle: TextStyle(color: isDark ? Colors.grey : Colors.black38),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.black12)),
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
        );
      },
    );
  }

  void _showConfirmationPrompt(BarcodeModel result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: theme.cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.check_circle_outline, color: Theme.of(context).primaryColor),
            const SizedBox(width: 8),
            Text('Confirm Scan', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
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
              'Weight (KG):',
              '${BarcodeProcessor.formatQuantity(result.manufacturedQty, 'KG')} KG',
              isBold: true,
            ),
            if (widget.product['unit'] == 'EA' || widget.product['unit'] == 'PCS')
              _buildPromptRow(
                'Qty (EA):',
                '${BarcodeProcessor.formatQuantity(result.scannedQty, 'EA')} EA',
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
      );
    },
  );
}

  Widget _buildPromptRow(String label, String value, {bool isBold = false}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(color: isDark ? Colors.grey : Colors.black54, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: isBold ? orange : (isDark ? Colors.white : Colors.black87),
              fontSize: 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOverlayStat(String label, String value, String unit, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.4),
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

  Widget _buildSummaryStat(BuildContext context, String label, String value, Color color) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 10, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  void _showLocationPicker() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final TextEditingController searchController = TextEditingController();
    List<LocationLookup> filteredLocations = List.from(_locations);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : theme.cardColor,
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
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Select Target Location',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: searchController,
                autofocus: true,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  hintText: 'Search locations...',
                  hintStyle: TextStyle(color: isDark ? Colors.grey : Colors.black38),
                  prefixIcon: Icon(Icons.search, color: isDark ? Colors.grey : Colors.black38),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF2C2C2E) : Colors.black.withValues(alpha: 0.03),
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
                                color: isSelected ? theme.primaryColor : (isDark ? Colors.white : Colors.black87),
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text(
                              '${loc.locationTypeName} - ${loc.warehouseName}',
                              style: TextStyle(
                                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.5),
                                fontSize: 12,
                              ),
                            ),
                            trailing: isSelected ? Icon(Icons.check, color: theme.primaryColor) : null,
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
