import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/delivery_repository.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/entities/sales_order.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/entities/sales_order_detail.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/pages/production_tracking_screen.dart';

class ProductionTrackingScanner extends StatefulWidget {
  final SalesOrder order;
  final List<SalesOrderDetail> details;

  const ProductionTrackingScanner({
    super.key,
    required this.order,
    required this.details,
  });

  @override
  State<ProductionTrackingScanner> createState() => _ProductionTrackingScannerState();
}

class _ProductionTrackingScannerState extends State<ProductionTrackingScanner> {
  final MobileScannerController _controller = MobileScannerController(
    formats: [BarcodeFormat.ean13],
  );
  bool _isProcessing = false;
  DateTime? _lastScanTime;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final String? barcode = capture.barcodes.first.rawValue;
    if (barcode == null || barcode.isEmpty) return;

    // Pause between scans to avoid accidental multiples (2 seconds)
    if (_lastScanTime != null &&
        DateTime.now().difference(_lastScanTime!).inSeconds < 2) {
      return;
    }
    _lastScanTime = DateTime.now();

    setState(() => _isProcessing = true);

    try {
      final repository = context.read<DeliveryRepository>();
      final productInfo = await repository.getProductByBarcode(barcode);

      if (!mounted) return;

      if (productInfo != null) {
        final String itemCode = (productInfo['productCode'] as String?) ?? '';
        
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
            Navigator.pop(context); // Close scanner modal
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProductionTrackingScreen(
                  order: widget.order,
                  product: detail,
                ),
              ),
            );
          }
        } else {
          _showSnackBar('No product code "$itemCode" in this order.');
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
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          // Scanner Overlay (visual guidework)
          Center(
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.orange, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          if (_isProcessing)
            const Center(
              child: CircularProgressIndicator(color: Colors.orange),
            ),
          const Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Text(
              'Align EAN-13 barcode within the frame',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
