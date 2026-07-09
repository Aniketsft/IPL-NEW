import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:ui' show ImageFilter;
import 'package:uuid/uuid.dart';

import '../../../../core/utils/audio/audio_service.dart';
import '../../../../core/utils/barcode_scanner/barcode_processor.dart';
import '../../../../core/utils/barcode_scanner/hardware_scanner_mixin.dart';

import '../../domain/entities/sales_order.dart';
import '../../domain/entities/sales_order_detail.dart';
import '../../data/repositories/delivery_repository.dart';
import '../../domain/entities/location_lookup.dart';
import '../widgets/scan_item_card.dart';
import '../../data/local/local_database_helper.dart';
import '../../../../core/utils/app_ui.dart';

class ProductionTrackingScreen extends StatefulWidget {
  final SalesOrder order;
  final SalesOrderDetail product;
  final List<String> permissions;

  const ProductionTrackingScreen({
    super.key,
    required this.order,
    required this.product,
    required this.permissions,
  });

  @override
  State<ProductionTrackingScreen> createState() =>
      _ProductionTrackingScreenState();
}

class _ProductionTrackingScreenState extends State<ProductionTrackingScreen> with HardwareScannerMixin<ProductionTrackingScreen> {
  String _status = 'A'; // A: Approved, Q: Quality, R: Rejected
  double _cumulativeQty = 0.0; // Qty of pending (unsaved) scans this session
  double _cumulativeWeight = 0.0; // Weight (KG) of pending (unsaved) scans this session
  double _baseSessionScannedQty = 0.0; // Qty of successfully saved batch scans this session.
  double _baseSessionScannedWeight = 0.0; // Weight of successfully saved batch scans this session.
  List<Map<String, dynamic>> _scans = [];
  Map<String, dynamic>? _pendingScan;
  bool _isSaving = false;
  bool _isDirty = false;
  bool _isProcessingBarcode = false;
  bool _isLoadingHistory = false;
  bool _isMultiplierMode = false;
  List<String> _sites = [];
  String? _selectedSite;
  List<String> _lots = [];
  String? _selectedLot;
  List<LocationLookup> _locations = [];
  LocationLookup? _selectedLocation;
  final TextEditingController _lotController = TextEditingController();
  bool _isSettingsExpanded = false;
  List<Map<String, dynamic>> _excessPools = [];
  Map<String, dynamic>? _selectedBulkPool;
  bool _isLoadingExcess = false;
  double _tolerancePercentage = 0.0;
  double _localManufacturedQty = 0.0;
  double _localEaScannedQty = 0.0;

  @override
  void initState() {
    super.initState();
    _localManufacturedQty = widget.product.manufacturedQuantity;
    _localEaScannedQty = widget.product.eaScannedQuantity;
    _selectedSite = widget.product.site;
    _fetchInitialData();
    _fetchHistoricalScans();
    _fetchExcessPools();
  }

  @override
  void onHardwareScan(String data) {
    if (!widget.permissions.contains('manufacturing.all.update')) {
      AppUI.showErrorSnackBar(context: context, message: 'You do not have permission to scan items.');
      return;
    }
    _handleScan(data);
  }

