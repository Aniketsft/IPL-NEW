import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PrinterService {
  static final PrinterService instance = PrinterService._internal();
  PrinterService._internal();

  Future<void> init() async {
    // No initialization needed for system printers
  }

  Future<bool> isConnected() async {
    // We assume the native print spooler handles connection checks
    return true;
  }

  Future<void> disconnect() async {
  }

  Future<void> printLabel({
    required String soNumber,
    required String customerName,
    required String productCode,
    required double weight,
    required String unit,
    required String qrData,
    String? auditId,
  }) async {
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(32),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('ITEM: $productCode', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 32)),
                          pw.SizedBox(height: 16),
                          pw.Text('CUSTOMER: ${customerName.toUpperCase()}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 24)),
                          pw.Text('SO: $soNumber', style: pw.TextStyle(fontSize: 24)),
                          pw.SizedBox(height: 24),
                          pw.Text('WEIGHT: ${weight.toStringAsFixed(2)} $unit', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 32)),
                        ],
                      ),
                    ),
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: qrData,
                      width: 150,
                      height: 150,
                    ),
                  ],
                ),
                pw.SizedBox(height: 32),
                pw.Center(child: pw.Text('Industrial Tracking System', style: const pw.TextStyle(fontSize: 16))),
                if (auditId != null)
                  pw.Center(child: pw.Text('AUDIT: $auditId', style: const pw.TextStyle(fontSize: 12))),
              ],
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Item_Label_$productCode',
    );
  }

  Future<void> printCrateLabel({
    required String soNumber,
    required String customerName,
    required String deliveryDate,
    required List<Map<String, String>> items,
    required String unit,
    required String qrData,
    String? auditId,
  }) async {
    final doc = pw.Document();
    double total = items.fold(0.0, (val, item) => val + (double.tryParse(item['weight'] ?? '0') ?? 0.0));

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(32),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Center(child: pw.Text('CRATE LABEL', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 36))),
                pw.SizedBox(height: 16),
                pw.Text('CUSTOMER: ${customerName.toUpperCase()}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 24)),
                pw.Text('SO REF: $soNumber', style: pw.TextStyle(fontSize: 24)),
                pw.Text('DELIVERY: $deliveryDate', style: pw.TextStyle(fontSize: 24)),
                pw.SizedBox(height: 24),
                
                pw.Divider(thickness: 2),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('PRODUCT', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 20)),
                    pw.Text('WEIGHT', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 20)),
                  ],
                ),
                pw.Divider(thickness: 1),
                
                ...items.map((item) {
                  String prod = item['itemCode'] ?? 'N/A';
                  String wgt = '${item['weight'] ?? '0.00'} $unit';
                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 4.0),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(prod, style: const pw.TextStyle(fontSize: 18)),
                        pw.Text(wgt, style: const pw.TextStyle(fontSize: 18)),
                      ],
                    ),
                  );
                }),
                pw.Divider(thickness: 2),
                
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        children: [
                          pw.Text('TOTAL WEIGHT', style: const pw.TextStyle(fontSize: 20)),
                          pw.Text('${total.toStringAsFixed(2)} $unit', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 32)),
                        ],
                      ),
                    ),
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: qrData,
                      width: 150,
                      height: 150,
                    ),
                  ],
                ),
                
                pw.SizedBox(height: 32),
                pw.Center(child: pw.Text('Industrial Tracking System', style: const pw.TextStyle(fontSize: 16))),
                if (auditId != null)
                  pw.Center(child: pw.Text('AUDIT: $auditId', style: const pw.TextStyle(fontSize: 12))),
              ],
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Crate_Label_$soNumber',
    );
  }

  Future<void> printPaletteLabel({
    required int soCount,
    required double totalWeight,
    required String unit,
    required String qrData,
    required Map<String, Map<String, dynamic>> manifest,
    String customerName = "MULTIPLE",
    String deliveryDate = "MULTIPLE",
    String? auditId,
  }) async {
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(32),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Center(child: pw.Text('PALETTE MASTER', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 36))),
                pw.SizedBox(height: 16),
                pw.Text('MASTER CUST: ${customerName.toUpperCase()}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 24)),
                pw.Text('TOTAL SOs: $soCount', style: const pw.TextStyle(fontSize: 24)),
                pw.Text('DELIVERY: $deliveryDate', style: const pw.TextStyle(fontSize: 24)),
                pw.SizedBox(height: 24),

                pw.Center(child: pw.Text('EXPLODED MANIFEST', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 20))),
                pw.Divider(thickness: 2),
                
                ...manifest.entries.map((entry) {
                  final so = entry.key;
                  final data = entry.value;
                  final cust = (data['customer'] ?? 'N/A').toString().toUpperCase();
                  final items = List<Map<String, String>>.from(data['items'] ?? []);

                  return pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 12.0),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('SO: $so | CUST: $cust', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18)),
                        ...items.map((item) {
                          String prod = item['itemCode'] ?? 'N/A';
                          String wgt = '${item['weight'] ?? '0.00'} $unit';
                          return pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text('  $prod', style: const pw.TextStyle(fontSize: 16)),
                              pw.Text(wgt, style: const pw.TextStyle(fontSize: 16)),
                            ],
                          );
                        }),
                      ],
                    ),
                  );
                }),
                
                pw.Divider(thickness: 2),
                pw.SizedBox(height: 16),
                
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        children: [
                          pw.Text('PALETTE TOTAL WEIGHT', style: const pw.TextStyle(fontSize: 20)),
                          pw.Text('${totalWeight.toStringAsFixed(2)} $unit', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 32)),
                        ],
                      ),
                    ),
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: qrData,
                      width: 180,
                      height: 180,
                    ),
                  ],
                ),
                
                pw.SizedBox(height: 32),
                pw.Center(child: pw.Text('Industrial Tracking System', style: const pw.TextStyle(fontSize: 16))),
                if (auditId != null)
                  pw.Center(child: pw.Text('AUDIT: $auditId', style: const pw.TextStyle(fontSize: 12))),
              ],
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Palette_Master',
    );
  }
}
