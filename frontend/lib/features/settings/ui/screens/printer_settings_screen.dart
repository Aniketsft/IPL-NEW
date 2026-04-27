import 'package:flutter/material.dart';
import 'package:enterprise_auth_mobile/core/widgets/industrial_module_layout.dart';
import 'package:enterprise_auth_mobile/core/services/printer_service.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    return IndustrialModuleLayout(
      title: 'PRINTER MANAGEMENT',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          _sectionHeader('PRINTING MODE', isDark),
          _modeSelector(orange, isDark),
          
          if (PrinterService.instance.currentMode == PrintMode.directIp) ...[
            const SizedBox(height: 24),
            _sectionHeader('IP THERMAL PRINTER SETTINGS', isDark),
            _ipSettings(orange, isDark),
          ],

          if (PrinterService.instance.currentMode == PrintMode.system) ...[
            const SizedBox(height: 24),
            _sectionHeader('INKJET / SYSTEM PRINTERS', isDark),
            _systemPrinterInfo(isDark),
          ],

          const SizedBox(height: 48),
          _testPrintButton(orange, isDark),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8),
      child: Text(
        title,
        style: TextStyle(
          color: isDark ? Colors.grey : Colors.grey[600], 
          fontSize: 12, 
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _modeSelector(Color orange, bool isDark) {
    final mode = PrinterService.instance.currentMode;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: SegmentedButton<PrintMode>(
        segments: const [
          ButtonSegment(value: PrintMode.system, label: Text('SYSTEM PDF'), icon: Icon(Icons.picture_as_pdf)),
          ButtonSegment(value: PrintMode.directIp, label: Text('DIRECT IP'), icon: Icon(Icons.lan)),
        ],
        selected: {mode},
        onSelectionChanged: (newSelection) async {
          await PrinterService.instance.setPrintMode(newSelection.first);
          setState(() {});
        },
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: orange,
          selectedForegroundColor: Colors.black,
          side: BorderSide(color: orange.withValues(alpha: 0.5)),
        ),
      ),
    );
  }

  Widget _ipSettings(Color orange, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        children: [
          TextField(
            controller: TextEditingController(text: PrinterService.instance.printerIp),
            decoration: InputDecoration(
              labelText: 'Printer IP Address',
              labelStyle: TextStyle(color: orange),
              prefixIcon: Icon(Icons.settings_ethernet, color: orange),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: orange.withValues(alpha: 0.3))),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: orange)),
            ),
            keyboardType: TextInputType.number,
            onChanged: (val) => PrinterService.instance.setPrinterIp(val),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: TextEditingController(text: PrinterService.instance.printerPort.toString()),
            decoration: InputDecoration(
              labelText: 'Port (Usually 9100)',
              labelStyle: TextStyle(color: orange),
              prefixIcon: Icon(Icons.numbers, color: orange),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: orange.withValues(alpha: 0.3))),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: orange)),
            ),
            keyboardType: TextInputType.number,
            onChanged: (val) => PrinterService.instance.setPrinterPort(int.tryParse(val) ?? 9100),
          ),
        ],
      ),
    );
  }

  Widget _systemPrinterInfo(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Text(
        'Uses standard PDF printing. Printers are discovered automatically via AirPrint or Android Print Services.',
        style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _testPrintButton(Color orange, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: OutlinedButton.icon(
        onPressed: _isLoading ? null : () async {
          setState(() => _isLoading = true);
          try {
            await PrinterService.instance.printLabel(
              soNumber: "TEST-BATCH-00x",
              customerName: "MANAGEMENT TEST",
              productCode: "THERMAL-TEST-1",
              weight: 1.25,
              unit: "KG",
              qrData: "MULTI|TEST|DATA"
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Test Print Sent'), backgroundColor: Colors.green),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Print Failed: $e'), backgroundColor: Colors.redAccent),
              );
            }
          } finally {
            if (mounted) setState(() => _isLoading = false);
          }
        },
        icon: _isLoading 
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.print_outlined),
        label: Text(_isLoading ? 'PRINTING...' : 'RUN TEST PRINT', style: const TextStyle(fontWeight: FontWeight.bold)),
        style: OutlinedButton.styleFrom(
          foregroundColor: orange,
          side: BorderSide(color: orange.withValues(alpha: 0.5), width: 2),
          padding: const EdgeInsets.symmetric(vertical: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}
