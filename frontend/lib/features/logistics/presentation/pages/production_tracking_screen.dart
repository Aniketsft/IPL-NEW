import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'dart:ui' show ImageFilter;

import '../../../../core/utils/barcode_scanner/barcode_scanner_widget.dart';
import '../../../../core/utils/audio/audio_service.dart';
import '../../../../core/utils/barcode_scanner/barcode_processor.dart';

import '../../domain/entities/sales_order.dart';
import '../../domain/entities/sales_order_detail.dart';
import '../../data/repositories/delivery_repository.dart';
import '../../domain/entities/location_lookup.dart';
import '../widgets/scan_item_card.dart';
import '../../data/local/local_database_helper.dart';

const Color orange = Color(0xFFFF9800);
const Color dark800 = Color(0xFF1E1E1E);
const Color dark900 = Color(0xFF0D0D0D);
const Color darkBorder = Color(0xFF2C2C2E);

class ProductionTrackingScreen extends StatefulWidget {
  final SalesOrder order;
  final SalesOrderDetail product;

  const ProductionTrackingScreen({
    super.key,
    required this.order,
    required this.product,
  });

  @override
  State<ProductionTrackingScreen> createState() =>
      _ProductionTrackingScreenState();
}

class _ProductionTrackingScreenState extends State<ProductionTrackingScreen> {
  String _status = 'A'; // A: Approved, Q: Quality, R: Rejected
  double _cumulativeQty = 0.0; // Qty of pending (unsaved) scans this session
  double _baseSessionScannedQty = 0.0; // Qty of successfully saved batch scans this session.
  List<Map<String, dynamic>> _scans = [];
  Map<String, dynamic>? _pendingScan;
  bool _isSaving = false;
  bool _isProcessingBarcode = false;
  bool _isLoadingHistory = false;
  List<String> _sites = [];
  String? _selectedSite;
  List<String> _lots = [];
  String? _selectedLot;
  List<LocationLookup> _locations = [];
  LocationLookup? _selectedLocation;
  bool _isScannerVisible = false;
  bool _isSettingsExpanded = false;
  List<Map<String, dynamic>> _excessPools = [];
  bool _isLoadingExcess = false;
  double _tolerancePercentage = 0.0;

  @override
  void initState() {
    super.initState();
    _selectedSite = widget.product.site;
    _fetchInitialData();
    _fetchHistoricalScans();
    _fetchExcessPools();
  }

