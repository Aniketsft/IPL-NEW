import 'package:flutter/material.dart';
import 'package:enterprise_auth_mobile/core/widgets/industrial_module_layout.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/widgets/label_qr_generator.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/widgets/label_printing_handler.dart';
import 'package:enterprise_auth_mobile/core/utils/barcode_scanner/hardware_scanner_mixin.dart';

enum AggregationMode { crate, palette }

class QrLabelScreen extends StatefulWidget {
  const QrLabelScreen({super.key});

  @override
  State<QrLabelScreen> createState() => _QrLabelScreenState();
}

class _QrLabelScreenState extends State<QrLabelScreen> with HardwareScannerMixin<QrLabelScreen> {
  AggregationMode _mode = AggregationMode.crate;
  
  // Crate State
  String? _crateSoNumber;
  final List<Map<String, String>> _crateItems = [];
  
  // Palette State (Grouped by SO)
  final Map<String, List<Map<String, String>>> _paletteGroups = {};

  double get _totalWeight {
    if (_mode == AggregationMode.crate) {
      return _crateItems.fold(0.0, (sum, item) => sum + (double.tryParse(item['weight'] ?? '0') ?? 0.0));
    } else {
      double total = 0.0;
      _paletteGroups.forEach((so, items) {
        total += items.fold(0.0, (sum, item) => sum + (double.tryParse(item['weight'] ?? '0') ?? 0.0));
      });
      return total;
    }
  }

  @override
  void onHardwareScan(String data) {
    final parsedData = LabelQrGenerator.parse(data);
    if (parsedData.isEmpty) return;

    final type = parsedData['type'];
    
    if (_mode == AggregationMode.crate) {
      if (type != 'ITEM') {
        _showError('CRATE MODE: Only scan individual products!');
        return;
      }
    } else if (_mode == AggregationMode.palette) {
      if (type != 'CRATE') {
        _showError('PALETTE MODE: Only scan Master Crate labels!');
        return;
      }
    }

    setState(() {
      if (_mode == AggregationMode.crate) {
        _handleCrateScan(parsedData);
      } else {
        _handlePaletteScan(parsedData);
      }
    });
  }

  void _handleCrateScan(Map<String, String> data) {
    final so = data['soNumber'];
    if (_crateSoNumber == null) {
      _crateSoNumber = so;
      _crateItems.add(data);
    } else if (_crateSoNumber != so) {
      _showError('SO MISMATCH: This crate is for $_crateSoNumber. You scanned $so.');
    } else {
      _crateItems.add(data);
    }
  }