  @override
  void dispose() {
    _lotController.dispose();
    super.dispose();
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
        AppUI.showWarningSnackBar(context: context, message: 'Error loading initial data: $e');
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
        final mappedScans = historicalScans
            .map(
              (s) => {
                'barcode': (s['barcode'] ?? s['Barcode']) ?? ((s['syncId'] != null && s['syncId'].toString().contains('-')) ? 'Synced Scan' : (s['syncId'] ?? 'SAVED')),
                'originalBarcode': (s['barcode'] ?? s['Barcode']) ?? '',
                'productCode': s['itemCode'] ?? widget.product.itemCode,
                'scannedQty':
                    (s['eaQuantity'] != null &&
                        (s['eaQuantity'] as num).toDouble() > 0)
                    ? (s['eaQuantity'] as num).toDouble()
                    : (s['scanAmountKg'] as num?)?.toDouble() ?? 0.0,
                'manufacturedQty':
                    (s['scanAmountKg'] as num?)?.toDouble() ?? 0.0,
                'weight': (s['scanAmountKg'] as num?)?.toDouble() ?? 0.0,
                'unit': widget.product.unit,
                'timestamp': s['createdAt'] ?? DateTime.now().toIso8601String(),
                'status': s['itemStatus'] ?? 'A',
                'siteId': _selectedSite,
                'locationCode': s['location'],
                'lot': s['lot'],
                'soNumber': widget.order.orderNumber,
                'syncId': s['syncId'],
                'isSaved': true,
              },
            )
            .toList();
        setState(() {
          // Append historical at the end (pending scans stay at top)
          _scans = [
            ..._scans.where((s) => s['isSaved'] != true),
            ...mappedScans,
          ];
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
        widget.order.orderNumber.startsWith('CUTS-')) {
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
          _excessPools = pools.map((p) => Map<String, dynamic>.from(p)).where((p) {
            final double available =
                (p['poolQty'] as num).toDouble() -
                (p['allocatedQty'] as num).toDouble();
            return available > 0.001;
          }).toList();
        });

        if (_excessPools.isNotEmpty && _selectedBulkPool == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _showPoolSelectionDialog();
            }
          });
        }
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
            _selectedLocation = iplch.isNotEmpty
                ? iplch.first
                : _locations.first;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        AppUI.showWarningSnackBar(context: context, message: 'Error loading locations: $e');
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
        AppUI.showWarningSnackBar(context: context, message: 'Error loading production sites: $e');
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

  Future<void> _saveBatch() async {
    if (!widget.permissions.contains('manufacturing.all.update')) return;
    if (_scans.isEmpty || _isSaving) return;
    // Implementation of batch saving logic would go here...
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
      String? globalLot;

      // Relaxed check: if it exists and looks like a valid lot, use it
      if (settings.dailyLotNumber != null &&
          settings.dailyLotNumber!.isNotEmpty) {
        globalLot = settings.dailyLotNumber;
      }

      if (mounted) {
        setState(() {
          _lots = lots;

          if (globalLot != null) {
            if (!_lots.contains(globalLot)) {
              _lots.insert(0, globalLot!);
            }
            _selectedLot = globalLot;
            _lotController.text = globalLot!;
          } else if (_selectedLot == null || !_lots.contains(_selectedLot)) {
            _selectedLot = _lots.isNotEmpty ? _lots.first : null;
            if (_selectedLot != null) _lotController.text = _selectedLot!;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        AppUI.showWarningSnackBar(context: context, message: 'Error loading lots: $e');
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



  void _removeScan(int index) {
    if (!widget.permissions.contains('manufacturing.all.update')) return;
    setState(() {
      _scans.removeAt(index);
    });
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
        _showErrorDialog(
          'Scan Pending',
          'Please save or discard the current scan first.',
        );
        return false;
      }

      final repository = context.read<DeliveryRepository>();
      final matchedProduct = await repository.getProductByBarcode(barcode);

      if (matchedProduct == null) {
        AudioService.instance.playError();
        HapticFeedback.heavyImpact();
        _showErrorDialog(
          'Barcode Not Found',
          'This barcode is not registered in the system.',
        );
        return false;
      }

      final String targetItemCode =
          matchedProduct[LocalDatabaseHelper.colProdCode] ?? '';
      final String targetUnit =
          matchedProduct[LocalDatabaseHelper.colProdSau] ?? 'KG';
      final double targetStdWeight =
          (matchedProduct[LocalDatabaseHelper.colProdStandardWeight] as num?)
              ?.toDouble() ??
          0.0;

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
            _showErrorDialog(
              'Wrong Product',
              'Scanned: ${result.itemCode}\nExpected: ${widget.product.itemCode}',
            );
            return false;
          }

          final isCutBulkOrder =
              widget.order.orderNumber.startsWith('BLK-') ||
              widget.order.orderNumber.startsWith('CUTS-');
          if (!isCutBulkOrder && _status == 'A') {
            final bool isEA = widget.product.unit.toUpperCase() == 'EA' || widget.product.unit.toUpperCase() == 'PCS';
            final double tolerance = isEA ? 0.0 : _tolerancePercentage;
            final double effectiveLimit = widget.product.quantity * (1 + tolerance / 100);

            final double currentTotal = isEA
                ? (_localEaScannedQty + _baseSessionScannedQty + _cumulativeQty)
                : (_localManufacturedQty + _baseSessionScannedWeight + _cumulativeWeight);

            final double remaining = effectiveLimit - currentTotal;
            final double scanAmount = isEA ? result.scannedQty : result.manufacturedQty;

            if (scanAmount > remaining + 0.001) {
              AudioService.instance.playError();
              HapticFeedback.heavyImpact();
              _showErrorDialog(
                'Limit Exceeded',
                'Scanning ${widget.product.formatQuantity(scanAmount)} would exceed the order limit${isEA ? '' : ' (with ' + _tolerancePercentage.toString() + '% tolerance)'}.',
              );
              return false;
            }
          }

          final pending = {
            'barcode': result.processedBarcode,
            'originalBarcode': result.originalBarcode,
            'productCode': result.itemCode,
            'scannedQty': result.scannedQty,
            'manufacturedQty': result.manufacturedQty,
            'weight': result.manufacturedQty,
            'unit': targetUnit,
            'timestamp': DateTime.now().toIso8601String(),
          };

          if (_isMultiplierMode) {
            _showMultiplierPrompt(pending);
          } else {
            setState(() {
              pending['syncId'] = const Uuid().v4();
              _pendingScan = pending;
              // --- Instant Save (Removes 2FA / Confirmation) ---
              _savePendingScan();
            });
          }

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
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      return false;
    } finally {
      if (mounted) setState(() => _isProcessingBarcode = false);
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.amber),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(color: Colors.white))),
          ],
        ),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmDelete() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange),
                SizedBox(width: 8),
                Text('Confirm Delete', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: const Text(
              'Are you sure you want to delete this scan line?',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  'CANCEL',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                ),
                child: const Text(
                  'DELETE',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _savePendingScan() {
    if (_pendingScan == null) return;

    if (_selectedBulkPool != null) {
      final isEA = widget.product.unit.toUpperCase() == 'EA' || widget.product.unit.toUpperCase() == 'PCS';
      final double amount = isEA 
          ? (_pendingScan!['scannedQty'] as num?)?.toDouble() ?? 0.0
          : (_pendingScan!['manufacturedQty'] as num?)?.toDouble() ?? 0.0;
      
      final double poolAvailable =
          (_selectedBulkPool!['poolQty'] as num).toDouble() -
          (_selectedBulkPool!['allocatedQty'] as num).toDouble();

      if (amount > poolAvailable + 0.001) {
        AudioService.instance.playError();
        HapticFeedback.heavyImpact();
        AppUI.showWarningSnackBar(context: context, message: 'Scan amount exceeds available pool excess');
        return;
      }

      setState(() {
        _selectedBulkPool!['allocatedQty'] = (_selectedBulkPool!['allocatedQty'] as num).toDouble() + amount;
      });
    }

    setState(() {
      final scanWithMetadata = Map<String, dynamic>.from(_pendingScan!);
      scanWithMetadata['status'] = _status;
      scanWithMetadata['siteId'] = _selectedSite;
      scanWithMetadata['locationCode'] = _selectedLocation?.location;
      scanWithMetadata['lot'] = _selectedLot;
      scanWithMetadata['soNumber'] = widget.order.orderNumber;
      scanWithMetadata['productCode'] = widget.product.itemCode;
      scanWithMetadata['isSaved'] = false;
      if (_selectedBulkPool != null) {
        scanWithMetadata['sourceBulkSoNumber'] = _selectedBulkPool!['soNumber'];
      }

      _scans.insert(0, scanWithMetadata);
      if (_status == 'A') {
        _cumulativeQty += _pendingScan!['scannedQty'] as double;
        _cumulativeWeight += (_pendingScan!['manufacturedQty'] as num?)?.toDouble() ?? 0.0;
        _isDirty = true;
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

  void _showMultiplierPrompt(Map<String, dynamic> pendingScan) {
    final TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final orange = theme.primaryColor;
        
        return AlertDialog(
          backgroundColor: theme.colorScheme.surface,
          title: Text('Multiplier Mode', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Enter the number of times to multiply this scan record:', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  labelText: 'Quantity',
                  labelStyle: TextStyle(color: orange),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: orange)),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.black26)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('CANCEL', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
            ),
            ElevatedButton(
              onPressed: () {
                final int? count = int.tryParse(controller.text);
                if (count != null && count > 0) {
                  Navigator.pop(context);
                  _applyMultiplier(pendingScan, count);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: orange),
              child: const Text('CONFIRM', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _applyMultiplier(Map<String, dynamic> pendingScan, int count) {
    final isEA = widget.product.unit.toUpperCase() == 'EA' || widget.product.unit.toUpperCase() == 'PCS';
    final double amountPerScan = isEA 
        ? (pendingScan['scannedQty'] as num?)?.toDouble() ?? 0.0
        : (pendingScan['manufacturedQty'] as num?)?.toDouble() ?? 0.0;
    final double totalAmount = amountPerScan * count;

    final bool isCutBulkOrder = widget.order.orderNumber.startsWith('BLK-') || widget.order.orderNumber.startsWith('CUTS-');
    if (!isCutBulkOrder && _status == 'A') {
      final double tolerance = isEA ? 0.0 : _tolerancePercentage;
      final double effectiveLimit = widget.product.quantity * (1 + tolerance / 100);
      final double currentTotal = isEA
          ? (_localEaScannedQty + _baseSessionScannedQty + _cumulativeQty)
          : (_localManufacturedQty + _baseSessionScannedWeight + _cumulativeWeight);
      final double remaining = effectiveLimit - currentTotal;

      if (totalAmount > remaining + 0.001) {
        AudioService.instance.playError();
        HapticFeedback.heavyImpact();
        AppUI.showWarningSnackBar(context: context, message: 'Total multiplied amount would exceed the order limit');
        return;
      }
    }

    if (_selectedBulkPool != null) {
      final double poolAvailable =
          (_selectedBulkPool!['poolQty'] as num).toDouble() -
          (_selectedBulkPool!['allocatedQty'] as num).toDouble();

      if (totalAmount > poolAvailable + 0.001) {
        AudioService.instance.playError();
        HapticFeedback.heavyImpact();
        AppUI.showWarningSnackBar(context: context, message: 'Total multiplied amount exceeds available pool excess');
        return;
      }

      setState(() {
        _selectedBulkPool!['allocatedQty'] = (_selectedBulkPool!['allocatedQty'] as num).toDouble() + totalAmount;
      });
    }

    setState(() {
      for (int i = 0; i < count; i++) {
        final scanWithMetadata = Map<String, dynamic>.from(pendingScan);
        scanWithMetadata['status'] = _status;
        scanWithMetadata['siteId'] = _selectedSite;
        scanWithMetadata['locationCode'] = _selectedLocation?.location;
        scanWithMetadata['lot'] = _selectedLot;
        scanWithMetadata['soNumber'] = widget.order.orderNumber;
        scanWithMetadata['productCode'] = widget.product.itemCode;
        scanWithMetadata['isSaved'] = false;
        scanWithMetadata['syncId'] = const Uuid().v4();
        if (_selectedBulkPool != null) {
          scanWithMetadata['sourceBulkSoNumber'] = _selectedBulkPool!['soNumber'];
        }
        
        _scans.insert(0, scanWithMetadata);
        if (_status == 'A') {
          _cumulativeQty += scanWithMetadata['scannedQty'] as double;
          _cumulativeWeight += (scanWithMetadata['manufacturedQty'] as num?)?.toDouble() ?? 0.0;
          _isDirty = true;
        }
      }
      _pendingScan = null;
    });
    AudioService.instance.playSuccess();
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$count records generated'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _addManualQty(double qty) {
    final isCutBulkOrder =
        widget.order.orderNumber.startsWith('BLK-') ||
        widget.order.orderNumber.startsWith('CUTS-');
    if (!isCutBulkOrder) {
      final bool isEA = widget.product.unit.toUpperCase() == 'EA';
      final double tolerance = isEA ? 0.0 : _tolerancePercentage;
      final double effectiveLimit =
          widget.product.quantity * (1 + tolerance / 100);

      final remaining =
          effectiveLimit -
          _localManufacturedQty -
          _baseSessionScannedQty -
          _cumulativeQty;
      if (qty > remaining + 0.001) {
        AudioService.instance.playError();
        HapticFeedback.heavyImpact();
        _showErrorDialog(
          'Limit Exceeded',
          'Adding ${qty.toStringAsFixed(3)} would exceed the limit${isEA ? '' : ' (with ' + _tolerancePercentage.toString() + '% tolerance)'}.',
        );
        return;
      }
    }

    setState(() {
      final manualScan = {
        'barcode':
            'MANUAL-${qty.toInt()}KG-${DateTime.now().millisecondsSinceEpoch}',
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
        'syncId': Uuid().v4(),
      };
      _scans.insert(0, manualScan);
      if (_status == 'A') _cumulativeQty += qty;
    });

    AudioService.instance.playSuccess();
    HapticFeedback.lightImpact();
  }

  Future<void> _saveAndUpload() async {
    final pendingScans = _scans.where((s) => s['isSaved'] != true).toList();
    if (pendingScans.isEmpty && !_isDirty) {
      AppUI.showWarningSnackBar(context: context, message: 'No new scans to save');
      return;
    }
    if (_selectedLocation == null) {
      AppUI.showWarningSnackBar(context: context, message: 'Select target location');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final repository = context.read<DeliveryRepository>();

      // Enrich all pending scans with current location/lot before saving
      final List<Map<String, dynamic>> enrichedScans = [];
      for (final s in pendingScans) {
        final copy = Map<String, dynamic>.from(s);
        copy['locationCode'] = _selectedLocation?.location;
        copy['lot'] = _selectedLot;
        copy['soNumber'] = widget.order.orderNumber;
        copy['productCode'] = widget.product.itemCode;
        if (copy['syncId'] == null) {
          copy['syncId'] = const Uuid().v4();
        }
        enrichedScans.add(copy);

        if (copy['sourceBulkSoNumber'] != null) {
          final isEA = widget.product.unit.toUpperCase() == 'EA' || widget.product.unit.toUpperCase() == 'PCS';
          final double amount = (copy['manufacturedQty'] as num?)?.toDouble() ?? (copy['weight'] as num?)?.toDouble() ?? 0.0;
          final double scannedAmount = isEA ? ((copy['scannedQty'] as num?)?.toDouble() ?? 0.0) : amount;
          
          final negativeRecord = {
            'soNumber': copy['sourceBulkSoNumber'],
            'productCode': widget.product.itemCode,
            'scannedQty': -scannedAmount,
            'manufacturedQty': -amount,
            'weight': -amount,
            'timestamp': DateTime.now().toIso8601String(),
            'status': 'A',
            'locationCode': _selectedLocation?.location ?? 'BULK-ALLOC',
            'lot': _selectedLot,
            'siteId': _selectedSite,
            'barcode': 'ALLOC-OUT-${copy['barcode'] ?? copy['syncId']}',
            'isSaved': false, // Batch save forces them anyway in the DB
            'syncId': const Uuid().v4(),
            'unit': widget.product.unit,
          };
          enrichedScans.add(negativeRecord);
        }
      }

      await repository.ensureSalesOrderDetailExists(widget.product);
      await repository.saveProductionScansBatch(enrichedScans);

      if (mounted) {
        setState(() {
          // Mark all pending scans as saved in place
          for (int i = 0; i < _scans.length; i++) {
            if (_scans[i]['isSaved'] != true) {
              _scans[i] = Map<String, dynamic>.from(_scans[i])
                ..['isSaved'] = true;
            }
          }
          // Shift the pending quantity naturally into the core persistent memory for this screen session
          _baseSessionScannedQty += _cumulativeQty;
          _baseSessionScannedWeight += _cumulativeWeight;
          _cumulativeQty = 0.0;
          _cumulativeWeight = 0.0;
          _isDirty = false;
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
      if (mounted)
        AppUI.showErrorSnackBar(context: context, message: 'Failed to save: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, dynamic) {
        if (!didPop) {
          Navigator.pop(context, _baseSessionScannedQty > 0);
        }
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(
            'Production Scan',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
              letterSpacing: 1.0,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.home_rounded, color: orange, size: 24),
              tooltip: 'Back to Home',
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
            ),
            const SizedBox(width: 8),
          ],
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
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final scan = _scans[index];
                          final bool isSaved = scan['isSaved'] == true;
                          return ScanItemCard(
                            lineNumber: _scans.length - index,
                            scan: scan,
                            unit: widget.product.unit,
                            canDelete: scan['status'] != 'REVERSED' && scan['status'] != 'DELETED_ORIGINAL',
                            onDelete: () async {
                              final confirmed = await _confirmDelete();
                              if (confirmed && mounted) {
                                try {
                                  final db = LocalDatabaseHelper.instance;
                                  
                                  // --- AUDIT-PRESERVING REVERSAL ---
                                  final syncId = scan['syncId']?.toString();
                                  final repository = context.read<DeliveryRepository>();
                                  
                                  if (syncId != null) {
                                    if (isSaved) {
                                      // 1. Mark original as DELETED_ORIGINAL in DB
                                      await db.updateScanStatusBySyncId(syncId, 'DELETED_ORIGINAL');

                                      // 2. Prepare and persist NEGATIVE LINE (Reversal) for audit and server sync
                                      final reversalScan = Map<String, dynamic>.from(scan);
                                      reversalScan['scannedQty'] = -((scan['scannedQty'] as num?)?.toDouble() ?? 0.0);
                                      reversalScan['manufacturedQty'] = -((scan['manufacturedQty'] as num?)?.toDouble() ?? 0.0);
                                      reversalScan['weight'] = -((scan['weight'] as num?)?.toDouble() ?? 0.0);
                                      reversalScan['status'] = 'REVERSED';
                                      reversalScan['syncId'] = 'REV-${const Uuid().v4()}';
                                      reversalScan['isSaved'] = true;
                                      reversalScan['timestamp'] = DateTime.now().toIso8601String();
                                      
                                      await repository.saveProductionScansBatch([reversalScan]);

                                      final barcodeStr = scan['barcode']?.toString() ?? '';
                                      final dummyNegativeBarcode = 'ALLOC-OUT-$barcodeStr';
                                      
                                      final database = await db.database;
                                      final matchingOuts = await database.query(
                                        LocalDatabaseHelper.tableScans,
                                        where: "${LocalDatabaseHelper.columnBarcode} = ? AND ${LocalDatabaseHelper.columnItemStatus} != 'DELETED_ORIGINAL'",
                                        whereArgs: [dummyNegativeBarcode],
                                      );

                                      if (matchingOuts.isNotEmpty) {
                                          await database.rawUpdate(
                                            "UPDATE ${LocalDatabaseHelper.tableScans} SET ${LocalDatabaseHelper.columnItemStatus} = 'DELETED_ORIGINAL' WHERE ${LocalDatabaseHelper.columnBarcode} = ?",
                                            [dummyNegativeBarcode],
                                          );

                                          final dummyReversalScan = Map<String, dynamic>.from(reversalScan);
                                          dummyReversalScan['soNumber'] = matchingOuts.first[LocalDatabaseHelper.columnSoNumber];
                                          dummyReversalScan['barcode'] = 'REV-$dummyNegativeBarcode';
                                          dummyReversalScan['scannedQty'] = ((scan['scannedQty'] as num?)?.toDouble() ?? 0.0);
                                          dummyReversalScan['manufacturedQty'] = ((scan['manufacturedQty'] as num?)?.toDouble() ?? 0.0);
                                          dummyReversalScan['weight'] = ((scan['weight'] as num?)?.toDouble() ?? 0.0);
                                          dummyReversalScan['syncId'] = 'REV-${const Uuid().v4()}';
                                          
                                          await repository.saveProductionScansBatch([dummyReversalScan]);
                                      }

                                      // 3. Update local session state directly (deduction handled by sum in DB automatically)
                                      final weightToDeduct = (scan['manufacturedQty'] as num?)?.toDouble() ?? 0.0;
                                      final eaToDeduct = (scan['scannedQty'] as num?)?.toDouble() ?? 0.0;

                                      if (mounted) {
                                        setState(() {
                                          // Update original line in local list to grey it out
                                          _scans[index] = Map<String, dynamic>.from(_scans[index])
                                            ..['status'] = 'DELETED_ORIGINAL';
                                          
                                          // Add reversal line to the list for visual confirmation
                                          _scans.insert(0, reversalScan);
                                          
                                          _localManufacturedQty -= weightToDeduct;
                                          _localEaScannedQty -= eaToDeduct;
                                          _isDirty = true;
                                        });
                                      }
                                    } else {
                                      // For unsaved (pending) scans, hard delete is appropriate
                                      await db.deleteScanBySyncId(syncId);
                                      if (mounted) {
                                        setState(() {
                                          _scans.removeAt(index);
                                          _isDirty = true;
                                          if (scan['status'] == 'A') {
                                            _cumulativeQty -= (scan['scannedQty'] as num?)?.toDouble() ?? 0.0;
                                            _cumulativeWeight -= (scan['manufacturedQty'] as num?)?.toDouble() ?? 0.0;
                                          }
                                          if (scan['sourceBulkSoNumber'] != null && _selectedBulkPool != null && _selectedBulkPool!['soNumber'] == scan['sourceBulkSoNumber']) {
                                              final isEA = widget.product.unit.toUpperCase() == 'EA' || widget.product.unit.toUpperCase() == 'PCS';
                                              final amount = isEA ? ((scan['scannedQty'] as num?)?.toDouble() ?? 0.0) : ((scan['manufacturedQty'] as num?)?.toDouble() ?? 0.0);
                                              _selectedBulkPool!['allocatedQty'] = (_selectedBulkPool!['allocatedQty'] as num).toDouble() - amount;
                                          }
                                        });
                                      }
                                    }
                                  }

                                  // Always log deletion so backend can process it if synced
                                  await db.insertOfflineAuditLog(
                                    entity: 'ProductionScan',
                                    action: 'DELETE',
                                    payload: jsonEncode({
                                      'barcode': scan['barcode'],
                                      'syncId': scan['syncId'],
                                      'soNumber': widget.order.orderNumber,
                                      'productCode': widget.product.itemCode,
                                      'manufacturedQty': scan['manufacturedQty'],
                                      'eaQuantity': (widget.product.unit == 'EA' || widget.product.unit == 'PCS')
                                          ? (scan['scannedQty'] ?? 0.0)
                                          : 0.0,
                                      'timestamp': DateTime.now().toIso8601String(),
                                    }),
                                  );
                                  await _fetchExcessPools();
                                } catch (e) {
                                  debugPrint('Failed to log deletion: $e');
                                }
                              }
                            },
                          );
                        }, childCount: _scans.length),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;
    final double availablePool = totalAvailableExcess;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.08),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  widget.order.customerName,
                  style: TextStyle(
                    color: orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              if (availablePool > 0) ...[
                const SizedBox(width: 12),
                _bulkPoolBadge(availablePool),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            widget.product.description,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
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
        color: Colors.blue.shade900.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inventory_2_outlined, color: Colors.white, size: 12),
          const SizedBox(width: 6),
          Text(
            'POOL: ${amount.toStringAsFixed(2)} ${widget.product.unit}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(String label) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isDark ? Colors.grey : Colors.grey[600],
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildSettingsCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.08),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () =>
                setState(() => _isSettingsExpanded = !_isSettingsExpanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.settings_outlined, color: orange, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'PRODUCTION SETTINGS',
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  Icon(
                    _isSettingsExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ],
              ),
            ),
          ),
          if (_isSettingsExpanded) ...[
            Divider(color: isDark ? Colors.white10 : Colors.black12, height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildDropdownField(
                    'Production Site',
                    _selectedSite,
                    _sites,
                    _onSiteChanged,
                  ),
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

  Widget _buildDropdownField(
    String label,
    String? value,
    List<String> items,
    Function(String?) onChanged,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isDark ? Colors.grey : Colors.black54,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              dropdownColor: theme.cardColor,
              value: value,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 14,
              ),
              items: items
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLotField() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Production Lot',
          style: TextStyle(
            color: isDark ? Colors.grey : Colors.black54,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Autocomplete<String>(
          key: ValueKey(
            'lot_auto_${_lotController.text}',
          ), // Force rebuild if text changes from empty
          optionsBuilder: (v) =>
              v.text.isEmpty ? _lots : _lots.where((s) => s.contains(v.text)),
          onSelected: (s) => setState(() {
            _selectedLot = s;
            _lotController.text = s;
          }),
          fieldViewBuilder: (ctx, ctrl, node, onSub) {
            if (ctrl.text != _lotController.text &&
                _lotController.text.isNotEmpty &&
                ctrl.text.isEmpty) {
              ctrl.text = _lotController.text;
            }
            return TextField(
              controller: ctrl,
              focusNode: node,
              onChanged: (val) {
                _selectedLot = val;
                _lotController.text = val;
              },
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: theme.scaffoldBackgroundColor,
                hintText: 'Enter or search lot',
                hintStyle: TextStyle(
                  color: isDark ? Colors.white24 : Colors.black26,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: isDark ? Colors.white10 : Colors.black12,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: isDark ? Colors.white10 : Colors.black12,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildLocationField() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Target Location',
          style: TextStyle(
            color: isDark ? Colors.grey : Colors.black54,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: _showLocationPicker,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.black12,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedLocation?.location ?? 'Select Location',
                    style: TextStyle(
                      color: _selectedLocation == null
                          ? (isDark ? Colors.white24 : Colors.black26)
                          : (isDark ? Colors.white : Colors.black87),
                      fontSize: 14,
                    ),
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down,
                  color: isDark ? Colors.grey : Colors.grey[600],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressAndStatus() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    final bool isEA = widget.product.unit.toUpperCase() == 'EA';
    final double tolerance = isEA ? 0.0 : _tolerancePercentage;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _statTile(
                'Max Allowed',
                '${widget.product.formatQuantity((widget.product.unit.toUpperCase() == 'EA' || widget.product.unit.toUpperCase() == 'PCS') ? widget.product.quantity : (widget.product.quantity * (1 + tolerance / 100)))} ${widget.product.unit}',
                isDark,
              ),
              _statTile(
                'Scanned',
                '${widget.product.formatQuantity((widget.product.unit.toUpperCase() == 'EA' || widget.product.unit.toUpperCase() == 'PCS') ? (_localEaScannedQty + _baseSessionScannedQty + _cumulativeQty) : (_localManufacturedQty + _baseSessionScannedWeight + _cumulativeWeight))} ${widget.product.unit}',
                isDark,
                color: orange,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: isDark ? Colors.white10 : Colors.black12, height: 1),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                'STATUS',
                style: TextStyle(
                  color: isDark ? Colors.grey : Colors.black54,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              _buildStatusToggles(),
            ],
          ),
          if (_excessPools.isNotEmpty) ...[
            const SizedBox(height: 16),
            Divider(color: isDark ? Colors.white10 : Colors.black12, height: 1),
            const SizedBox(height: 16),
            _buildExcessAllocationButton(),
          ],
        ],
      ),
    );
  }

  Widget _buildExcessAllocationButton() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: orange.withValues(alpha: 0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _showPoolSelectionDialog,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.layers_outlined, color: orange, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedBulkPool == null ? 'SELECT BULK POOL' : 'ACTIVE POOL: ${_selectedBulkPool!['soNumber']}',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _selectedBulkPool == null 
                          ? 'No pool selected. Scanning independently.' 
                          : 'Available: ${widget.product.formatQuantity((_selectedBulkPool!['poolQty'] as num).toDouble() - (_selectedBulkPool!['allocatedQty'] as num).toDouble())} ${widget.product.unit}',
                        style: TextStyle(
                          color: orange,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios, color: orange, size: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPoolSelectionDialog() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;
    
    final List<Map<String, dynamic>?> poolOptions = [null, ..._excessPools];
    Map<String, dynamic>? localSelected = _selectedBulkPool;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: theme.cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(Icons.layers_outlined, color: orange),
                const SizedBox(width: 12),
                Text(
                  'Select Bulk Pool',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Scans will be deducted from the selected pool.',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: theme.scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.white10 : Colors.black12,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<Map<String, dynamic>?>(
                      isExpanded: true,
                      dropdownColor: theme.cardColor,
                      value: localSelected,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 14,
                      ),
                      items: poolOptions.map((p) {
                        if (p == null) {
                          return const DropdownMenuItem<Map<String, dynamic>?>(
                            value: null,
                            child: Text('None (Independent Scan)'),
                          );
                        }
                        final available = (p['poolQty'] as num).toDouble() - (p['allocatedQty'] as num).toDouble();
                        return DropdownMenuItem<Map<String, dynamic>?>(
                          value: p,
                          child: Text(
                            '${p['soNumber']} (${widget.product.formatQuantity(available)} left)',
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setDialogState(() => localSelected = val);
                      },
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'CANCEL',
                  style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _selectedBulkPool = localSelected;
                  });
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('CONFIRM', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _statTile(String label, String value, bool isDark, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isDark ? Colors.grey : Colors.black54,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color ?? (isDark ? Colors.white : Colors.black87),
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusToggles() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: ['Q', 'A', 'R'].map((s) {
          final isSelected = _status == s;
          return GestureDetector(
            onTap: () => setState(() => _status = s),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? theme.cardColor : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                s,
                style: TextStyle(
                  color: isSelected
                      ? _getStatusColor(s)
                      : (isDark ? Colors.white24 : Colors.black26),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _getStatusColor(String s) {
    if (s == 'A') return Colors.green[400]!;
    if (s == 'Q') return Colors.blue[400]!;
    return Colors.red[400]!;
  }

  Widget _buildScannerOrSummary() {
    return Stack(
      children: [
        _buildManualSummaryCard(),
        if (_pendingScan != null) _buildScanSuccessOverlay(),
      ],
    );
  }



  Widget _buildScanSuccessOverlay() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    return Positioned.fill(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
          child: Container(
            color: (isDark ? Colors.black : Colors.white).withValues(
              alpha: 0.85,
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'SCAN SUCCESSFUL',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.product.formatQuantity(
                        _pendingScan!['scannedQty'],
                      ),
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 42,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.product.unit,
                      style: TextStyle(
                        color: isDark ? Colors.white38 : Colors.black38,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => setState(() => _pendingScan = null),
                        child: Text(
                          'DISCARD',
                          style: TextStyle(
                            color: isDark ? Colors.white54 : Colors.black54,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _savePendingScan,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: orange,
                          foregroundColor: isDark ? Colors.black : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'SAVE SCAN',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
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

  Widget _buildManualSummaryCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.05),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: orange.withValues(alpha: 0.06),
                  blurRadius: 18,
                  spreadRadius: -2,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Column(
        children: [
          // ── Quantity display ──────────────────────────────────
          Text(
            (widget.product.unit.toUpperCase() == 'EA' ||
                widget.product.unit.toUpperCase() == 'PCS')
                ? 'Total EA (All Time)'
                : 'Total Produced (All Time)',
            style: TextStyle(
              color: isDark ? Colors.grey : Colors.grey[600],
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            decoration: BoxDecoration(
              color: orange.withValues(alpha: isDark ? 0.10 : 0.06),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              textBaseline: TextBaseline.alphabetic,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      widget.product.formatQuantity(
                        (widget.product.unit.toUpperCase() == 'EA' ||
                                widget.product.unit.toUpperCase() == 'PCS')
                            ? (_localEaScannedQty +
                                _baseSessionScannedQty +
                                _cumulativeQty)
                            : (_localManufacturedQty +
                                _baseSessionScannedQty +
                                _cumulativeQty),
                      ),
                      style: TextStyle(
                        color: orange,
                        fontSize: 56,
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  widget.product.unit + 
                  ((widget.product.unit.toUpperCase() == 'EA' || widget.product.unit.toUpperCase() == 'PCS') 
                   ? ' (${widget.product.formatQuantity(_localManufacturedQty + _baseSessionScannedWeight + _cumulativeWeight)} KG)' 
                   : ''),
                  style: TextStyle(
                    color: isDark ? Colors.white38 : Colors.grey[600],
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── Primary: Scan instruction text ──
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.barcode_reader, size: 18, color: orange.withValues(alpha: 0.7)),
              const SizedBox(width: 8),
              Text(
                'Scan product to track',
                style: TextStyle(
                  color: isDark ? Colors.white60 : Colors.black54,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  setState(() {
                    _isMultiplierMode = !_isMultiplierMode;
                  });
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: _isMultiplierMode ? orange : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _isMultiplierMode ? orange : (isDark ? Colors.white38 : Colors.black26),
                    ),
                  ),
                  child: Icon(
                    Icons.check,
                    size: 16,
                    color: _isMultiplierMode ? Colors.white : (isDark ? Colors.white54 : Colors.black54),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Secondary row: Manual Entry ─────────────
          Row(
            children: [
              // Manual Entry pill
              Expanded(
                child: InkWell(
                  onTap: _showManualBarcodeDialog,
                  borderRadius: BorderRadius.circular(32),
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.12)
                            : Colors.black.withValues(alpha: 0.10),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.keyboard_alt_outlined,
                          color: isDark ? Colors.white38 : Colors.black38,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Manual',
                          style: TextStyle(
                            color: isDark ? Colors.white54 : Colors.black54,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryHeader() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Text(
            'SCAN HISTORY',
            style: TextStyle(
              color: isDark ? Colors.white38 : Colors.black38,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const Spacer(),
          Text(
            '${_scans.length} ITEMS',
            style: TextStyle(
              color: theme.primaryColor,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionFooter() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(
          top: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
        ),
      ),
      child: ElevatedButton(
        onPressed: (_isSaving || (!(_isDirty || _scans.any((s) => s['isSaved'] == false))))
            ? null
            : _saveAndUpload,
        style: ElevatedButton.styleFrom(
          backgroundColor: isDark ? Colors.white : orange,
          foregroundColor: isDark ? Colors.black : Colors.white,
          minimumSize: const Size(double.infinity, 60),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: isDark ? 0 : 4,
        ),
        child: _isSaving
            ? CircularProgressIndicator(
                color: isDark ? Colors.black : Colors.white,
              )
            : const Text(
                'SAVE ALL AND COMPLETE',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: 1.0,
                ),
              ),
      ),
    );
  }

  void _showManualBarcodeDialog() {
    if (!widget.permissions.contains('manufacturing.all.update')) {
      AppUI.showErrorSnackBar(context: context, message: 'You do not have permission to add manual scans.');
      return;
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final ctrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Manual Barcode',
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        content: TextField(
          controller: ctrl,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          keyboardType: TextInputType.number,
          maxLength: 13,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            hintText: 'Enter 13-digit code',
            counterText: '',
            hintStyle: TextStyle(
              color: isDark ? Colors.white38 : Colors.black38,
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: isDark ? Colors.white10 : Colors.black12,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final code = ctrl.text.trim();
              if (code.length != 13) {
                _showErrorDialog(
                  'Invalid Barcode',
                  'Barcode must be exactly 13 digits.',
                );
                return;
              }
              Navigator.pop(ctx);
              await _handleScan(code);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primaryColor,
            ),
            child: const Text('Process', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _showLocationPicker() async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;
    final TextEditingController searchController = TextEditingController();
    List<LocationLookup> filteredLocations = List.from(_locations);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.75,
          padding: const EdgeInsets.all(20),
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
              const SizedBox(height: 20),
              Text(
                'SELECT LOCATION',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: searchController,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  hintText: 'Search...',
                  hintStyle: TextStyle(
                    color: isDark ? Colors.white24 : Colors.black26,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                  filled: true,
                  fillColor: theme.cardColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 0,
                  ),
                ),
                onChanged: (v) {
                  setModalState(() {
                    filteredLocations = _locations
                        .where(
                          (l) => l.fullInfo.toLowerCase().contains(
                            v.toLowerCase(),
                          ),
                        )
                        .toList();
                  });
                },
              ),
              const SizedBox(height: 20),
              Expanded(
                child: ListView.builder(
                  itemCount: filteredLocations.length,
                  itemBuilder: (ctx, idx) {
                    final l = filteredLocations[idx];
                    final isSel = _selectedLocation?.location == l.location;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      title: Text(
                        l.location ?? '',
                        style: TextStyle(
                          color: isSel
                              ? orange
                              : (isDark ? Colors.white : Colors.black87),
                          fontWeight: isSel
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        '${l.warehouseName} | ${l.locationTypeName}',
                        style: TextStyle(
                          color: isDark ? Colors.white38 : Colors.black45,
                          fontSize: 12,
                        ),
                      ),
                      trailing: isSel
                          ? Icon(Icons.check_circle, color: orange)
                          : null,
                      onTap: () {
                        setState(() => _selectedLocation = l);
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
