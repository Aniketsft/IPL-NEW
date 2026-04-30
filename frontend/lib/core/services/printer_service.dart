import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:enterprise_auth_mobile/core/services/tcp_print_service.dart';
import 'package:enterprise_auth_mobile/core/utils/zpl_generator.dart';

enum PrintMode { system, directIp }

class PrinterService {
  static final PrinterService instance = PrinterService._internal();
  PrinterService._internal();

  late SharedPreferences _prefs;
  PrintMode _mode = PrintMode.directIp;
  String _printerIp = '172.26.45.120';
  int _printerPort = 9100;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _mode = PrintMode.values[_prefs.getInt('print_mode') ?? 1];
    _printerIp = _prefs.getString('printer_ip') ?? '172.26.45.120';
    _printerPort = _prefs.getInt('printer_port') ?? 9100;
  }

  Future<void> setPrintMode(PrintMode mode) async {
    _mode = mode;
    await _prefs.setInt('print_mode', mode.index);
  }

  Future<void> setPrinterIp(String ip) async {
    _printerIp = ip;
    await _prefs.setString('printer_ip', ip);
  }

  Future<void> setPrinterPort(int port) async {
    _printerPort = port;
    await _prefs.setInt('printer_port', port);
  }

  PrintMode get currentMode => _mode;
  String get printerIp => _printerIp;
  int get printerPort => _printerPort;

  Future<bool> isConnected() async {
    return true;
  }

  Future<void> disconnect() async {
  }

  Future<void> printLabel({
    required String soNumber,
    required String customerName,
    required String productCode,
    required String description,
    required double weight,
    required String unit,
    required String qrData,
    String? lotNumber,
    String? productionDate,
    String? expiryDate,
    String? auditId,
    String? salesman,
  }) async {
    if (_mode == PrintMode.directIp) {
      final zpl = ZplGenerator.generateItemLabel(
        soNumber: soNumber,
        customerName: customerName,
        productCode: productCode,
        description: description,
        weight: weight,
        unit: unit,
        qrData: qrData,
        lotNumber: lotNumber,
        productionDate: productionDate,
        expiryDate: expiryDate,
        auditId: auditId,
        salesman: salesman,
      );
      await TcpPrintService.sendRawData(_printerIp, _printerPort, zpl);
      return;
    }

    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(100 * PdfPageFormat.mm, 100 * PdfPageFormat.mm),
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(32),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(productCode, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18)),
                    pw.Expanded(child: pw.Text(description, textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 12))),
                  ],
                ),
                pw.SizedBox(height: 12),
                pw.Text(customerName.toUpperCase(), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                pw.Text('IPLSO Number: $soNumber', style: const pw.TextStyle(fontSize: 14)),
                pw.Divider(thickness: 1),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Lot Number: ${lotNumber ?? "N/A"}', style: const pw.TextStyle(fontSize: 12)),
                    if (salesman != null) pw.Text('SM: $salesman', style: const pw.TextStyle(fontSize: 12)),
                  ],
                ),
                pw.Text('Production Date: ${productionDate ?? "TODAY"}', style: const pw.TextStyle(fontSize: 12)),
                pw.Text('Expiry Date: ${expiryDate ?? "N/A"}', style: const pw.TextStyle(fontSize: 12)),
                pw.SizedBox(height: 20),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Quantity:', style: const pw.TextStyle(fontSize: 14)),
                          pw.Text('${weight.toStringAsFixed(3)} $unit', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 32)),
                        ],
                      ),
                    ),
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: qrData,
                      width: 100,
                      height: 100,
                    ),
                  ],
                ),
                pw.Spacer(),
                pw.Divider(thickness: 1),
                pw.Text('Label ID: ${auditId ?? "INTERNAL"}', style: const pw.TextStyle(fontSize: 8)),
                pw.Text('Printed at: ${DateTime.now().toString()}', style: const pw.TextStyle(fontSize: 8)),
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
    if (_mode == PrintMode.directIp) {
      final zpl = ZplGenerator.generateCrateLabel(
        soNumber: soNumber,
        customerName: customerName,
        deliveryDate: deliveryDate,
        items: items,
        unit: unit,
        qrData: qrData,
        auditId: auditId,
      );
      await TcpPrintService.sendRawData(_printerIp, _printerPort, zpl);
      return;
    }

    final doc = pw.Document();
    double total = items.fold(0.0, (val, item) => val + (double.tryParse(item['weight'] ?? '0') ?? 0.0));

    doc.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(100 * PdfPageFormat.mm, 100 * PdfPageFormat.mm),
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
        pageFormat: const PdfPageFormat(100 * PdfPageFormat.mm, 100 * PdfPageFormat.mm),
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
  Future<void> printEodReport({
    required String workOrder,
    required String dateStr,
    required List<dynamic> items,
  }) async {
    if (_mode == PrintMode.directIp) {
      final zpl = ZplGenerator.generateEodLabel(
        workOrder: workOrder,
        dateStr: dateStr,
        items: items,
      );
      await TcpPrintService.sendRawData(_printerIp, _printerPort, zpl);
      return;
    }

    // PDF Fallback (uses the existing logic in EodPdfGenerator)
    // We don't implement the PDF logic here to avoid duplication,
    // instead, the UI will still call EodPdfGenerator if needed.
    // However, to make PrinterService the 'main' router, 
    // we can eventually move the logic here.
  }
}
