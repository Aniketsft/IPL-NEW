import 'package:flutter/material.dart';
import 'package:enterprise_auth_mobile/core/widgets/industrial_module_layout.dart';
import 'package:enterprise_auth_mobile/core/services/printer_service.dart';
import 'package:enterprise_auth_mobile/core/models/printer_device.dart';
import 'package:printing/printing.dart';

class PrinterSettingsScreen extends StatefulWidget {
  final List<String> permissions;
  const PrinterSettingsScreen({super.key, required this.permissions});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;
  bool _isBtLoading = false;

  bool get _canUpdate {
    return widget.permissions.contains('settings.printer.update') ||
        widget.permissions.contains('settings.printer.create') ||
        widget.permissions.contains('settings.printer.delete') ||
        widget.permissions.contains('admin') ||
        widget.permissions.contains('*') ||
        widget.permissions.isEmpty;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;
    final tabColor = isDark ? const Color(0xFF1E1E1E) : theme.cardColor;

    return IndustrialModuleLayout(
      title: 'PRINTER MANAGEMENT',
      body: Column(
        children: [
          Container(
            color: tabColor,
            child: TabBar(
              controller: _tabController,
              indicatorColor: orange,
              labelColor: orange,
              unselectedLabelColor: isDark ? Colors.white54 : Colors.black54,
              tabs: const [
                Tab(
                  icon: Icon(Icons.bluetooth),
                  text: 'BLUETOOTH',
                ),
                Tab(
                  icon: Icon(Icons.settings_ethernet),
                  text: 'IP THERMAL',
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildBluetoothTab(orange, isDark),
                _buildIpThermalTab(orange, isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BLUETOOTH PRINTER TAB
  // ---------------------------------------------------------------------------

  Widget _buildBluetoothTab(Color orange, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          _sectionHeader('BLUETOOTH THERMAL PRINTERS', isDark),
          const SizedBox(height: 8),
          _bluetoothPrinterList(orange, isDark),
          const SizedBox(height: 16),
          _addBluetoothPrinterButton(orange, isDark),
          const SizedBox(height: 36),
          _testPrintBluetoothButton(orange, isDark),
        ],
      ),
    );
  }

  Widget _bluetoothPrinterList(Color orange, bool isDark) {
    final printers = PrinterService.instance.printers
        .where((p) => p.mode == PrintMode.bluetooth)
        .toList();
    final defaultPrinter = PrinterService.instance.defaultBluetoothPrinter;

    if (printers.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
        padding: const EdgeInsets.all(24.0),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[900] : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
          ),
        ),
        child: Column(
          children: [
            Icon(Icons.bluetooth_searching, size: 48, color: orange.withValues(alpha: 0.7)),
            const SizedBox(height: 12),
            Text(
              'No Bluetooth Printer Configured',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Add a paired Bluetooth thermal printer to enable wireless van receipt & invoice printing. Configuration stays saved in phone memory.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white38 : Colors.black54,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: printers.length,
      itemBuilder: (context, index) {
        final printer = printers[index];
        final isDefault = defaultPrinter?.id == printer.id;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          elevation: isDefault ? 2 : 0,
          color: isDark
              ? (isDefault ? const Color(0xFF262626) : Colors.grey[900])
              : (isDefault ? Colors.orange.withValues(alpha: 0.05) : Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: isDefault
                  ? orange
                  : (isDark ? Colors.grey[800]! : Colors.grey[300]!),
              width: isDefault ? 1.5 : 0.8,
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: CircleAvatar(
              backgroundColor: isDefault
                  ? orange.withValues(alpha: 0.2)
                  : (isDark ? Colors.grey[800] : Colors.grey[200]),
              child: Icon(
                Icons.bluetooth_connected,
                color: isDefault ? orange : Colors.grey,
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    printer.name,
                    style: TextStyle(
                      fontWeight: isDefault ? FontWeight.bold : FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (isDefault)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: orange,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'DEFAULT',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Model: ${printer.printerModel}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                  ),
                  if (printer.macAddress != null && printer.macAddress!.isNotEmpty)
                    Text(
                      'Address: ${printer.macAddress}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                ],
              ),
            ),
            trailing: IconButton(
              icon: Icon(
                Icons.delete_outline,
                color: _canUpdate ? Colors.redAccent : Colors.grey,
              ),
              tooltip: 'Delete printer',
              onPressed: _canUpdate
                  ? () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete Printer'),
                          content: Text(
                            'Are you sure you want to remove "${printer.name}" from saved phone memory?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('CANCEL'),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                              ),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('DELETE'),
                            ),
                          ],
                        ),
                      );

                      if (confirmed == true) {
                        await PrinterService.instance.removePrinter(printer.id);
                        if (mounted) setState(() {});
                      }
                    }
                  : null,
            ),
            onTap: _canUpdate
                ? () async {
                    await PrinterService.instance.setDefaultPrinter(
                      printer.id,
                      PrintMode.bluetooth,
                    );
                    if (mounted) {
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${printer.name} set as default Bluetooth printer (Saved in phone memory).',
                          ),
                          backgroundColor: Colors.green,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  }
                : null,
          ),
        );
      },
    );
  }

  Widget _addBluetoothPrinterButton(Color orange, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: ElevatedButton.icon(
        onPressed: _canUpdate
            ? () => _showAddBluetoothPrinterDialog(context, orange, isDark)
            : null,
        icon: const Icon(Icons.add_circle_outline),
        label: const Text('ADD BLUETOOTH PRINTER'),
        style: ElevatedButton.styleFrom(
          backgroundColor: orange.withValues(alpha: 0.15),
          foregroundColor: orange,
          padding: const EdgeInsets.symmetric(vertical: 14),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: orange.withValues(alpha: 0.4)),
          ),
        ),
      ),
    );
  }