  Future<void> _fetchInitialData() async {
    try {
      await _fetchProductionSites();
      await _fetchLocations();
      await _fetchAppSettings();
      if (_selectedSite != null) {
        await _fetchLots();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading initial data: $e')),
        );
      }
    }
  }

  Future<void> _fetchHistoricalScans() async {
    if (_isLoadingHistory) return;
    setState(() => _isLoadingHistory = true);
    try {
      final repository = context.read<DeliveryRepository>();
      final historicalScans = await repository.getProductionScans(
        widget.order.orderNumber,
        widget.product.itemCode,
      );
      if (mounted && historicalScans.isNotEmpty) {
        final mappedScans = historicalScans.map((s) => {
          'barcode': s['barcode'] ?? s['syncId'] ?? 'SAVED',
          'originalBarcode': s['barcode'] ?? '',
          'productCode': s['itemCode'] ?? widget.product.itemCode,
          'scannedQty': (s['scanAmountKg'] as num?)?.toDouble() ?? 0.0,
          'manufacturedQty': (s['scanAmountKg'] as num?)?.toDouble() ?? 0.0,
          'weight': (s['scanAmountKg'] as num?)?.toDouble() ?? 0.0,
          'unit': widget.product.unit,
          'timestamp': s['createdAt'] ?? DateTime.now().toIso8601String(),
          'status': s['itemStatus'] ?? 'A',
          'siteId': _selectedSite,
          'locationCode': s['location'],
          'lot': s['lot'],
          'soNumber': widget.order.orderNumber,
          'isSaved': true,
        }).toList();
        setState(() {
          // Append historical at the end (pending scans stay at top)
          _scans = [..._scans.where((s) => s['isSaved'] != true), ...mappedScans];
        });
      }
    } catch (e) {
      debugPrint('Failed to load historical scans: $e');
    } finally {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  Future<void> _fetchExcessPools() async {
    if (widget.order.orderNumber.startsWith('BLK-') || 
        widget.order.orderNumber.startsWith('CUTS-') || 
        widget.order.orderNumber.startsWith('FRZ-')) {
      return; // Can't allocate from bulk into bulk (for now)
    }

    setState(() => _isLoadingExcess = true);
    try {
      final repository = context.read<DeliveryRepository>();
      final pools = await repository.getExcessByDateAndItem(
        widget.order.date,
        widget.product.itemCode,
      );
      if (mounted) {
        setState(() {
          _excessPools = pools.where((p) {
            final double available = (p['poolQty'] as num).toDouble() - (p['allocatedQty'] as num).toDouble();
            return available > 0.001;
          }).toList();
        });
      }
    } catch (e) {
      debugPrint('Failed to load excess pools: $e');
    } finally {
      if (mounted) setState(() => _isLoadingExcess = false);
    }
  }

  Future<void> _fetchLocations() async {
    if (_selectedSite == null) return;
    try {
      final repository = context.read<DeliveryRepository>();
      final locations = await repository.getTargetLocations(
        _selectedSite!,
        widget.product.itemCode,
      );
      if (mounted) {
        setState(() {
          _locations = locations;
          if (_selectedLocation == null && _locations.isNotEmpty) {
            final iplch = _locations.where((l) => l.location == 'IPLCH');
            _selectedLocation = iplch.isNotEmpty ? iplch.first : _locations.first;
          }

        });
      }
    } catch (e) {
      if (mounted) {

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading locations: $e')),
        );
      }
    }
  }

  Future<void> _fetchProductionSites() async {
    try {
      final repository = context.read<DeliveryRepository>();
      final sites = await repository.getProductionSites();
      if (mounted) {
        setState(() {
          _sites = sites;
          if (_sites.contains('IPL')) {
            _selectedSite = 'IPL';
          } else if (_selectedSite == null || !_sites.contains(_selectedSite)) {
            _selectedSite = _sites.isNotEmpty ? _sites.first : null;
          }

        });
      }
    } catch (e) {
      if (mounted) {

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading production sites: $e')),
        );
      }
    }
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

  Future<void> _fetchLots() async {
    if (_selectedSite == null) return;
    try {
      final repository = context.read<DeliveryRepository>();
      final lots = await repository.getLots(
        widget.product.itemCode,
        _selectedSite!,
      );
      
      // Integrate Global Daily Lot Number
      final settings = await repository.getAppSettings();
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      String? globalLot;
      
      if (settings.dailyLotNumber != null && 
          settings.dailyLotNumber!.isNotEmpty && 
          settings.lastLotDate == todayStr) {
        globalLot = settings.dailyLotNumber;
      }

      if (mounted) {
        setState(() {
          _lots = lots;
          
          // If global lot is available and not in the list, add it (or prioritize it)
          if (globalLot != null) {
            if (!_lots.contains(globalLot)) {
              _lots.insert(0, globalLot!);
            }
            _selectedLot = globalLot;
          } else if (_selectedLot == null || !_lots.contains(_selectedLot)) {
            _selectedLot = _lots.isNotEmpty ? _lots.first : null;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading lots: $e')),
        );
      }
    }
  }

  void _onSiteChanged(String? siteId) {
    if (siteId != null && siteId != _selectedSite) {
      setState(() {
        _selectedSite = siteId;
        _selectedLocation = null;
        _selectedLot = null;
      });
      _fetchLocations();
      _fetchLots();
    }
  }

  void _toggleScanner() {
    setState(() => _isScannerVisible = !_isScannerVisible);
  }

  Future<bool> _handleScan(String rawString) async {
    final barcode = rawString.trim();
    if (barcode.isEmpty) return false;
    if (_isProcessingBarcode) return false;
    _isProcessingBarcode = true;

    try {
      if (_pendingScan != null) {
        if (_pendingScan!['barcode'] == barcode) {
          _isProcessingBarcode = false;
          return true;
        }
        AudioService.instance.playError();
        HapticFeedback.heavyImpact();
        _showErrorDialog('Scan Pending', 'Please save or discard the current scan first.');
        return false;
      }

      final repository = context.read<DeliveryRepository>();
      final matchedProduct = await repository.getProductByBarcode(barcode);
      
      if (matchedProduct == null) {
        AudioService.instance.playError();
        HapticFeedback.heavyImpact();
        _showErrorDialog('Barcode Not Found', 'This barcode is not registered in the system.');
        return false;
      }

      final String targetItemCode = matchedProduct[LocalDatabaseHelper.colProdCode] ?? '';
      final String targetUnit = matchedProduct[LocalDatabaseHelper.colProdStu] ?? 'KG';
      final double targetStdWeight = (matchedProduct[LocalDatabaseHelper.colProdStandardWeight] as num?)?.toDouble() ?? 0.0;

      final result = BarcodeProcessor.process(
        barcode: barcode,
        itemCode: targetItemCode,
        unit: targetUnit,
        standardWeight: targetStdWeight,
      );

      if (mounted) {
        if (result.isValid) {
          if (result.itemCode != widget.product.itemCode) {
            AudioService.instance.playError();
            HapticFeedback.heavyImpact();
            _showErrorDialog('Wrong Product', 'Scanned: ${result.itemCode}\nExpected: ${widget.product.itemCode}');
            return false;
          }

          final isCutBulkOrder = widget.order.orderNumber.startsWith('CB-') || 
                                 widget.order.orderNumber.startsWith('BLK-') || 
                                 widget.order.orderNumber.startsWith('CUTS-') || 
                                 widget.order.orderNumber.startsWith('FRZ-');
          if (!isCutBulkOrder && _status == 'A') {
            final effectiveLimit = widget.product.quantity * (1 + _tolerancePercentage / 100);
            final remaining = effectiveLimit - widget.product.manufacturedQuantity - _cumulativeQty;
            if (result.manufacturedQty > remaining + 0.001) {
              AudioService.instance.playError();
              HapticFeedback.heavyImpact();
              _showErrorDialog('Limit Exceeded', 'Scanning ${widget.product.formatQuantity(result.manufacturedQty)} would exceed the order limit (with $_tolerancePercentage% tolerance).');
              return false;
            }
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
        } else {
          AudioService.instance.playError();
          HapticFeedback.heavyImpact();
          _showErrorDialog('Invalid Barcode', 'Invalid barcode format.');
          return false;
        }
      }
      return true;
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      return false;
    } finally {
      if (mounted) setState(() => _isProcessingBarcode = false);
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: dark800,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
      scanWithMetadata['status'] = _status;
      scanWithMetadata['siteId'] = _selectedSite;
      scanWithMetadata['locationCode'] = _selectedLocation?.location;
      scanWithMetadata['lot'] = _selectedLot;
      scanWithMetadata['soNumber'] = widget.order.orderNumber;
      scanWithMetadata['productCode'] = widget.product.itemCode;
      scanWithMetadata['isSaved'] = false;

      _scans.insert(0, scanWithMetadata);
      if (_status == 'A') {
        _cumulativeQty += _pendingScan!['manufacturedQty'] as double;
      }
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

  void _addManualQty(double qty) {
    final isCutBulkOrder = widget.order.orderNumber.startsWith('CB-') || 
                           widget.order.orderNumber.startsWith('BLK-') || 
                           widget.order.orderNumber.startsWith('CUTS-') || 
                           widget.order.orderNumber.startsWith('FRZ-');
    if (!isCutBulkOrder) {
      final effectiveLimit = widget.product.quantity * (1 + _tolerancePercentage / 100);
      final remaining = effectiveLimit - widget.product.manufacturedQuantity - _baseSessionScannedQty - _cumulativeQty;
      if (qty > remaining + 0.001) {
        AudioService.instance.playError();
        HapticFeedback.heavyImpact();
        _showErrorDialog('Limit Exceeded', 'Adding ${qty.toStringAsFixed(3)} would exceed the limit (with $_tolerancePercentage% tolerance).');
        return;
      }
    }

    setState(() {
      final manualScan = {
        'barcode': 'MANUAL-${qty.toInt()}KG-${DateTime.now().millisecondsSinceEpoch}',
        'manufacturedQty': qty,
        'scannedQty': qty,
        'weight': qty,
        'productCode': widget.product.itemCode,
        'soNumber': widget.order.orderNumber,
        'status': _status,
        'siteId': _selectedSite,
        'locationCode': _selectedLocation?.location,
        'lot': _selectedLot,
        'timestamp': DateTime.now().toIso8601String(),
        'unit': widget.product.unit,
        'isSaved': false,
      };
      _scans.insert(0, manualScan);
      if (_status == 'A') _cumulativeQty += qty;
    });

    AudioService.instance.playSuccess();
    HapticFeedback.lightImpact();
  }

  Future<void> _saveAndUpload() async {
    final pendingScans = _scans.where((s) => s['isSaved'] != true).toList();
    if (pendingScans.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No new scans to save')));
      return;
    }
    if (_selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select target location')));
      return;
    }

    setState(() => _isSaving = true);
    try {
      final repository = context.read<DeliveryRepository>();

      // Enrich all pending scans with current location/lot before saving
      final enrichedScans = pendingScans.map((s) {
        final copy = Map<String, dynamic>.from(s);
        copy['locationCode'] = _selectedLocation?.location;
        copy['lot'] = _selectedLot;
        copy['soNumber'] = widget.order.orderNumber;
        copy['productCode'] = widget.product.itemCode;
        return copy;
      }).toList();

      await repository.saveProductionScansBatch(enrichedScans);

      if (mounted) {
        setState(() {
          // Mark all pending scans as saved in place
          for (int i = 0; i < _scans.length; i++) {
            if (_scans[i]['isSaved'] != true) {
              _scans[i] = Map<String, dynamic>.from(_scans[i])..
                ['isSaved'] = true;
            }
          }
          // Shift the pending quantity naturally into the core persistent memory for this screen session
          _baseSessionScannedQty += _cumulativeQty;
          _cumulativeQty = 0.0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All scans saved to database ✓'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );

        // Auto-navigate back after success
        Future.delayed(const Duration(milliseconds: 1200), () {
          if (mounted) {
            Navigator.pop(context, true);
          }
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, dynamic) {
        if (!didPop) {
          Navigator.pop(context, _baseSessionScannedQty > 0);
        }
      },
      child: Scaffold(
        backgroundColor: dark900,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context, _baseSessionScannedQty > 0),
        ),
        title: const Text('Production Scan', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1.0)),
      ),
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        const SizedBox(height: 8),
                        _buildHeaderCard(),
                        const SizedBox(height: 16),
                        _buildSettingsCard(),
                        const SizedBox(height: 16),
                        _buildProgressAndStatus(),
                        const SizedBox(height: 20),
                        _buildScannerOrSummary(),
                        const SizedBox(height: 24),
                        if (_scans.isNotEmpty) ...[
                          _buildHistoryHeader(),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
                  ),
                ),
                if (_scans.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final scan = _scans[index];
                          final bool isSaved = scan['isSaved'] == true;
                          return ScanItemCard(
                            lineNumber: _scans.length - index,
                            scan: scan,
                            unit: widget.product.unit,
                            canDelete: !isSaved,
                            onDelete: isSaved ? null : () {
                              setState(() {
                                _scans.removeAt(index);
                                if (scan['status'] == 'A') {
                                  _cumulativeQty -= (scan['manufacturedQty'] as num).toDouble();
                                }
                              });
                            },
                          );
                        },
                        childCount: _scans.length,
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            ),
          ),
          _buildActionFooter(),
        ],
      ),
    ),
    );
  }

  double get totalAvailableExcess {
    if (_excessPools.isEmpty) return 0.0;
    return _excessPools.fold(0.0, (sum, p) {
      final double pool = (p['poolQty'] as num).toDouble();
      final double allocated = (p['allocatedQty'] as num).toDouble();
      return sum + (pool - allocated);
    });
  }

  Widget _buildHeaderCard() {
    final double availablePool = totalAvailableExcess;
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: dark800,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.order.customerName, style: const TextStyle(color: orange, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5)),
              if (availablePool > 0) _bulkPoolBadge(availablePool),
            ],
          ),
          const SizedBox(height: 6),
          Text(widget.product.description, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              _infoChip('SKU: ${widget.product.itemCode}'),
              const SizedBox(width: 8),
              _infoChip('SO: ${widget.order.orderNumber}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bulkPoolBadge(double amount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade900, Colors.blue.shade600],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.blue.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inventory_2_outlined, color: Colors.white, size: 12),
          const SizedBox(width: 6),
          Text(
            'POOL: ${amount.toStringAsFixed(2)} ${widget.product.unit}',
            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildSettingsCard() {
    return Container(
      decoration: BoxDecoration(
        color: dark800,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: darkBorder),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _isSettingsExpanded = !_isSettingsExpanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.settings_outlined, color: orange, size: 20),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('PRODUCTION SETTINGS', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.0))),
                  Icon(_isSettingsExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.grey),
                ],
              ),
            ),
          ),
          if (_isSettingsExpanded) ...[
            const Divider(color: Colors.white10, height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildDropdownField('Production Site', _selectedSite, _sites, _onSiteChanged),
                  const SizedBox(height: 12),
                  _buildLotField(),
                  const SizedBox(height: 12),
                  _buildLocationField(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDropdownField(String label, String? value, List<String> items, Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: dark900, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              dropdownColor: dark800,
              value: value,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              items: items.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLotField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Production Lot', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Autocomplete<String>(
          initialValue: TextEditingValue(text: _selectedLot ?? ''),
          optionsBuilder: (v) => v.text.isEmpty ? _lots : _lots.where((s) => s.contains(v.text)),
          onSelected: (s) => setState(() => _selectedLot = s),
          fieldViewBuilder: (ctx, ctrl, node, onSub) => TextField(
            controller: ctrl,
            focusNode: node,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              filled: true,
              fillColor: dark900,
              hintText: 'Enter or search lot',
              hintStyle: const TextStyle(color: Colors.white24),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white10)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white10)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLocationField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Target Location', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        InkWell(
          onTap: _showLocationPicker,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: dark900, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
            child: Row(
              children: [
                Expanded(child: Text(_selectedLocation?.location ?? 'Select Location', style: TextStyle(color: _selectedLocation == null ? Colors.white24 : Colors.white, fontSize: 14))),
                const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressAndStatus() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: dark800, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _statTile('Ordered', '${widget.product.formatQuantity(widget.product.quantity)} ${widget.product.unit}'),
              _statTile('Remaining', '${widget.product.formatQuantity((widget.product.quantity * (1 + _tolerancePercentage / 100)) - widget.product.manufacturedQuantity - _baseSessionScannedQty - _cumulativeQty)} ${widget.product.unit}', color: orange),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('STATUS', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
              const Spacer(),
              _buildStatusToggles(),
            ],
          ),
          if (_excessPools.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 16),
            _buildExcessAllocationButton(),
          ],
        ],
      ),
    );
  }

  Widget _buildExcessAllocationButton() {
    // Total available across all pools
    double totalAvailable = 0;
    for (var pool in _excessPools) {
      totalAvailable += (pool['poolQty'] as num).toDouble() - (pool['allocatedQty'] as num).toDouble();
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: orange.withOpacity(0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _showAllocationDialog,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.layers_outlined, color: orange, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ALLOCATE FROM BULK POOL',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Total Excess Available: ${widget.product.formatQuantity(totalAvailable)} ${widget.product.unit}',
                        style: TextStyle(
                          color: orange.withOpacity(0.8),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, color: orange, size: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAllocationDialog() {
    final TextEditingController amountController = TextEditingController();
    Map<String, dynamic> selectedPool = _excessPools.first;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final double poolAvailable = (selectedPool['poolQty'] as num).toDouble() - 
                                     (selectedPool['allocatedQty'] as num).toDouble();
          
          final remainingOrder = widget.product.quantity - 
                                widget.product.manufacturedQuantity - 
                                _baseSessionScannedQty - 
                                _cumulativeQty;

          return AlertDialog(
            backgroundColor: dark800,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.layers_outlined, color: orange),
                SizedBox(width: 12),
                Text('Manual Allocation', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select Source Pool:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: dark900,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<Map<String, dynamic>>(
                        isExpanded: true,
                        dropdownColor: dark800,
                        value: selectedPool,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        items: _excessPools.map((p) => DropdownMenuItem(
                          value: p,
                          child: Text('${p['soNumber']} (${widget.product.formatQuantity((p['poolQty'] as num).toDouble() - (p['allocatedQty'] as num).toDouble())} left)'),
                        )).toList(),
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selectedPool = val);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Amount to Allocate (KG):', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      Text('Max: ${widget.product.formatQuantity(poolAvailable < remainingOrder ? poolAvailable : remainingOrder)}', 
                        style: const TextStyle(color: orange, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: dark900,
                      hintText: '0.000',
                      hintStyle: const TextStyle(color: Colors.white24),
                      suffixText: widget.product.unit,
                      suffixStyle: const TextStyle(color: Colors.white38),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.blueAccent, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Allocation will draw from ${selectedPool['soNumber']} pool and add to current order.',
                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                onPressed: () async {
                  final amount = double.tryParse(amountController.text) ?? 0;
                  if (amount <= 0) return;
                  
                  if (amount > poolAvailable + 0.001) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not enough excess available')));
                    return;
                  }
                  
                  if (amount > remainingOrder + 0.001) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Exceeds target order limit')));
                    return;
                  }

                  Navigator.pop(context);
                  _performAllocation(selectedPool['soNumber'], amount);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: orange,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('ALLOCATE', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _performAllocation(String sourcePool, double amount) async {
    setState(() => _isSaving = true);
    try {
      final repository = context.read<DeliveryRepository>();
      
      // 1. Perform allocation via repository (saves local scan + notifies server)
      await repository.allocateExcess(
        sourceBulkSoNumber: sourcePool,
        targetSoNumber: widget.order.orderNumber,
        itemCode: widget.product.itemCode,
        amount: amount,
      );

      // 2. Add as a "virtual" scan in current list so it reflects immediately
      setState(() {
        _scans.insert(0, {
          'barcode': 'ALLOC-${sourcePool}-${DateTime.now().millisecondsSinceEpoch}',
          'originalBarcode': 'ALLOC-$sourcePool',
          'productCode': widget.product.itemCode,
          'scannedQty': amount,
          'manufacturedQty': amount,
          'weight': amount,
          'unit': widget.product.unit,
          'timestamp': DateTime.now().toIso8601String(),
          'status': 'A',
          'siteId': _selectedSite,
          'locationCode': 'BULK-ALLOC',
          'lot': _selectedLot,
          'soNumber': widget.order.orderNumber,
          'isSaved': true, // Marked as saved because allocateExcess already wrote to DB
        });
        _baseSessionScannedQty += amount;
      });

      // 3. Refresh pools
      await _fetchExcessPools();

      AudioService.instance.playSuccess();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully allocated ${widget.product.formatQuantity(amount)} KG from $sourcePool'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('Allocation Failed', e.toString());
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _statTile(String label, String value, {Color color = Colors.white}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w900)),
      ],
    );
  }

  Widget _buildStatusToggles() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: dark900, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: ['Q', 'A', 'R'].map((s) {
          final isSelected = _status == s;
          return GestureDetector(
            onTap: () => setState(() => _status = s),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: isSelected ? dark800 : Colors.transparent, borderRadius: BorderRadius.circular(8)),
              child: Text(s, style: TextStyle(color: isSelected ? _getStatusColor(s) : Colors.white24, fontWeight: FontWeight.bold)),
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _getStatusColor(String s) => s == 'A' ? Colors.greenAccent : (s == 'Q' ? Colors.blueAccent : Colors.redAccent);

  Widget _buildScannerOrSummary() {
    return _isScannerVisible ? _buildScannerSection() : _buildManualSummaryCard();
  }

  Widget _buildScannerSection() {
    return Stack(
      children: [
        Container(
          height: 320,
          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(20), border: Border.all(color: orange, width: 2)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: AppBarcodeScanner(onScan: _handleScan, themeColor: orange),
          ),
        ),
        if (_pendingScan != null) _buildScanSuccessOverlay(),
        Positioned(top: 12, right: 12, child: IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: _toggleScanner)),
      ],
    );
  }

  Widget _buildScanSuccessOverlay() {
    return Positioned.fill(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
          child: Container(
            color: darkBgColor.withValues(alpha: 0.85),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('SCAN SUCCESSFUL', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 2.0)),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(widget.product.formatQuantity(_pendingScan!['scannedQty']), style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Text(widget.product.unit, style: const TextStyle(color: Colors.white38, fontSize: 18)),
                  ],
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(child: TextButton(onPressed: () => setState(() => _pendingScan = null), child: const Text('DISCARD', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold)))),
                    const SizedBox(width: 12),
                    Expanded(child: ElevatedButton(onPressed: _savePendingScan, style: ElevatedButton.styleFrom(backgroundColor: orange, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('SAVE SCAN', style: TextStyle(fontWeight: FontWeight.bold)))),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const darkBgColor = Color(0xFF121212);

  Widget _buildManualSummaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: dark800, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
      child: Column(
        children: [
          const Text('Total Produced (All Time)', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            textBaseline: TextBaseline.alphabetic,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            children: [
              Text(
                widget.product.formatQuantity(widget.product.manufacturedQuantity + _baseSessionScannedQty + _cumulativeQty),
                style: const TextStyle(color: orange, fontSize: 56, fontWeight: FontWeight.w900),
              ),
              const SizedBox(width: 10),
              Text(widget.product.unit, style: const TextStyle(color: Colors.grey, fontSize: 22, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _toggleScanner,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('LAUNCH SCANNER', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: orange,
                    foregroundColor: Colors.black,
                    minimumSize: const Size(0, 64),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 1,
                child: InkWell(
                  onTap: () => _addManualQty(1.0),
                  borderRadius: BorderRadius.circular(32),
                  child: Container(
                    height: 64,
                    decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(32), border: Border.all(color: Colors.white10)),
                    child: const Center(child: Text('+1 KG', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14))),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: _showManualBarcodeDialog, child: const Text('Manual Barcode Entry', style: TextStyle(color: Colors.white24, fontSize: 12, decoration: TextDecoration.underline))),
        ],
      ),
    );
  }

  Widget _buildHistoryHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          const Text('SCAN HISTORY', style: TextStyle(color: Colors.white24, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
          const Spacer(),
          Text('${_scans.length} ITEMS', style: const TextStyle(color: orange, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildActionFooter() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 16),
      decoration: BoxDecoration(color: dark800, border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05)))),
      child: ElevatedButton(
        onPressed: (_isSaving || _scans.every((s) => s['isSaved'] == true)) ? null : _saveAndUpload,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          minimumSize: const Size(double.infinity, 60),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: _isSaving ? const CircularProgressIndicator(color: Colors.black) : const Text('SAVE ALL AND COMPLETE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.0)),
      ),
    );
  }

  void _showManualBarcodeDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: dark800,
        title: const Text('Manual Barcode', style: TextStyle(color: Colors.white)),
        content: TextField(controller: ctrl, style: const TextStyle(color: Colors.white), keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'Enter 13-digit code', hintStyle: TextStyle(color: Colors.white24))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () async { 
             final code = ctrl.text.trim();
             if (code.length != 13) {
                 _showErrorDialog('Invalid Barcode', 'Barcode must be exactly 13 digits.');
                 return;
             }
             final success = await _handleScan(code); 
             if (success && mounted) {
                 Navigator.pop(ctx);
                 if (_pendingScan != null) {
                     _savePendingScan();
                 }
             }
          }, child: const Text('Process')),
        ],
      ),
    );
  }

  Future<void> _showLocationPicker() async {
    final TextEditingController searchController = TextEditingController();
    List<LocationLookup> filteredLocations = List.from(_locations);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: darkBgColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.75,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              const Text('SELECT LOCATION', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.0)),
              const SizedBox(height: 20),
              TextField(
                controller: searchController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(hintText: 'Search...', hintStyle: const TextStyle(color: Colors.white24), prefixIcon: const Icon(Icons.search, color: Colors.white24), filled: true, fillColor: dark800, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
                onChanged: (v) { setModalState(() { filteredLocations = _locations.where((l) => l.fullInfo.toLowerCase().contains(v.toLowerCase())).toList(); }); },
              ),
              const SizedBox(height: 20),
              Expanded(
                child: ListView.builder(
                  itemCount: filteredLocations.length,
                  itemBuilder: (ctx, idx) {
                    final l = filteredLocations[idx];
                    final isSel = _selectedLocation?.location == l.location;
                    return ListTile(
                      title: Text(l.location ?? '', style: TextStyle(color: isSel ? orange : Colors.white, fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
                      subtitle: Text('${l.warehouseName} | ${l.locationTypeName}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      trailing: isSel ? const Icon(Icons.check_circle, color: orange) : null,
                      onTap: () { setState(() => _selectedLocation = l); Navigator.pop(context); },
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
