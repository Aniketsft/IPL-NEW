import 'package:flutter/material.dart';
import 'package:enterprise_auth_mobile/core/widgets/industrial_module_layout.dart';

import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:enterprise_auth_mobile/core/widgets/industrial_module_layout.dart';
import 'package:enterprise_auth_mobile/core/services/printer_service.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  final PrinterService _printerService = PrinterService.instance;
  List<BluetoothInfo> _devices = [];
  bool _isLoading = false;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _refreshDevices();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final connected = await _printerService.isConnected();
    if (mounted) {
      setState(() => _isConnected = connected);
    }
  }

  Future<void> _refreshDevices() async {
    setState(() => _isLoading = true);
    try {
      final devices = await _printerService.getDevices();
      setState(() {
        _devices = devices;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error scanning devices: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF9800);
    const dark800 = Color(0xFF1E1E1E);

    return IndustrialModuleLayout(
      title: 'PRINTER SETTINGS',
      body: Column(
        children: [
          // ── Header Section ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: dark800,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isConnected ? Colors.green.withValues(alpha: 0.3) : Colors.white10,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: _isConnected ? Colors.green.withValues(alpha: 0.1) : Colors.white10,
                  child: Icon(
                    _isConnected ? Icons.print : Icons.print_disabled,
                    color: _isConnected ? Colors.green : Colors.grey,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isConnected ? 'PRINTER CONNECTED' : 'NOT CONNECTED',
                        style: TextStyle(
                          color: _isConnected ? Colors.green : Colors.white70,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      if (_isConnected && _printerService.connectedDeviceName != null)
                        Text(
                          _printerService.connectedDeviceName!,
                          style: const TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                if (_isConnected)
                  TextButton(
                    onPressed: () async {
                      await _printerService.disconnect();
                      _checkStatus();
                    },
                    child: const Text('DISCONNECT', style: TextStyle(color: Colors.redAccent)),
                  ),
              ],
            ),
          ),

          // ── Device List ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'PAIRED DEVICES',
                  style: TextStyle(color: Colors.grey, fontSize: 11, letterSpacing: 1),
                ),
                IconButton(
                  onPressed: _isLoading ? null : _refreshDevices,
                  icon: Icon(Icons.refresh, color: orange.withValues(alpha: 0.7), size: 18),
                ),
              ],
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: orange))
                : _devices.isEmpty
                    ? const Center(
                        child: Text(
                          'No paired devices found.\nPlease pair your printer in Android Settings.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white24, fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _devices.length,
                        itemBuilder: (context, index) {
                          final device = _devices[index];
                          final isThisDevice = _printerService.connectedDeviceName == device.name && _isConnected;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: dark800,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isThisDevice ? orange.withValues(alpha: 0.5) : Colors.transparent,
                              ),
                            ),
                            child: ListTile(
                              leading: const Icon(Icons.bluetooth, color: Colors.blueAccent),
                              title: Text(
                                device.name,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                device.macAdress,
                                style: const TextStyle(color: Colors.white38, fontSize: 11),
                              ),
                              trailing: isThisDevice
                                  ? const Icon(Icons.check_circle, color: orange)
                                  : ElevatedButton(
                                      onPressed: () async {
                                        setState(() => _isLoading = true);
                                        final success = await _printerService.connect(device.name, device.macAdress);
                                        setState(() => _isLoading = false);
                                        _checkStatus();
                                        if (success && mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Printer connected!')),
                                          );
                                        }
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.white10,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      child: const Text('CONNECT'),
                                    ),
                            ),
                          );
                        },
                      ),
          ),
          
          if (_isConnected)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _printerService.printLabel(
                    soNumber: "TEST-12345",
                    customerName: "TEST CUSTOMER",
                    productCode: "PRD-001",
                    weight: 12.5,
                    unit: "KG",
                    qrData: "TEST-SO|TEST-CUST|PRD-001|12.5|KG"
                  ),
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('PRINT TEST LABEL'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: orange,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
