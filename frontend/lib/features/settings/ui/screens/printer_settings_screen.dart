import 'package:flutter/material.dart';
import 'package:enterprise_auth_mobile/core/widgets/industrial_module_layout.dart';
import 'package:enterprise_auth_mobile/core/services/printer_service.dart';
import 'package:enterprise_auth_mobile/core/models/printer_device.dart';
import 'package:printing/printing.dart';
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
          ] else ...[
            const SizedBox(height: 24),
            _sectionHeader('SYSTEM PDF PRINTERS', isDark),
          ],
          
          _printerList(orange, isDark),
          const SizedBox(height: 16),
          _addPrinterButton(orange, isDark),

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

  Widget _printerList(Color orange, bool isDark) {
    final mode = PrinterService.instance.currentMode;
    final printers = PrinterService.instance.printers.where((p) => p.mode == mode).toList();
    
    if (printers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        child: Text(
          'No printers configured for this mode.',
          style: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: printers.length,
      itemBuilder: (context, index) {
        final printer = printers[index];
        final isDefault = (mode == PrintMode.directIp && PrinterService.instance.defaultDirectIpPrinter?.id == printer.id) ||
                          (mode == PrintMode.system && PrinterService.instance.defaultSystemPrinter?.id == printer.id);

        return ListTile(
          leading: Icon(mode == PrintMode.directIp ? Icons.print : Icons.picture_as_pdf, color: isDefault ? orange : Colors.grey),
          title: Text(printer.name, style: TextStyle(fontWeight: isDefault ? FontWeight.bold : FontWeight.normal)),
          subtitle: Text('${printer.printerModel}${printer.ipAddress != null ? ' - ${printer.ipAddress}:${printer.port}' : ''}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isDefault)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: orange.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                  child: Text('DEFAULT', style: TextStyle(color: orange, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () async {
                  await PrinterService.instance.removePrinter(printer.id);
                  setState(() {});
                },
              ),
            ],
          ),
          onTap: () async {
            await PrinterService.instance.setDefaultPrinter(printer.id, mode);
            setState(() {});
          },
        );
      },
    );
  }

  Widget _addPrinterButton(Color orange, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: ElevatedButton.icon(
        onPressed: () => _showAddEditPrinterDialog(context, orange, isDark),
        icon: const Icon(Icons.add),
        label: const Text('ADD PRINTER'),
        style: ElevatedButton.styleFrom(
          backgroundColor: orange.withValues(alpha: 0.1),
          foregroundColor: orange,
          elevation: 0,
        ),
      ),
    );
  }

  Future<void> _showAddEditPrinterDialog(BuildContext context, Color orange, bool isDark) async {
    final mode = PrinterService.instance.currentMode;
    final nameCtrl = TextEditingController();
    final modelCtrl = TextEditingController();
    final ipCtrl = TextEditingController();
    final portCtrl = TextEditingController(text: '9100');

    List<Printer>? availablePrinters;
    Printer? selectedPrinter;

    if (mode == PrintMode.system) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator()),
      );
      try {
        availablePrinters = await Printing.listPrinters();
      } catch (e) {
        availablePrinters = [];
      }
      if (!context.mounted) return;
      Navigator.pop(context); // Close loading indicator
    }

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text('Add ${mode == PrintMode.directIp ? 'Direct IP' : 'System PDF'} Printer'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (mode == PrintMode.system && availablePrinters != null) ...[
                  if (availablePrinters!.isEmpty)
                    const Text('No network printers discovered. Please ensure you are connected to the same network as your printers.', style: TextStyle(color: Colors.redAccent)),
                  if (availablePrinters!.isNotEmpty)
                    DropdownButtonFormField<Printer>(
                      decoration: const InputDecoration(labelText: 'Select Network Printer'),
                      value: selectedPrinter,
                      items: availablePrinters!.map((p) {
                        return DropdownMenuItem(
                          value: p,
                          child: Text(p.name, overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setStateDialog(() {
                          selectedPrinter = val;
                          if (val != null) {
                            nameCtrl.text = val.name;
                            modelCtrl.text = val.model ?? 'System Printer';
                            ipCtrl.text = val.url; // Use URL to store system printer connection info if needed
                          }
                        });
                      },
                    ),
                ],
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Printer Name (e.g. Warehouse 1)'),
                ),
                TextField(
                  controller: modelCtrl,
                  decoration: const InputDecoration(labelText: 'Printer Model (e.g. Zebra ZD421)'),
                ),
                if (mode == PrintMode.directIp) ...[
                  TextField(
                    controller: ipCtrl,
                    decoration: const InputDecoration(labelText: 'IP Address'),
                    keyboardType: TextInputType.number,
                  ),
                  TextField(
                    controller: portCtrl,
                    decoration: const InputDecoration(labelText: 'Port'),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: orange, foregroundColor: Colors.black),
              onPressed: () async {
                if (nameCtrl.text.isEmpty || modelCtrl.text.isEmpty) return;
                if (mode == PrintMode.directIp && ipCtrl.text.isEmpty) return;

                final newPrinter = PrinterDevice(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: nameCtrl.text,
                  printerModel: modelCtrl.text,
                  ipAddress: mode == PrintMode.directIp ? ipCtrl.text : (mode == PrintMode.system && selectedPrinter != null ? selectedPrinter!.url : null),
                  port: mode == PrintMode.directIp ? int.tryParse(portCtrl.text) : null,
                  mode: mode,
                );

                await PrinterService.instance.addPrinter(newPrinter);
                if (!ctx.mounted) return;
                if (mounted) setState(() {});
                Navigator.pop(ctx);
              },
              child: const Text('SAVE'),
            ),
          ],
        ),
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
              description: "INDUSTRIAL TEST PRODUCT",
              weight: 1.25,
              unit: "KG",
              qrData: "MULTI|TEST|DATA",
              lotNumber: "LOT-TEST-99",
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
