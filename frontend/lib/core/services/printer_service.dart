import 'dart:convert';
import 'package:enterprise_auth_mobile/core/models/printer_device.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:enterprise_auth_mobile/core/services/tcp_print_service.dart';
import 'package:enterprise_auth_mobile/core/utils/zpl_generator.dart';
class PrinterService {
  static final PrinterService instance = PrinterService._internal();
  PrinterService._internal();

  late SharedPreferences _prefs;
  List<PrinterDevice> _printers = [];
  String? _defaultDirectIpPrinterId;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    
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
        );
        _printers = [defaultPrinter];
        _defaultDirectIpPrinterId = defaultPrinter.id;
        await _savePrinters();
      }
    }
    
    _defaultDirectIpPrinterId = _prefs.getString('default_direct_ip_printer_id') ?? _defaultDirectIpPrinterId;
  }

  Future<void> _savePrinters() async {
    final encoded = jsonEncode(_printers.map((e) => e.toJson()).toList());
    await _prefs.setString('printers_list', encoded);
  }



  List<PrinterDevice> get printers => List.unmodifiable(_printers);
  
  PrinterDevice? get defaultDirectIpPrinter {
    try {
      return _printers.firstWhere((p) => p.id == _defaultDirectIpPrinterId);
    } catch (_) {
      return null;
    }
  }

  Future<void> addPrinter(PrinterDevice printer) async {
    _printers.add(printer);
    await _savePrinters();
    
    // Auto-assign default if it's the first
    if (_defaultDirectIpPrinterId == null) {
      await setDefaultPrinter(printer.id);
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

    if (_defaultDirectIpPrinterId == id) {
      _defaultDirectIpPrinterId = null;
      await _prefs.remove('default_direct_ip_printer_id');
      final fallback = _printers.firstOrNull;
      if (fallback != null) await setDefaultPrinter(fallback.id);
    }
  }

  Future<void> setDefaultPrinter(String id) async {
    _defaultDirectIpPrinterId = id;
    await _prefs.setString('default_direct_ip_printer_id', id);
  }

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
  }
  Future<void> printEodReport({
    required String workOrder,
    required String dateStr,
    required List<dynamic> items,
  }) async {
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
  }
}
