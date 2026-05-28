import 'package:flutter/material.dart';
import 'package:enterprise_auth_mobile/core/utils/barcode_scanner/hardware_scanner_mixin.dart';
import 'package:provider/provider.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/delivery_repository.dart';
import 'offline_barcode_processor.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/entities/sales_order.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/entities/sales_order_detail.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/pages/production_tracking_screen.dart';

class ProductionTrackingScanner extends StatefulWidget {
  final SalesOrder order;
  final List<SalesOrderDetail> details;
  final List<String> permissions;

  const ProductionTrackingScanner({
    super.key,
    required this.order,
    required this.details,
    required this.permissions,
  });

  @override
  State<ProductionTrackingScanner> createState() => _ProductionTrackingScannerState();
}

class _ProductionTrackingScannerState extends State<ProductionTrackingScanner> with HardwareScannerMixin<ProductionTrackingScanner> {
  bool _isProcessing = false;
  DateTime? _lastScanTime;

  @override
  void onHardwareScan(String data) {
    _handleHardwareScan(data);
  }

  Future<void> _handleHardwareScan(String barcode) async {

    // Pause between scans to avoid accidental multiples (2 seconds)
    if (_lastScanTime != null &&
        DateTime.now().difference(_lastScanTime!).inSeconds < 2) {
      return;
    }
    _lastScanTime = DateTime.now();

    setState(() => _isProcessing = true);

    try {
      final processor = OfflineBarcodeProcessor();
      final result = await processor.processBarcode(barcode);

      if (!mounted) return;

      if (result != null) {
        final String itemCode = result.itemCode;
        
        if (itemCode.isEmpty) {
          _showSnackBar('Product found but item code is missing.');
          return;
        }
        
        // Find matching detail in current order
        final detail = widget.details.firstWhere(
          (d) => d.itemCode.toUpperCase() == itemCode.toUpperCase(),
          orElse: () => SalesOrderDetail(
            soNumber: widget.order.orderNumber,
            itemCode: 'not_found',
            description: '',
            quantity: 0,
            unit: '',
            barcodeType: '',
            remaining: 0,
            scannedQuantity: 0,
            manufacturedQuantity: 0,
            isPrepared: false,
          ),
        );

        if (detail.itemCode != 'not_found') {
          // Navigation logic
          if (detail.isPrepared) {
            _showSnackBar('Product "${detail.itemCode}" is already marked as PREPARED.');
          } else {
             // Redirect to tracking screen
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProductionTrackingScreen(
                  order: widget.order,
                  product: detail,
                  permissions: widget.permissions,
                ),
              ),
            );
            
            if (mounted) {
              Navigator.pop(context, result); // Close scanner and return tracking result (true if saved)
            }
          }
        } else {
          // NEW: For Cut/Bulk orders, allow adding "new" products that aren't in the detail list
          final isCutBulkOrder =
              widget.order.orderNumber.startsWith('BLK-') ||
              widget.order.orderNumber.startsWith('CUTS-');

          if (isCutBulkOrder) {
            final newDetail = SalesOrderDetail(
              soNumber: widget.order.orderNumber,
              itemCode: result.itemCode,
              description: result.description,
              quantity: 0.0, // Default for new additions
              unit: result.unit,
              barcodeType: '',
              remaining: 0.0,
              scannedQuantity: 0.0,
              manufacturedQuantity: 0.0,
              isPrepared: false,
            );

            final trackingResult = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProductionTrackingScreen(
                  order: widget.order,
                  product: newDetail,
                  permissions: widget.permissions,
                ),
              ),
            );
            
            if (mounted) {
              Navigator.pop(context, trackingResult);
            }
          } else {
            _showSnackBar('No product code "$itemCode" in this order.');
          }
        }
      } else {
        _showSnackBar('Unknown barcode: $barcode');
      }
    } catch (e) {
      _showSnackBar('Error processing scan: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan Product to Track'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.3), width: 2),
                  ),
                  child: const Icon(
                    Icons.barcode_reader,
                    size: 80,
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'READY TO TRACK',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Trigger physical scan button on device',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          if (_isProcessing)
            const Center(
              child: CircularProgressIndicator(color: Colors.orange),
            ),
        ],
      ),
    );
  }
}
