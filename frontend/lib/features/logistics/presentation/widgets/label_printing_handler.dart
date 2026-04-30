import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:enterprise_auth_mobile/core/services/printer_service.dart';
import '../../domain/entities/sales_order_detail.dart';
import '../../data/repositories/delivery_repository.dart';
import 'dart:convert';
import 'label_qr_generator.dart';

class LabelPrintingHandler {
  /// Shows the consolidated dialog for marking as prepared and choosing a printing action.
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

  /// Base UI for all label previews with an industrial aesthetic.
  static Widget _buildPreviewCard({
    required BuildContext context,
    required String title,
    required String qrData,
    required List<Widget> details,
    String? labelId,
    List<Widget>? manifest,
  }) {
    // Dynamic height based on screen size to prevent overflows
    final maxHeight = MediaQuery.of(context).size.height * 0.70;
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          constraints: BoxConstraints(maxHeight: maxHeight), 
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: SingleChildScrollView(
            child: Column(
              children: [
                Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.black, 
                    fontWeight: FontWeight.bold, 
                    fontSize: 18,
                    letterSpacing: 1.5,
                  ),
                ),
                const Divider(color: Colors.black, thickness: 2.0),
                const SizedBox(height: 8),
                QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: 140.0,
                  foregroundColor: Colors.black,
                ),
                const SizedBox(height: 12),
                ...details,
                if (manifest != null && manifest.isNotEmpty) ...[
                  const Divider(color: Colors.black, height: 20, thickness: 1),
                  const Text('EXPLODED MANIFEST LOG', style: TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black12),
                      color: Colors.grey[50],
                    ),
                    child: Column(children: manifest),
                  ),
                ],
                if (labelId != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'AUDIT ID: $labelId',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 8,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'INDUSTRIAL THERMAL PREVIEW (COMPACT)',
          style: TextStyle(color: Colors.white38, fontSize: 7, letterSpacing: 2),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// Visual preview for a standard Sales Order label.
  static Future<void> showLabelPreview({
    required BuildContext context,
    required SalesOrderDetail item,
    required Function(SalesOrderDetail, String? auditId) onPrintRequested,
  }) async {
    // 1. Log Audit and get ID (Local or Server)
    final auditId = await _logAudit(context, item);

    final qrData = LabelQrGenerator.generate(item);
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1D1D1D),
        contentPadding: const EdgeInsets.all(12),
        content: _buildPreviewCard(
          context: context,
          title: item.itemCode,
          qrData: qrData,
          details: [
            Text(item.description, style: const TextStyle(color: Colors.black54, fontSize: 10, fontStyle: FontStyle.italic)),
            const SizedBox(height: 8),
            Text('CUSTOMER: ${item.customerName?.toUpperCase() ?? "N/A"}', style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
            Text('SO REF: ${item.soNumber}', style: const TextStyle(color: Colors.black, fontSize: 10)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (item.lot != null) Text('LOT: ${item.lot}', style: const TextStyle(color: Colors.black, fontSize: 10)),
                Text('SM: ${((item.salesMan2?.trim() ?? "").isNotEmpty) ? item.salesMan2!.trim() : (item.salesMan1?.trim() ?? "N/A")}', style: const TextStyle(color: Colors.black, fontSize: 10)),
              ],
            ),
            const SizedBox(height: 12),
            Text('QTY: ${item.manufacturedQuantity.toStringAsFixed(3)} ${item.unit}', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CLOSE', style: TextStyle(color: Colors.grey))),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              onPrintRequested(item, auditId);
            },
            icon: const Icon(Icons.print),
            label: const Text('PRINT'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF9800), 
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  /// Refined Crate Preview: Header is general, manifest shows Products.
  static Future<void> showCratePreview({
    required BuildContext context,
    required String soNumber,
    required String customerName,
    required String deliveryDate,
    required List<Map<String, String>> items, 
    required String unit,
    required String qrData,
  }) async {
    double total = items.fold(0.0, (sum, i) => sum + (double.tryParse(i['weight'] ?? '0') ?? 0.0));

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1D1D1D),
        contentPadding: const EdgeInsets.all(12),
        content: _buildPreviewCard(
          context: context,
          title: 'CRATE LABEL',
          qrData: qrData,
          details: [
            Text('CUSTOMER: ${customerName.toUpperCase()}', style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
            Text('SO REF: $soNumber', style: const TextStyle(color: Colors.black, fontSize: 10)),
            Text('DELIVERY: $deliveryDate', style: const TextStyle(color: Colors.black, fontSize: 10)),
            const SizedBox(height: 8),
            Text('TOTAL: ${total.toStringAsFixed(2)} $unit', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 20)),
          ],
          labelId: 'PENDING...', // Will be updated if we audit before preview
          manifest: items.map((i) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(i['itemCode'] ?? 'N/A', style: const TextStyle(color: Colors.black87, fontSize: 10, fontFamily: 'monospace')),
                Text('${i['weight'] ?? '0.00'} $unit', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 10, fontFamily: 'monospace')),
              ],
            ),
          )).toList(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CLOSE', style: TextStyle(color: Colors.grey))),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await PrinterService.instance.printCrateLabel(
                  soNumber: soNumber,
                  customerName: customerName,
                  deliveryDate: deliveryDate,
                  items: items,
                  unit: unit,
                  qrData: qrData,
                );
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Print Fail: $e'), backgroundColor: Colors.red));
                }
              }
            },
            icon: const Icon(Icons.print),
            label: const Text('PRINT CRATE'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF9800), foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  /// Granular Palette Preview: Shows every item in every SO.
  static Future<void> showPalettePreview({
    required BuildContext context,
    required double totalWeight,
    required String unit,
    required String qrData,
    required Map<String, Map<String, dynamic>> manifest,
    String customerName = "MULTIPLE",
    String deliveryDate = "MULTIPLE",
  }) async {
    final List<Widget> manifestWidgets = [];
    manifest.forEach((so, data) {
      final items = List<Map<String, String>>.from(data['items'] ?? []);
      final cust = (data['customer'] ?? 'N/A').toUpperCase();
      
      manifestWidgets.add(
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(8),
          color: Colors.grey[200],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SO: $so', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 9)),
              Text('CUST: ${cust.length > 30 ? cust.substring(0, 30) + "..." : cust}', style: const TextStyle(color: Colors.black54, fontSize: 8)),
              const Divider(color: Colors.black12, height: 6),
              ...items.map((i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(i['itemCode'] ?? 'N/A', style: const TextStyle(color: Colors.black87, fontSize: 8, fontFamily: 'monospace')),
                    Text('${i['weight'] ?? '0.00'} $unit', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 8, fontFamily: 'monospace')),
                  ],
                ),
              )).toList(),
            ],
          ),
        )
      );
    });

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1D1D1D),
        contentPadding: const EdgeInsets.all(8),
        content: _buildPreviewCard(
          context: context,
          title: 'PALETTE MASTER',
          qrData: qrData,
          details: [
            Text('MASTER CUST: ${customerName.toUpperCase()}', style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
            Text('SO COUNT: ${manifest.length}', style: const TextStyle(color: Colors.black, fontSize: 10)),
            const SizedBox(height: 8),
            Text('TOTAL: ${totalWeight.toStringAsFixed(2)} $unit', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 22)),
          ],
          labelId: 'MULTI-AUDIT',
          manifest: manifestWidgets,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CLOSE', style: TextStyle(color: Colors.grey))),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await PrinterService.instance.printPaletteLabel(
                  soCount: manifest.length,
                  totalWeight: totalWeight,
                  unit: unit,
                  qrData: qrData,
                  manifest: manifest,
                  customerName: customerName,
                  deliveryDate: deliveryDate,
                );
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Palette Print Fail: $e'), backgroundColor: Colors.red));
                }
              }
            },
            icon: const Icon(Icons.print),
            label: const Text('PRINT PALETTE'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF9800), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16)),
          ),
        ],
      ),
    );
  }

  /// Sends the label to the thermal printer.
  static Future<void> printLabel({
    required BuildContext context,
    required SalesOrderDetail item,
    String? auditId,
  }) async {
    try {
      // 1. Ensure we have an audit ID (If direct print was called)
      final effectiveAuditId = auditId ?? await _logAudit(context, item);

      await PrinterService.instance.printLabel(
        soNumber: item.soNumber,
        customerName: item.customerName ?? 'N/A',
        productCode: item.itemCode,
        description: item.description,
        weight: item.manufacturedQuantity,
        unit: item.unit,
        qrData: LabelQrGenerator.generate(item),
        lotNumber: item.lot,
        auditId: effectiveAuditId,
        salesman: ((item.salesMan2?.trim() ?? "").isNotEmpty) 
            ? item.salesMan2!.trim() 
            : item.salesMan1?.trim(),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Print Fail: $e'), backgroundColor: Colors.red));
      }
    }
  }

  /// Private helper to log audit and handle both online/offline flows.
  static Future<String?> _logAudit(BuildContext context, SalesOrderDetail item) async {
    try {
      final repo = RepositoryProvider.of<DeliveryRepository>(context);
      return await repo.logLabelAudit({
        'referenceNumber': item.soNumber,
        'labelType': 'Standard',
        'productCode': item.itemCode,
        'customerName': item.customerName,
        'totalWeight': item.manufacturedQuantity,
        'manifestJson': jsonEncode([{
          'so': item.soNumber,
          'item': item.itemCode,
          'weight': item.manufacturedQuantity,
        }]),
      });
    } catch (e) {
      debugPrint("LabelPrintingHandler: Failed to log audit: $e");
      return "TMP-${DateTime.now().millisecondsSinceEpoch}";
    }
  }
}
