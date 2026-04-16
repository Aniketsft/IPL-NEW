import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:enterprise_auth_mobile/core/services/printer_service.dart';
import '../../domain/entities/sales_order_detail.dart';
import 'label_qr_generator.dart';

class LabelPrintingHandler {
  /// Shows the consolidated dialog for marking as prepared and choosing a printing action.
  /// Returns the user's choice: 'just_mark', 'preview', 'print', or null (if cancelled).
  static Future<String?> showPreparationPrompt({
    required BuildContext context,
    required SalesOrderDetail item,
  }) async {
    return await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1D1D1D),
        title: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Color(0xFFFF9800)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Prepare SO ${item.soNumber}',
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ],
        ),
        content: const Text(
          'Mark this item as prepared?\nYou can also choose to preview or print the label immediately.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context, 'print'),
                  icon: const Icon(Icons.print),
                  label: const Text('PRINT LABEL NOW'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF9800),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context, 'preview'),
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('PREVIEW LABEL'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF9800),
                    side: const BorderSide(color: Color(0xFFFF9800)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, 'just_mark'),
                        child: const Text('JUST MARK AS PREPARED', style: TextStyle(color: Color(0xFFFF9800))),
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, 'cancel'),
                  child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Shows a visual preview of the label on screen.
  static Future<void> showLabelPreview({
    required BuildContext context,
    required SalesOrderDetail item,
    required Function(SalesOrderDetail) onPrintRequested,
  }) async {
    final qrData = LabelQrGenerator.generate(item);
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1D1D1D),
        title: const Row(
          children: [
            Icon(Icons.visibility_outlined, color: Color(0xFFFF9800)),
            SizedBox(width: 12),
            Text('Label Preview', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: Column(
                children: [
                  QrImageView(
                    data: qrData,
                    version: QrVersions.auto,
                    size: 150.0,
                    foregroundColor: Colors.black,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'SO: ${item.soNumber}',
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  Text(
                    'Customer: ${item.customerName ?? "N/A"}',
                    style: const TextStyle(color: Colors.black, fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    'Product: ${item.itemCode}',
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  Text(
                    'Weight: ${item.manufacturedQuantity.toStringAsFixed(2)} ${item.unit}',
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'This is a visual representation of the thermal print layout.',
              style: TextStyle(color: Colors.white38, fontSize: 10),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              onPrintRequested(item);
            },
            icon: const Icon(Icons.print),
            label: const Text('PRINT NOW'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF9800),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// Sends the label to the thermal printer.
  static Future<void> printLabel({
    required BuildContext context,
    required SalesOrderDetail item,
  }) async {
    try {
      await PrinterService.instance.printLabel(
        soNumber: item.soNumber,
        customerName: item.customerName ?? 'N/A',
        productCode: item.itemCode,
        weight: item.manufacturedQuantity,
        unit: item.unit,
        qrData: LabelQrGenerator.generate(item),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Label sent to printer ✓'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Printing failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }
}