  void _handlePaletteScan(Map<String, String> data) {
    if (data['type'] == 'CRATE') {
      final manifest = data['manifest'] ?? '';
      final so = data['soNumber'] ?? 'UNKNOWN';
      final customer = data['customer'] ?? 'N/A';
      final delivery = data['delivery'] ?? 'N/A';
      final unit = data['unit'] ?? 'KG';
      
      final items = manifest.split(',');
      for (var itemStr in items) {
        final pair = itemStr.split(':');
        if (pair.length == 2) {
          _paletteGroups.putIfAbsent(so, () => []).add({
            'itemCode': pair[0],
            'weight': pair[1],
            'soNumber': so,
            'customer': customer,
            'deliveryDate': delivery,
            'unit': unit,
            'type': 'ITEM',
          });
        }
      }
    } else {
      final so = data['soNumber'] ?? 'UNKNOWN';
      _paletteGroups.putIfAbsent(so, () => []).add(data);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _resetSession() {
    setState(() {
      _crateSoNumber = null;
      _crateItems.clear();
      _paletteGroups.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;
    final cardBg = theme.cardColor;
    final surfaceBg = isDark ? (theme.scaffoldBackgroundColor) : Colors.grey.withValues(alpha: 0.05);

    return IndustrialModuleLayout(
      title: 'QR AGGREGATION',
      body: Column(
        children: [
          // ── Mode Switcher ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(4),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
            ),
            child: Row(
              children: [
                _buildModeButton(context, 'CRATE', AggregationMode.crate, orange),
                _buildModeButton(context, 'PALETTE', AggregationMode.palette, orange),
              ],
            ),
          ),

          // ── Session Header ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: _buildStatCard(context, 'TOTAL WEIGHT', '${_totalWeight.toStringAsFixed(2)} KG', orange),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    context,
                    'ITEMS COUNT', 
                    '${_mode == AggregationMode.crate ? _crateItems.length : _paletteGroups.values.fold(0, (sum, list) => sum + list.length)}', 
                    isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),

          // ── Grouped List ───────────────────────────────────────────────
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: surfaceBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: _buildScannedList(context),
            ),
          ),

          // ── Action Bar ──────────────────────────────────────────────────
          _buildActionBar(context, orange),
        ],
      ),
    );
  }

  Widget _buildModeButton(BuildContext context, String label, AggregationMode mode, Color activeColor) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bool active = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_mode != mode) {
            _resetSession();
            setState(() => _mode = mode);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: active ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? Colors.black : (isDark ? Colors.white38 : Colors.black38),
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, String label, String value, Color valueColor) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = theme.cardColor;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
        boxShadow: isDark ? null : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: valueColor, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildScannedList(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    if (_mode == AggregationMode.crate) {
      if (_crateItems.isEmpty) return _buildEmptyState(context);
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _crateItems.length,
        itemBuilder: (context, index) {
          final item = _crateItems[index];
          return _buildItemTile(context, item);
        },
      );
    } else {
      if (_paletteGroups.isEmpty) return _buildEmptyState(context);
      final sos = _paletteGroups.keys.toList();
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sos.length,
        itemBuilder: (context, index) {
          final so = sos[index];
          final items = _paletteGroups[so]!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                child: Text(
                  'SALES ORDER: $so',
                  style: TextStyle(color: orange, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              ...items.map((item) => _buildItemTile(context, item)),
              Divider(color: isDark ? Colors.white10 : Colors.black12, height: 24),
            ],
          );
        },
      );
    }
  }

  Widget _buildItemTile(BuildContext context, Map<String, String> item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: isDark ? null : Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Icon(Icons.inventory_2_outlined, size: 16, color: isDark ? Colors.white24 : Colors.black26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['itemCode'] ?? 'UNKNOWN', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.w600)),
                Text(item['description'] ?? '', style: TextStyle(color: isDark ? Colors.white24 : Colors.black38, fontSize: 11), maxLines: 1),
              ],
            ),
          ),
          Text('${item['weight']} ${item['unit']}', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.qr_code_scanner, size: 48, color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05)),
          const SizedBox(height: 16),
          Text('AWAITING SCANS...', style: TextStyle(color: isDark ? Colors.white12 : Colors.black12, letterSpacing: 1.5)),
        ],
      ),
    );
  }

  Widget _buildActionBar(BuildContext context, Color orange) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = theme.cardColor;
    bool canFinalize = (_mode == AggregationMode.crate && _crateItems.isNotEmpty) || 
                      (_mode == AggregationMode.palette && _paletteGroups.isNotEmpty);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        border: Border(top: BorderSide(color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05))),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _resetSession,
            icon: Icon(Icons.refresh, color: isDark ? Colors.white38 : Colors.black38),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: canFinalize ? _onFinalize : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: orange,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                'FINALIZE ${_mode.name.toUpperCase()} QR',
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onFinalize() {
    if (_mode == AggregationMode.crate) {
      final firstItem = _crateItems.first;
      
      final qrData = LabelQrGenerator.generateCrate(
        soNumber: _crateSoNumber!,
        customer: firstItem['customer'] ?? 'N/A',
        delivery: firstItem['deliveryDate'] ?? 'N/A',
        items: _crateItems, // Detailed items manifest
        unit: firstItem['unit'] ?? 'KG',
      );
      
      LabelPrintingHandler.showCratePreview(
        context: context,
        soNumber: _crateSoNumber!,
        customerName: firstItem['customer'] ?? 'N/A',
        deliveryDate: firstItem['deliveryDate'] ?? 'N/A',
        items: _crateItems, // Detailed items manifest
        unit: firstItem['unit'] ?? 'KG',
        qrData: qrData,
      );
    } else {
      final firstSoGroup = _paletteGroups.values.first;
      final firstItem = firstSoGroup.first;
      
      // Compute detailed manifest: SO -> {Metadata + Full Item List}
      final Map<String, Map<String, dynamic>> manifest = _paletteGroups.map(
        (so, items) => MapEntry(so, {
          'customer': items.first['customer'] ?? 'N/A',
          'delivery': items.first['deliveryDate'] ?? 'N/A',
          'items': items, // Preserve full Product + Weight list
        })
      );

      final qrData = LabelQrGenerator.generatePalette(manifest);
      
      LabelPrintingHandler.showPalettePreview(
        context: context,
        totalWeight: _totalWeight,
        unit: 'KG',
        qrData: qrData,
        manifest: manifest,
        customerName: _paletteGroups.length == 1 ? (firstItem['customer'] ?? 'MULTIPLE') : 'MULTIPLE',
        deliveryDate: _paletteGroups.length == 1 ? (firstItem['deliveryDate'] ?? 'MULTIPLE') : 'MULTIPLE',
      );
    }
  }
}
