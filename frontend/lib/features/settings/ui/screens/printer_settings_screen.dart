import 'package:flutter/material.dart';
import 'package:enterprise_auth_mobile/core/widgets/industrial_module_layout.dart';
import 'package:enterprise_auth_mobile/core/services/printer_service.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  final PrinterService _printerService = PrinterService.instance;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    // Just refresh the UI to show current active/printers
    setState(() {});
  }

  void _showAddPrinterDialog() {
    final nameController = TextEditingController();
    final ipController = TextEditingController();
    final portController = TextEditingController(text: '9100');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'REGISTER NEW PRINTER',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 24),
            _buildDialogInput(nameController, 'DISPLAY NAME', 'e.g. Warehouse 1', Icons.label_outline),
            const SizedBox(height: 16),
            _buildDialogInput(ipController, 'IP ADDRESS', 'e.g. 192.168.1.100', Icons.lan_outlined),
            const SizedBox(height: 16),
            _buildDialogInput(portController, 'PORT', '9100', Icons.settings_ethernet, isNumeric: true),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final name = nameController.text.trim();
                  final ip = ipController.text.trim();
                  final portStr = portController.text.trim();
                  
                  if (name.isEmpty || ip.isEmpty) return;
                  
                  final port = int.tryParse(portStr) ?? 9100;
                  
                  Navigator.pop(context);
                  setState(() => _isLoading = true);
                  await _printerService.addPrinter(name, ip, port);
                  setState(() => _isLoading = false);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF9800),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('SAVE PRINTER'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogInput(TextEditingController controller, String label, String hint, IconData icon, {bool isNumeric = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white10),
            prefixIcon: Icon(icon, color: Colors.white24, size: 20),
            filled: true,
            fillColor: Colors.white.withAlpha(13),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF9800);
    const dark800 = Color(0xFF1E1E1E);

    return IndustrialModuleLayout(
      title: 'PRINTER MANAGEMENT',
      body: Column(
        children: [
          // ── Active Status ──────────────────────────────────────────────
          if (_printerService.activePrinter != null)
            _buildActivePrinterSummary(dark800, orange),

          // ── Printer List Header ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'SAVED PRINTERS',
                  style: TextStyle(color: Colors.grey, fontSize: 11, letterSpacing: 1),
                ),
                TextButton.icon(
                  onPressed: _showAddPrinterDialog,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('ADD NEW', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: orange),
                ),
              ],
            ),
          ),

          // ── Printer List ───────────────────────────────────────────────
          Expanded(
            child: _printerService.printers.isEmpty
                ? const Center(
                    child: Text(
                      'No printers saved.\nTap "ADD NEW" to register a printer.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white24, fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _printerService.printers.length,
                    itemBuilder: (context, index) {
                      final printer = _printerService.printers[index];
                      final isActive = _printerService.activePrinter?.id == printer.id;
                      
                      return _buildPrinterTile(printer, isActive, dark800, orange);
                    },
                  ),
          ),
          
          // ── Test Label Action ──────────────────────────────────────────
          if (_printerService.activePrinter != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _printerService.printLabel(
                    soNumber: "TEST-BATCH-00x",
                    customerName: "MANAGEMENT TEST",
                    productCode: "MULTI-PRNT",
                    weight: 1.0,
                    unit: "KG",
                    qrData: "MULTI|TEST|DATA"
                  ),
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('PRINT TEST ON PRIMARY'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white10),
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

  Widget _buildActivePrinterSummary(Color bgColor, Color accentColor) {
    final active = _printerService.activePrinter!;
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withAlpha(75)),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Colors.green,
            child: Icon(Icons.print, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SYSTEM PRIMARY',
                  style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1),
                ),
                Text(
                  active.name.toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Text(
                  '${active.ip}:${active.port}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrinterTile(NetPrinter printer, bool isActive, Color bgColor, Color accentColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isActive ? accentColor.withAlpha(127) : Colors.transparent),
      ),
      child: ListTile(
        onTap: () => _printerService.setPrimaryPrinter(printer.id).then((_) => setState(() {})),
        leading: Icon(
          isActive ? Icons.radio_button_checked : Icons.radio_button_off,
          color: isActive ? accentColor : Colors.white24,
        ),
        title: Text(
          printer.name,
          style: TextStyle(color: Colors.white, fontWeight: isActive ? FontWeight.bold : FontWeight.normal),
        ),
        subtitle: Text(
          '${printer.ip}:${printer.port}',
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.flash_on, size: 18),
              onPressed: () async {
                final success = await _printerService.testConnection(printer.ip, printer.port);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success ? 'Printer Online ✓' : 'Printer Offline ✗'),
                      backgroundColor: success ? Colors.green : Colors.redAccent,
                      duration: const Duration(seconds: 1),
                    ),
                  );
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
              onPressed: () => _printerService.removePrinter(printer.id).then((_) => setState(() {})),
            ),
          ],
        ),
      ),
    );
  }
}