  Future<void> _showAddBluetoothPrinterDialog(
    BuildContext context,
    Color orange,
    bool isDark,
  ) async {
    await showDialog(
      context: context,
      builder: (ctx) => _BluetoothPrinterPickerDialog(
        orange: orange,
        isDark: isDark,
        onSaved: () {
          if (mounted) setState(() {});
        },
      ),
    );
  }

  Widget _testPrintBluetoothButton(Color orange, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: OutlinedButton.icon(
        onPressed: _isBtLoading
            ? null
            : () async {
                setState(() => _isBtLoading = true);
                try {
                  await PrinterService.instance.testPrintBluetooth();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Bluetooth Test Receipt Sent Successfully'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Bluetooth Print Failed: $e'),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                } finally {
                  if (mounted) setState(() => _isBtLoading = false);
                }
              },
        icon: _isBtLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.print_outlined),
        label: Text(
          _isBtLoading ? 'PRINTING TEST RECEIPT...' : 'RUN BLUETOOTH TEST PRINT',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: orange,
          side: BorderSide(color: orange.withValues(alpha: 0.5), width: 2),
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // IP THERMAL PRINTER TAB
  // ---------------------------------------------------------------------------

  Widget _buildIpThermalTab(Color orange, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          _sectionHeader('IP THERMAL PRINTER SETTINGS', isDark),
          const SizedBox(height: 8),
          _ipPrinterList(orange, isDark),
          const SizedBox(height: 16),
          _addIpPrinterButton(orange, isDark),
          const SizedBox(height: 36),
          _testPrintButton(orange, isDark),
        ],
      ),
    );
  }

  Widget _ipPrinterList(Color orange, bool isDark) {
    const mode = PrintMode.directIp;
    final printers =
        PrinterService.instance.printers.where((p) => p.mode == mode).toList();

    if (printers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        child: Text(
          'No direct IP printers configured.',
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
        final isDefault =
            PrinterService.instance.defaultDirectIpPrinter?.id == printer.id;

        return ListTile(
          leading: Icon(
            Icons.print,
            color: isDefault ? orange : Colors.grey,
          ),
          title: Text(
            printer.name,
            style: TextStyle(
              fontWeight: isDefault ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          subtitle: Text(
            '${printer.printerModel}${printer.ipAddress != null ? ' - ${printer.ipAddress}:${printer.port}' : ''}',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isDefault)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'DEFAULT',
                    style: TextStyle(
                      color: orange,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  color: _canUpdate ? Colors.redAccent : Colors.grey,
                ),
                onPressed: _canUpdate
                    ? () async {
                        await PrinterService.instance.removePrinter(printer.id);
                        setState(() {});
                      }
                    : null,
              ),
            ],
          ),
          onTap: _canUpdate
              ? () async {
                  await PrinterService.instance.setDefaultPrinter(
                    printer.id,
                    mode,
                  );
                  setState(() {});
                }
              : null,
        );
      },
    );
  }

  Widget _addIpPrinterButton(Color orange, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: ElevatedButton.icon(
        onPressed: _canUpdate
            ? () => _showAddEditIpPrinterDialog(context, orange, isDark)
            : null,
        icon: const Icon(Icons.add),
        label: const Text('ADD IP PRINTER'),
        style: ElevatedButton.styleFrom(
          backgroundColor: orange.withValues(alpha: 0.1),
          foregroundColor: orange,
          elevation: 0,
        ),
      ),
    );
  }

  Future<void> _showAddEditIpPrinterDialog(
    BuildContext context,
    Color orange,
    bool isDark,
  ) async {
    const mode = PrintMode.directIp;
    final nameCtrl = TextEditingController();
    final modelCtrl = TextEditingController();
    final ipCtrl = TextEditingController();
    final portCtrl = TextEditingController(text: '9100');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Direct IP Printer'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Printer Name (e.g. Warehouse 1)',
                ),
              ),
              TextField(
                controller: modelCtrl,
                decoration: const InputDecoration(
                  labelText: 'Printer Model (e.g. Zebra ZD421)',
                ),
              ),
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
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: orange,
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              if (nameCtrl.text.isEmpty || modelCtrl.text.isEmpty) return;
              if (ipCtrl.text.isEmpty) return;

              final newPrinter = PrinterDevice(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                name: nameCtrl.text,
                printerModel: modelCtrl.text,
                ipAddress: ipCtrl.text,
                port: int.tryParse(portCtrl.text),
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
    );
  }

  Widget _testPrintButton(Color orange, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: OutlinedButton.icon(
        onPressed: _isLoading
            ? null
            : () async {
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
                      const SnackBar(
                        content: Text('Test Print Sent'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Print Failed: $e'),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              },
        icon: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.print_outlined),
        label: Text(
          _isLoading ? 'PRINTING...' : 'RUN TEST PRINT',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: orange,
          side: BorderSide(color: orange.withValues(alpha: 0.5), width: 2),
          padding: const EdgeInsets.symmetric(vertical: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
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
}

class _BluetoothPrinterPickerDialog extends StatefulWidget {
  final Color orange;
  final bool isDark;
  final VoidCallback onSaved;

  const _BluetoothPrinterPickerDialog({
    required this.orange,
    required this.isDark,
    required this.onSaved,
  });

  @override
  State<_BluetoothPrinterPickerDialog> createState() => _BluetoothPrinterPickerDialogState();
}

class _BluetoothPrinterPickerDialogState extends State<_BluetoothPrinterPickerDialog> {
  List<Map<String, String>> _pairedDevices = [];
  bool _isLoading = true;
  bool _showManualEntry = false;

  final _nameCtrl = TextEditingController();
  final _modelCtrl = TextEditingController(text: 'ESC/POS 58mm');
  final _macCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _modelCtrl.dispose();
    _macCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDevices() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final devices = await PrinterService.instance.getPairedBluetoothDevices();
      if (mounted) {
        setState(() {
          _pairedDevices = devices;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _selectDevice(String name, String address) async {
    final newPrinter = PrinterDevice(
      id: address.isNotEmpty ? address : DateTime.now().millisecondsSinceEpoch.toString(),
      name: name.isNotEmpty ? name : 'Bluetooth Thermal Printer',
      printerModel: 'ESC/POS 58mm',
      macAddress: address,
      ipAddress: address,
      mode: PrintMode.bluetooth,
    );

    await PrinterService.instance.addPrinter(newPrinter);
    await PrinterService.instance.setDefaultPrinter(newPrinter.id, PrintMode.bluetooth);

    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onSaved();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✓ ${newPrinter.name} saved as default Bluetooth printer.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orange = widget.orange;
    final isDark = widget.isDark;

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.bluetooth, color: Colors.blueAccent, size: 22),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Select Bluetooth Printer',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 300, maxWidth: 450),
        child: SingleChildScrollView(
          child: _showManualEntry
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Printer Name *',
                        hintText: 'e.g. MPT-II Van Printer',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _modelCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Printer Model',
                        hintText: 'e.g. ESC/POS 58mm',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _macCtrl,
                      decoration: const InputDecoration(
                        labelText: 'MAC / Hardware Address',
                        hintText: 'e.g. 00:11:22:33:44:55',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () {
                            setState(() => _showManualEntry = false);
                          },
                          child: const Text('Back to Paired Devices'),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: orange,
                            foregroundColor: Colors.black,
                          ),
                          onPressed: () {
                            if (_nameCtrl.text.trim().isEmpty) return;
                            _selectDevice(_nameCtrl.text.trim(), _macCtrl.text.trim());
                          },
                          child: const Text('SAVE TO PHONE'),
                        ),
                      ],
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tap your paired printer to set it as default in phone memory:',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_isLoading)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(color: orange),
                              const SizedBox(height: 16),
                              Text(
                                'Scanning paired Bluetooth devices...',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white70 : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (_pairedDevices.isNotEmpty)
                      ..._pairedDevices.map((dev) {
                        final name = dev['name'] ?? 'Bluetooth Printer';
                        final addr = dev['address'] ?? '';
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          color: isDark ? const Color(0xFF282828) : Colors.grey[100],
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: orange.withValues(alpha: 0.3),
                            ),
                          ),
                          child: InkWell(
                            onTap: () => _selectDevice(name, addr),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: orange.withValues(alpha: 0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.print_outlined, color: orange, size: 20),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          name,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          addr.isNotEmpty ? 'MAC: $addr' : 'Bluetooth Device',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isDark ? Colors.white38 : Colors.black45,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: orange,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'SELECT',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      })
                    else
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[900] : Colors.grey[100],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.bluetooth_searching, size: 40, color: Colors.orange),
                            const SizedBox(height: 8),
                            const Text(
                              'No Paired Bluetooth Devices Found',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Please pair your thermal printer in Android Bluetooth settings first (PIN is usually 0000 or 1234).\n\nIf recently hot-reloaded, please fully stop and re-run the app (flutter run) to bind Android native channels.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white54 : Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 14),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: orange,
                                foregroundColor: Colors.black,
                              ),
                              icon: const Icon(Icons.settings_bluetooth, size: 18),
                              label: const Text('OPEN BLUETOOTH SETTINGS'),
                              onPressed: () async {
                                final opened = await PrinterService.instance.openBluetoothSettings();
                                if (!opened && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Please open phone Settings → Bluetooth directly, or re-run the app (flutter run).',
                                      ),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Refresh', style: TextStyle(fontSize: 12)),
                          onPressed: _loadDevices,
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() => _showManualEntry = true);
                          },
                          child: const Text(
                            'Enter manually',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CLOSE'),
        ),
      ],
    );
  }
}
