import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:enterprise_auth_mobile/core/models/printer_device.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:enterprise_auth_mobile/core/services/tcp_print_service.dart';
import 'package:enterprise_auth_mobile/core/utils/zpl_generator.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;

enum PrintMode { system, directIp, bluetooth }

class PrinterService {
  static final PrinterService instance = PrinterService._internal();
  PrinterService._internal();

  static const MethodChannel _bluetoothChannel = MethodChannel('com.enterprise.auth/bluetooth');

  late SharedPreferences _prefs;
  PrintMode _mode = PrintMode.bluetooth;
  List<PrinterDevice> _printers = [];
  String? _defaultDirectIpPrinterId;
  String? _defaultSystemPrinterId;
  String? _defaultBluetoothPrinterId;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final modeIndex = _prefs.getInt('print_mode') ?? PrintMode.bluetooth.index;
    _mode = modeIndex < PrintMode.values.length ? PrintMode.values[modeIndex] : PrintMode.bluetooth;
    
    final printersJson = _prefs.getString('printers_list');
    if (printersJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(printersJson);
        _printers = decoded.map((e) => PrinterDevice.fromJson(e)).toList();
      } catch(e) {
        _printers = [];
      }
    } else {
      // Migrate old data if present
      final oldIp = _prefs.getString('printer_ip');
      if (oldIp != null) {
        final defaultPrinter = PrinterDevice(
          id: 'default_migration_id',
          name: 'Legacy Thermal Printer',
          printerModel: 'Generic',
          ipAddress: oldIp,
          port: _prefs.getInt('printer_port') ?? 9100,
          mode: PrintMode.directIp,
        );
        _printers = [defaultPrinter];
        _defaultDirectIpPrinterId = defaultPrinter.id;
        await _savePrinters();
      }
    }
    
    _defaultDirectIpPrinterId = _prefs.getString('default_direct_ip_printer_id') ?? _defaultDirectIpPrinterId;
    _defaultSystemPrinterId = _prefs.getString('default_system_printer_id');
    _defaultBluetoothPrinterId = _prefs.getString('default_bluetooth_printer_id');
  }

  Future<void> _savePrinters() async {
    final encoded = jsonEncode(_printers.map((e) => e.toJson()).toList());
    await _prefs.setString('printers_list', encoded);
  }

  Future<void> setPrintMode(PrintMode mode) async {
    _mode = mode;
    await _prefs.setInt('print_mode', mode.index);
  }

  List<PrinterDevice> get printers => List.unmodifiable(_printers);
  
  PrinterDevice? get defaultDirectIpPrinter {
    try {
      return _printers.firstWhere((p) => p.id == _defaultDirectIpPrinterId && p.mode == PrintMode.directIp);
    } catch (_) {
      return null;
    }
  }

  PrinterDevice? get defaultSystemPrinter {
    try {
      return _printers.firstWhere((p) => p.id == _defaultSystemPrinterId && p.mode == PrintMode.system);
    } catch (_) {
      return null;
    }
  }

  PrinterDevice? get defaultBluetoothPrinter {
    try {
      return _printers.firstWhere((p) => p.id == _defaultBluetoothPrinterId && p.mode == PrintMode.bluetooth);
    } catch (_) {
      return null;
    }
  }

  Future<void> addPrinter(PrinterDevice printer) async {
    _printers.add(printer);
    await _savePrinters();
    
    // Auto-assign default if it's the first of its mode
    if (printer.mode == PrintMode.directIp && _defaultDirectIpPrinterId == null) {
      await setDefaultPrinter(printer.id, PrintMode.directIp);
    } else if (printer.mode == PrintMode.bluetooth && _defaultBluetoothPrinterId == null) {
      await setDefaultPrinter(printer.id, PrintMode.bluetooth);
    } else if (printer.mode == PrintMode.system && _defaultSystemPrinterId == null) {
      await setDefaultPrinter(printer.id, PrintMode.system);
    }
  }

  Future<void> updatePrinter(PrinterDevice printer) async {
    final index = _printers.indexWhere((p) => p.id == printer.id);
    if (index != -1) {
      _printers[index] = printer;
      await _savePrinters();
    }
  }

  Future<void> removePrinter(String id) async {
    final printer = _printers.firstWhere((p) => p.id == id);
    _printers.removeWhere((p) => p.id == id);
    await _savePrinters();

    if (printer.mode == PrintMode.directIp && _defaultDirectIpPrinterId == id) {
      _defaultDirectIpPrinterId = null;
      await _prefs.remove('default_direct_ip_printer_id');
      final fallback = _printers.where((p) => p.mode == PrintMode.directIp).firstOrNull;
      if (fallback != null) await setDefaultPrinter(fallback.id, PrintMode.directIp);
    } else if (printer.mode == PrintMode.bluetooth && _defaultBluetoothPrinterId == id) {
      _defaultBluetoothPrinterId = null;
      await _prefs.remove('default_bluetooth_printer_id');
      final fallback = _printers.where((p) => p.mode == PrintMode.bluetooth).firstOrNull;
      if (fallback != null) await setDefaultPrinter(fallback.id, PrintMode.bluetooth);
    } else if (printer.mode == PrintMode.system && _defaultSystemPrinterId == id) {
      _defaultSystemPrinterId = null;
      await _prefs.remove('default_system_printer_id');
      final fallback = _printers.where((p) => p.mode == PrintMode.system).firstOrNull;
      if (fallback != null) await setDefaultPrinter(fallback.id, PrintMode.system);
    }
  }

  Future<void> setDefaultPrinter(String id, PrintMode mode) async {
    if (mode == PrintMode.directIp) {
      _defaultDirectIpPrinterId = id;
      await _prefs.setString('default_direct_ip_printer_id', id);
    } else if (mode == PrintMode.bluetooth) {
      _defaultBluetoothPrinterId = id;
      await _prefs.setString('default_bluetooth_printer_id', id);
    } else {
      _defaultSystemPrinterId = id;
      await _prefs.setString('default_system_printer_id', id);
    }
  }

  PrintMode get currentMode => _mode;

  Future<bool> isConnected() async {
    return true;
  }

  Future<void> disconnect() async {
  }

  Future<void> printLabel({
    required String soNumber,
    required String customerName,
    String? customerCode,
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
    double? eaQuantity,
  }) async {
    if (_mode == PrintMode.directIp) {
      final printer = defaultDirectIpPrinter;
      if (printer == null || printer.ipAddress == null || printer.port == null) {
        throw Exception("No default Direct IP printer configured.");
      }
      final zpl = ZplGenerator.generateItemLabel(
        soNumber: soNumber,
        customerName: customerName,
        customerCode: customerCode,
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
        eaQuantity: eaQuantity,
      );
      await TcpPrintService.sendRawData(printer.ipAddress!, printer.port!, zpl);
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
    String? customerCode,
    required String deliveryDate,
    required List<Map<String, String>> items,
    required String unit,
    required String qrData,
    String? auditId,
  }) async {
    if (_mode == PrintMode.directIp) {
      final printer = defaultDirectIpPrinter;
      if (printer == null || printer.ipAddress == null || printer.port == null) {
        throw Exception("No default Direct IP printer configured.");
      }
      final zpl = ZplGenerator.generateCrateLabel(
        soNumber: soNumber,
        customerName: customerName,
        customerCode: customerCode,
        deliveryDate: deliveryDate,
        items: items,
        unit: unit,
        qrData: qrData,
        auditId: auditId,
      );
      await TcpPrintService.sendRawData(printer.ipAddress!, printer.port!, zpl);
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
    if (_mode == PrintMode.directIp) {
      final printer = defaultDirectIpPrinter;
      if (printer == null || printer.ipAddress == null || printer.port == null) {
        throw Exception("No default Direct IP printer configured.");
      }
      final zpl = ZplGenerator.generatePaletteLabel(
        soCount: soCount,
        totalWeight: totalWeight,
        unit: unit,
        qrData: qrData,
        manifest: manifest,
        customerName: customerName,
        deliveryDate: deliveryDate,
        auditId: auditId,
      );
      await TcpPrintService.sendRawData(printer.ipAddress!, printer.port!, zpl);
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
      final printer = defaultDirectIpPrinter;
      if (printer == null || printer.ipAddress == null || printer.port == null) {
        throw Exception("No default Direct IP printer configured.");
      }
      final zpl = ZplGenerator.generateEodLabel(
        workOrder: workOrder,
        dateStr: dateStr,
        items: items,
      );
      await TcpPrintService.sendRawData(printer.ipAddress!, printer.port!, zpl);
      return;
    }

    // PDF Fallback (uses the existing logic in EodPdfGenerator)
    // We don't implement the PDF logic here to avoid duplication,
    // instead, the UI will still call EodPdfGenerator if needed.
    // However, to make PrinterService the 'main' router, 
    // we can eventually move the logic here.
  }

  Future<bool> ensureBluetoothPermissions() async {
    try {
      // Android 12+ (API 31+) permissions
      if (await Permission.bluetoothScan.isDenied) {
        await Permission.bluetoothScan.request();
      }
      if (await Permission.bluetoothConnect.isDenied) {
        await Permission.bluetoothConnect.request();
      }
      // Location fallback for Android 10/11
      if (await Permission.location.isDenied) {
        await Permission.location.request();
      }
      return true;
    } catch (e) {
      debugPrint('PrinterService.ensureBluetoothPermissions error: $e');
      return false;
    }
  }

  Future<bool> connectBluetoothPrinter(String macAddress) async {
    try {
      // 1. Ensure runtime permissions are granted
      await ensureBluetoothPermissions();

      // 2. Check if Bluetooth is turned on on phone
      try {
        final bool isBtEnabled = await PrintBluetoothThermal.bluetoothEnabled;
        if (!isBtEnabled) {
          throw Exception("Bluetooth is currently turned OFF. Please turn on Bluetooth in device settings.");
        }
      } catch (e) {
        if (e is Exception && e.toString().contains('turned OFF')) {
          rethrow;
        }
        debugPrint('PrinterService: bluetoothEnabled check warning: $e');
      }

      // 3. Check existing connection
      final bool isConnected = await PrintBluetoothThermal.connectionStatus;
      if (isConnected) {
        return true;
      }

      // 4. Connect to printer by MAC address (force clean socket first if stale)
      await disconnectBluetooth();
      bool connected = await PrintBluetoothThermal.connect(macPrinterAddress: macAddress);
      debugPrint('PrinterService.connect($macAddress) -> $connected');

      // Retry once if connection failed (frequently needed right after cancelDiscovery)
      if (!connected) {
        await Future.delayed(const Duration(milliseconds: 600));
        connected = await PrintBluetoothThermal.connect(macPrinterAddress: macAddress);
        debugPrint('PrinterService.connect retry($macAddress) -> $connected');
      }

      return connected;
    } catch (e) {
      debugPrint('PrinterService.connectBluetoothPrinter error: $e');
      rethrow;
    }
  }

  Future<void> disconnectBluetooth() async {
    try {
      await PrintBluetoothThermal.disconnect;
    } catch (e) {
      debugPrint('PrinterService.disconnectBluetooth error: $e');
    }
  }

  static final Map<
      int,
      ({
        List<({String text, bool bold})> lines,
        String? qrBase64,
        String? fiscalIrn,
      })> _pdfThermalLineCache = {};

  static int _fingerprintPdf(Uint8List bytes) {
    int hash = 0x811c9dc5;
    final int step = bytes.length > 4096 ? (bytes.length ~/ 2048) : 1;
    for (int i = 0; i < bytes.length; i += step) {
      hash ^= bytes[i];
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return (hash ^ bytes.length) & 0x7fffffff;
  }

  /// Registers the 68-column native ESC/POS lines (and optional fiscal QR/IRN)
  /// that produced [pdfBytes] so any caller passing [pdfBytes] to
  /// [printPdfViaBluetooth] prints crisp hardware-font ESC/POS text.
  static void registerPdfThermalLines(
    Uint8List pdfBytes,
    List<({String text, bool bold})> lines, {
    String? qrBase64,
    String? fiscalIrn,
  }) {
    if (_pdfThermalLineCache.length >= 32) {
      _pdfThermalLineCache.remove(_pdfThermalLineCache.keys.first);
    }
    _pdfThermalLineCache[_fingerprintPdf(pdfBytes)] = (
      lines: List.unmodifiable(lines),
      qrBase64: qrBase64,
      fiscalIrn: fiscalIrn,
    );
  }

  static List<({String text, bool bold})>? lookupPdfThermalLines(Uint8List pdfBytes) =>
      _pdfThermalLineCache[_fingerprintPdf(pdfBytes)]?.lines;

  static ({
    List<({String text, bool bold})> lines,
    String? qrBase64,
    String? fiscalIrn,
  })? lookupPdfThermalEntry(Uint8List pdfBytes) =>
      _pdfThermalLineCache[_fingerprintPdf(pdfBytes)];

  Future<bool> _writeBytesInChunks(List<int> bytes, {int chunkSize = 512}) async {
    debugPrint('PrinterService: writing ${bytes.length} bytes to Bluetooth socket (chunkSize=$chunkSize)...');
    for (int i = 0; i < bytes.length; i += chunkSize) {
      final end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
      final chunk = bytes.sublist(i, end);
      bool ok = await PrintBluetoothThermal.writeBytes(chunk);
      if (!ok && i == 0) {
        final mac = defaultBluetoothPrinter?.macAddress;
        if (mac != null && mac.isNotEmpty) {
          debugPrint('PrinterService: first chunk write failed, reconnecting to $mac and retrying...');
          await disconnectBluetooth();
          final reconnected = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
          if (reconnected) {
            ok = await PrintBluetoothThermal.writeBytes(chunk);
          }
        }
      }
      if (!ok) {
        debugPrint('PrinterService: writeBytes failed at offset $i (chunk size ${chunk.length})');
        return false;
      }
      if (end < bytes.length) {
        await Future.delayed(const Duration(milliseconds: 35));
      }
    }
    debugPrint('PrinterService: write completed successfully (${bytes.length} bytes)');
    return true;
  }

  Future<void> testPrintBluetooth() async {
    final printer = defaultBluetoothPrinter;
    if (printer == null || printer.macAddress == null || printer.macAddress!.isEmpty) {
      throw Exception("No default Bluetooth printer configured. Please add and set a default Bluetooth printer first in PRINTER MANAGEMENT.");
    }

    final isConnected = await connectBluetoothPrinter(printer.macAddress!);
    if (!isConnected) {
      throw Exception("Could not connect to '${printer.name}' (${printer.macAddress}). Please verify the printer is turned on and paired in Bluetooth settings.");
    }

    try {
      debugPrint('PrinterService.testPrintBluetooth generating test receipt...');
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);
      List<int> bytes = [];

      bytes += generator.reset();
      bytes += generator.text(
        'ENTERPRISE MOBILE',
        styles: const PosStyles(
          align: PosAlign.center,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
          bold: true,
        ),
      );
      bytes += generator.text(
        'SEWOO LK-P43II TEST',
        styles: const PosStyles(align: PosAlign.center, bold: true),
        linesAfter: 1,
      );
      bytes += generator.hr();
      bytes += generator.text('Printer: ${printer.name}');
      bytes += generator.text('Model: ${printer.printerModel}');
      if (printer.macAddress != null) {
        bytes += generator.text('MAC: ${printer.macAddress}');
      }
      bytes += generator.text('Status: CONNECTED (OK)');
      bytes += generator.text('Time: ${DateTime.now().toString().substring(0, 19)}');
      bytes += generator.hr();
      bytes += generator.qrcode('SEWOO_BT_TEST_${DateTime.now().millisecondsSinceEpoch}', size: QRSize.size6);
      bytes += generator.feed(4);

      final success = await _writeBytesInChunks(bytes);
      debugPrint('PrinterService.testPrintBluetooth completed: $success');
    } catch (e) {
      debugPrint('PrinterService.testPrintBluetooth error: $e');
      rethrow;
    }
  }

  Future<List<Map<String, String>>> getPairedBluetoothDevices() async {
    try {
      await ensureBluetoothPermissions();

      // Try PrintBluetoothThermal plugin first
      try {
        final List<BluetoothInfo> list = await PrintBluetoothThermal.pairedBluetooths;
        if (list.isNotEmpty) {
          return list.map((item) => {
            'name': item.name.isNotEmpty ? item.name : 'Unknown Device',
            'address': item.macAdress,
          }).toList();
        }
      } catch (btErr) {
        debugPrint('PrintBluetoothThermal.pairedBluetooths fallback: $btErr');
      }

      final result = await _bluetoothChannel.invokeMethod<List<dynamic>>('getPairedDevices');
      if (result == null) return [];
      return result.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        return {
          'name': (map['name'] ?? 'Unknown Device').toString(),
          'address': (map['address'] ?? '').toString(),
        };
      }).toList();
    } catch (e) {
      debugPrint('getPairedBluetoothDevices error: $e');
      return [];
    }
  }

  /// Prints monospaced 68-column lines directly using native ESC/POS text
  /// commands (matching [testPrintBluetooth]) on the Sewoo LK-P43II.
  Future<bool> printThermalLinesViaBluetooth({
    required List<({String text, bool bold})> lines,
    required String documentName,
    String? qrBase64,
    String? fiscalIrn,
  }) async {
    final printer = defaultBluetoothPrinter;
    if (printer == null || printer.macAddress == null || printer.macAddress!.isEmpty) {
      throw Exception(
        "No default Bluetooth printer configured. Please go to PRINTER MANAGEMENT and set your Sewoo LK-P43II as the default Bluetooth printer.",
      );
    }

    try {
      debugPrint('PrinterService.printThermalLinesViaBluetooth starting for $documentName (${lines.length} lines)');

      final isConnected = await connectBluetoothPrinter(printer.macAddress!);
      if (!isConnected) {
        throw Exception(
          "Could not connect to Bluetooth printer '${printer.name}' (${printer.macAddress}). Please ensure printer is powered on and in range.",
        );
      }

      // Build clean, standard ESC/POS byte stream directly without
      // esc_pos_utils_plus per-line control bloat (ESC $ 00 00, FS ., etc.).
      final List<int> bytes = <int>[
        0x1B, 0x40, // ESC @ : Initialize printer
        0x1B, 0x61, 0x00, // ESC a 0 : Left alignment
        0x1B, 0x4D, 0x00, // ESC M 0 : Font A (12x24, 69 cols on 832-dot Sewoo LK-P43II)
        0x1B, 0x45, 0x00, // ESC E 0 : Bold off
      ];

      bool currentBold = false;
      for (final line in lines) {
        final String trimmedRight = line.text.replaceAll(RegExp(r'\s+$'), '');
        if (trimmedRight.isEmpty) {
          bytes.add(0x0D);
          bytes.add(0x0A);
          continue;
        }

        if (line.bold != currentBold) {
          currentBold = line.bold;
          bytes.addAll(<int>[0x1B, 0x45, currentBold ? 0x01 : 0x00]);
        }

        // Emit strict printable ASCII (0x20..0x7E) only to prevent weird symbols
        for (int i = 0; i < trimmedRight.length; i++) {
          final int code = trimmedRight.codeUnitAt(i);
          bytes.add((code >= 0x20 && code <= 0x7E) ? code : 0x20);
        }
        bytes.add(0x0D);
        bytes.add(0x0A);
      }

      if (currentBold) {
        bytes.addAll(const <int>[0x1B, 0x45, 0x00]);
      }

      // Append MRA Fiscal QR raster + IRN when fiscalised
      final cleanQr = qrBase64?.trim() ?? '';
      final cleanIrn = fiscalIrn?.trim() ?? '';
      if (cleanQr.isNotEmpty) {
        try {
          final qrPngBytes = base64Decode(cleanQr);
          final decodedQr = img.decodeImage(qrPngBytes);
          if (decodedQr != null) {
            // Convert any PNG bit depth / color type (MRA returns 1-bit grayscale PNGs
            // where white=1 rather than 255) into an opaque 8-bit RGB canvas (0 or 255)
            // so esc_pos_utils_plus luminance (<128) does not render white pixels black.
            var qrImg = img.Image(
              width: decodedQr.width,
              height: decodedQr.height,
              numChannels: 3,
              format: img.Format.uint8,
            );
            for (final pixel in decodedQr) {
              final double rN = pixel.rNormalized.toDouble();
              final double gN = decodedQr.numChannels >= 2 ? pixel.gNormalized.toDouble() : rN;
              final double bN = decodedQr.numChannels >= 3 ? pixel.bNormalized.toDouble() : rN;
              final double alpha = decodedQr.hasAlpha ? pixel.aNormalized.toDouble() : 1.0;
              final double lum = (decodedQr.numChannels <= 2 && !decodedQr.hasPalette)
                  ? rN
                  : (0.299 * rN) + (0.587 * gN) + (0.114 * bN);
              final double blended = (lum * alpha) + (1.0 - alpha);
              final int c = blended >= 0.5 ? 255 : 0;
              qrImg.setPixelRgb(pixel.x, pixel.y, c, c, c);
            }

            const int targetWidth = 240; // multiple of 8, ~30mm at 203 DPI
            if (qrImg.width != targetWidth || qrImg.height != targetWidth) {
              qrImg = img.copyResize(
                qrImg,
                width: targetWidth,
                height: targetWidth,
                interpolation: img.Interpolation.nearest,
              );
            }

            debugPrint(
              'PrinterService: QR ${decodedQr.width}x${decodedQr.height} (fmt=${decodedQr.format}, ch=${decodedQr.numChannels}, alpha=${decodedQr.hasAlpha}, palette=${decodedQr.hasPalette}) -> ${qrImg.width}x${qrImg.height} RGB8',
            );

            bytes.addAll(const <int>[0x1B, 0x61, 0x01, 0x1B, 0x45, 0x01]);
            bytes.addAll('MRA E-INVOICE FISCAL QR\r\n'.codeUnits);
            bytes.addAll(const <int>[0x1B, 0x45, 0x00]);
            final profile = await CapabilityProfile.load();
            final generator = Generator(PaperSize.mm80, profile);
            const int sliceHeight = 128;
            for (int y = 0; y < qrImg.height; y += sliceHeight) {
              final int h = (y + sliceHeight <= qrImg.height) ? sliceHeight : (qrImg.height - y);
              final slice = img.copyCrop(qrImg, x: 0, y: y, width: qrImg.width, height: h);
              bytes.addAll(generator.imageRaster(slice, align: PosAlign.center));
            }
            if (cleanIrn.isNotEmpty) {
              bytes.addAll(const <int>[0x1B, 0x61, 0x01]);
              for (final ch in 'IRN: $cleanIrn'.codeUnits) {
                bytes.add((ch >= 0x20 && ch <= 0x7E) ? ch : 0x20);
              }
              bytes.addAll(const <int>[0x0D, 0x0A]);
            }
            bytes.addAll(const <int>[0x1B, 0x61, 0x00]);
          }
        } catch (qrErr) {
          debugPrint('PrinterService: skipping invalid fiscal QR bitmap: $qrErr');
        }
      } else if (cleanIrn.isNotEmpty) {
        bytes.addAll(const <int>[0x1B, 0x61, 0x01]);
        for (final ch in 'IRN: $cleanIrn'.codeUnits) {
          bytes.add((ch >= 0x20 && ch <= 0x7E) ? ch : 0x20);
        }
        bytes.addAll(const <int>[0x0D, 0x0A, 0x1B, 0x61, 0x00]);
      }

      // Feed 4 blank lines for clean manual tear-off past the cutter bar
      for (int i = 0; i < 4; i++) {
        bytes.add(0x0D);
        bytes.add(0x0A);
      }

      debugPrint('PrinterService: prepared ${bytes.length} bytes of clean ESC/POS text for $documentName');
      final bool success = await _writeBytesInChunks(bytes, chunkSize: 512);
      debugPrint('PrinterService: printThermalLinesViaBluetooth result: $success');
      return success;
    } catch (e, stack) {
      debugPrint('PrinterService.printThermalLinesViaBluetooth error: $e\n$stack');
      rethrow;
    }
  }

  Future<bool> printPdfViaBluetooth({
    required Uint8List pdfBytes,
    required String documentName,
  }) async {
    // Fast path: if these PDF bytes were produced by ThermalDoc.build(),
    // route directly to native ESC/POS text printing instead of slow rasterization.
    final cachedEntry = lookupPdfThermalEntry(pdfBytes);
    if (cachedEntry != null && cachedEntry.lines.isNotEmpty) {
      debugPrint(
        'PrinterService.printPdfViaBluetooth: routing $documentName (${cachedEntry.lines.length} lines) to native ESC/POS text',
      );
      return printThermalLinesViaBluetooth(
        lines: cachedEntry.lines,
        documentName: documentName,
        qrBase64: cachedEntry.qrBase64,
        fiscalIrn: cachedEntry.fiscalIrn,
      );
    }

    final printer = defaultBluetoothPrinter;
    if (printer == null || printer.macAddress == null || printer.macAddress!.isEmpty) {
      throw Exception(
        "No default Bluetooth printer configured. Please go to PRINTER MANAGEMENT and set your Sewoo LK-P43II as the default Bluetooth printer.",
      );
    }

    try {
      debugPrint('PrinterService.printPdfViaBluetooth starting for $documentName (${pdfBytes.length} bytes)');

      // 1. Connect to Sewoo Bluetooth Thermal Printer via SPP
      final isConnected = await connectBluetoothPrinter(printer.macAddress!);
      if (!isConnected) {
        throw Exception(
          "Could not connect to Bluetooth printer '${printer.name}' (${printer.macAddress}). Please ensure printer is powered on and in range.",
        );
      }

      // 2. Load ESC/POS Profile (Generic 80mm/104mm thermal printer)
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);
      List<int> bytes = [];

      bytes += generator.reset();

      // 3. Rasterize PDF pages at 203 DPI (native Sewoo LK-P43II resolution)
      int pageCount = 0;
      await for (final page in Printing.raster(pdfBytes, dpi: 203)) {
        pageCount++;
        debugPrint('PrinterService: rasterizing page $pageCount...');
        final pngBytes = await page.toPng();
        var image = img.decodeImage(pngBytes);
        if (image != null) {
          // Composite onto an opaque white background: Printing.raster renders
          // transparent RGBA (0,0,0,0) for empty paper, which esc_pos_utils_plus
          // grayscale+invert turns into solid black (255).
          final whiteBg = img.Image(width: image.width, height: image.height)
            ..clear(img.ColorRgba8(255, 255, 255, 255));
          img.compositeImage(whiteBg, image);
          image = whiteBg;

          // Constrain width to 832 dots (4.5" / 104 mm printable on LK-P43II @ 203 DPI)
          // and align to a multiple of 8 so esc_pos_utils_plus never hits its
          // fixed-length List.filled + insertAll bug on non-8-aligned widths (e.g. 831 px).
          final int clampedWidth = image.width > 832 ? 832 : image.width;
          final int alignedWidth = clampedWidth >= 8 ? (clampedWidth & ~7) : 8;
          if (image.width != alignedWidth) {
            image = img.copyResize(image, width: alignedWidth);
          }

          // Slice tall receipt images into vertical strips of 128 rows.
          // This keeps each GS v 0 raster command under 10 KB, completely preventing
          // buffer overflows in mobile thermal printers like Sewoo LK-P43II.
          const int sliceHeight = 128;
          for (int y = 0; y < image.height; y += sliceHeight) {
            final int h = (y + sliceHeight <= image.height) ? sliceHeight : (image.height - y);
            final slice = img.copyCrop(image, x: 0, y: y, width: image.width, height: h);
            bytes += generator.imageRaster(slice, align: PosAlign.center);
          }
        }
      }

      debugPrint('PrinterService: prepared ${bytes.length} bytes of raster ESC/POS data across $pageCount page(s)');

      // Feed paper for clean manual tear-off past the cutter bar
      bytes += generator.feed(4);

      // 4. Send directly to Bluetooth socket in chunks
      final bool success = await _writeBytesInChunks(bytes, chunkSize: 512);
      debugPrint('PrinterService: printPdfViaBluetooth result: $success');
      return success;
    } catch (e, stack) {
      debugPrint('PrinterService.printPdfViaBluetooth error: $e\n$stack');
      rethrow;
    }
  }

  Future<bool> openBluetoothSettings() async {
    try {
      final res = await _bluetoothChannel.invokeMethod<bool>('openBluetoothSettings');
      return res ?? true;
    } catch (e) {
      debugPrint('openBluetoothSettings native channel failed: $e');
      return false;
    }
  }
}
