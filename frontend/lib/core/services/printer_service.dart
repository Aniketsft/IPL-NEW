import 'dart:convert';
import 'dart:typed_data';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrinterService {
  static final PrinterService instance = PrinterService._internal();
  PrinterService._internal();

  static const String _prefSelectedDeviceAddress = 'selected_printer_address';
  static const String _prefSelectedDeviceName = 'selected_printer_name';

  String? _connectedAddress;
  String? _connectedName;

  String? get connectedDeviceName => _connectedName;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _connectedAddress = prefs.getString(_prefSelectedDeviceAddress);
    _connectedName = prefs.getString(_prefSelectedDeviceName);
  }

  Future<List<BluetoothInfo>> getDevices() async {
    return await PrintBluetoothThermal.pairedBluetooths;
  }

  Future<bool> connect(String name, String address) async {
    try {
      final bool result = await PrintBluetoothThermal.connect(macPrinterAddress: address);
      if (result) {
        _connectedAddress = address;
        _connectedName = name;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefSelectedDeviceAddress, address);
        await prefs.setString(_prefSelectedDeviceName, name);
      }
      return result;
    } catch (e) {
      print('Printer connection error: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    await PrintBluetoothThermal.disconnect;
    _connectedAddress = null;
    _connectedName = null;
  }

  Future<bool> isConnected() async {
    return await PrintBluetoothThermal.connectionStatus;
  }

  Future<void> printLabel({
    required String soNumber,
    required String customerName,
    required String productCode,
    required double weight,
    required String unit,
    required String qrData,
  }) async {
    if (!(await isConnected())) {
      print('Printer not connected');
      return;
    }

    // Print Header
    await PrintBluetoothThermal.writeString(
      printText: PrintTextSize(text: "--------------------------------\n", size: 1)
    );
    
    // Body details
    await PrintBluetoothThermal.writeString(
      printText: PrintTextSize(text: "SO NUMBER: $soNumber\n", size: 1)
    );
        
    await PrintBluetoothThermal.writeString(
      printText: PrintTextSize(text: "CUSTOMER: ${customerName.length > 20 ? customerName.substring(0, 18) + '..' : customerName}\n", size: 1)
    );

    await PrintBluetoothThermal.writeString(
      printText: PrintTextSize(text: "PRODUCT: $productCode\n", size: 1)
    );
        
    await PrintBluetoothThermal.writeString(
      printText: PrintTextSize(text: "WEIGHT: ${weight.toStringAsFixed(2)} $unit\n", size: 3)
    );
    
    await PrintBluetoothThermal.writeString(
      printText: PrintTextSize(text: "\n", size: 1)
    );

    // QR Code
    await PrintBluetoothThermal.writeString(
      printText: PrintTextSize(text: "   LABEL QR DATA:\n", size: 1)
    ); 
    
    // We print the raw QR data string. Thermal printers often handle QR better as raw text 
    // if the library doesn't have a direct helper, or we can use the library's QR logic if available.
    // Given the current usage, we print the data string which is machine-readable once scanned.
    await PrintBluetoothThermal.writeString(
      printText: PrintTextSize(text: "$qrData\n", size: 1)
    );

    await PrintBluetoothThermal.writeString(
      printText: PrintTextSize(text: "\n\n", size: 1)
    );
    
    await PrintBluetoothThermal.writeString(
      printText: PrintTextSize(text: "Enterprise Auth Project\n", size: 1)
    );

    await PrintBluetoothThermal.writeString(
      printText: PrintTextSize(text: "--------------------------------\n\n\n", size: 1)
    );
  }
}
