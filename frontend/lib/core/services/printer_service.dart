import 'dart:convert';
import 'dart:io';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class NetPrinter {
  final String id;
  final String name;
  final String ip;
  final int port;
  final bool isDefault;

  NetPrinter({
    required this.id,
    required this.name,
    required this.ip,
    this.port = 9100,
    this.isDefault = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'ip': ip,
    'port': port,
    'isDefault': isDefault,
  };

  factory NetPrinter.fromJson(Map<String, dynamic> json) => NetPrinter(
    id: json['id'],
    name: json['name'],
    ip: json['ip'],
    port: json['port'],
    isDefault: json['isDefault'] ?? false,
  );

  NetPrinter copyWith({bool? isDefault, String? name, String? ip, int? port}) {
    return NetPrinter(
      id: this.id,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      isDefault: isDefault ?? this.isDefault,
    );
  }
}

class PrinterService {
  static final PrinterService instance = PrinterService._internal();
  PrinterService._internal();

  static const String _prefPrintersKey = 'saved_network_printers';

  List<NetPrinter> _printers = [];
  NetPrinter? _activePrinter;
  
  List<NetPrinter> get printers => _printers;
  NetPrinter? get activePrinter => _activePrinter;

  Future<void> init() async {
    await _loadPrinters();
  }

  Future<void> _loadPrinters() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_prefPrintersKey);
    
    if (data != null) {
      final List<dynamic> decoded = jsonDecode(data);
      _printers = decoded.map((p) => NetPrinter.fromJson(p)).toList();
      
      // Set active printer
      try {
        _activePrinter = _printers.firstWhere((p) => p.isDefault);
      } catch (_) {
        if (_printers.isNotEmpty) {
          _activePrinter = _printers.first;
        }
      }
    }
  }

  Future<void> _savePrinters() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(_printers.map((p) => p.toJson()).toList());
    await prefs.setString(_prefPrintersKey, encoded);
  }

  /// Adds a new printer to the list.
  Future<void> addPrinter(String name, String ip, int port) async {
    final newPrinter = NetPrinter(
      id: const Uuid().v4(),
      name: name,
      ip: ip,
      port: port,
      isDefault: _printers.isEmpty, // First printer is default
    );
    
    _printers.add(newPrinter);
    if (newPrinter.isDefault) {
      _activePrinter = newPrinter;
    }
    await _savePrinters();
  }

  /// Removes a printer and updates default if necessary.
  Future<void> removePrinter(String id) async {
    final wasDefault = _printers.any((p) => p.id == id && p.isDefault);
    _printers.removeWhere((p) => p.id == id);
    
    if (wasDefault && _printers.isNotEmpty) {
      _printers[0] = _printers[0].copyWith(isDefault: true);
      _activePrinter = _printers[0];
    } else if (_printers.isEmpty) {
      _activePrinter = null;
    }
    
    await _savePrinters();
  }

  /// Sets a printer as the default for the app.
  Future<void> setPrimaryPrinter(String id) async {
    _printers = _printers.map((p) {
      final isNowDefault = p.id == id;
      final updated = p.copyWith(isDefault: isNowDefault);
      if (isNowDefault) {
        _activePrinter = updated;
      }
      return updated;
    }).toList();
    
    await _savePrinters();
  }

  /// Tests connectivity to a specific IP/Port without saving.
  Future<bool> testConnection(String ip, int port) async {
    try {
      final socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 3));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isConnected() async {
    if (_activePrinter == null) return false;
    return await testConnection(_activePrinter!.ip, _activePrinter!.port);
  }

  Future<void> disconnect() async {
    // TCP sockets are managed per-print job.
  }

  Future<void> printLabel({
    required String soNumber,
    required String customerName,
    required String productCode,
    required double weight,
    required String unit,
    required String qrData,
  }) async {
    if (_activePrinter == null) {
      throw 'No printer selected. Please configure a printer in Settings.';
    }

    try {
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);
      List<int> bytes = [];

      bytes += generator.text("--------------------------------");
      bytes += generator.text("SALES ORDER", styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
      bytes += generator.feed(1);
      
      bytes += generator.text("SO NUMBER: $soNumber");
      
      String displayCust = customerName;
      if (displayCust.length > 25) {
        displayCust = displayCust.substring(0, 22) + "...";
      }
      bytes += generator.text("CUSTOMER: $displayCust");
      bytes += generator.text("PRODUCT: $productCode");
      
      bytes += generator.feed(1);
      bytes += generator.text("WEIGHT: ${weight.toStringAsFixed(2)} $unit", styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
      bytes += generator.feed(1);

      bytes += generator.text("   LABEL QR DATA:");
      bytes += generator.qrcode(qrData, size: QRSize.size4);
      
      bytes += generator.feed(2);
      bytes += generator.text("Enterprise Auth Project", styles: const PosStyles(align: PosAlign.center));
      bytes += generator.text("--------------------------------", styles: const PosStyles(align: PosAlign.center));
      bytes += generator.feed(3);
      bytes += generator.cut();

      // Transmission
      final socket = await Socket.connect(_activePrinter!.ip, _activePrinter!.port, timeout: const Duration(seconds: 5));
      socket.add(bytes);
      await socket.flush();
      await socket.close();
      
    } catch (e) {
      print('Network printing failed: $e');
      rethrow;
    }
  }
}
