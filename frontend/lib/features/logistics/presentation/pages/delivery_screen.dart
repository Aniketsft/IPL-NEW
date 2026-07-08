import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:enterprise_auth_mobile/core/widgets/industrial_module_layout.dart';
import '../widgets/sync_status_header.dart';
import '../../domain/entities/sales_order.dart';
import '../widgets/sales_order_card.dart';
import '../../data/repositories/delivery_repository.dart';
import 'package:enterprise_auth_mobile/core/utils/barcode_scanner/barcode_scanner_widget.dart';
import '../widgets/label_qr_generator.dart';
import 'package:enterprise_auth_mobile/core/utils/barcode_scanner/hardware_scanner_mixin.dart';
import '../bloc/sync_bloc.dart';
import '../bloc/sync_event.dart';
import '../bloc/sync_state.dart';

class DeliveryScreen extends StatefulWidget {
  final List<String> permissions;

  const DeliveryScreen({super.key, required this.permissions});

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> with HardwareScannerMixin<DeliveryScreen> {
  bool get _canUpdate {
    return widget.permissions.contains('logistics.delivery.update') ||
           widget.permissions.contains('logistics.delivery.create') ||
           widget.permissions.contains('logistics.delivery.delete');
  }
  @override
  void onHardwareScan(String data) {
    _processScan(data);
  }

  final String _lastSync = '2026-03-10 10:25'; // Mocked for UI demo
  List<SalesOrder> _orders = [];
  List<SalesOrder> _filteredOrders = [];
  bool _isLoading = false;
  String? _errorMessage;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _fetchOrders();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredOrders = List.from(_orders);
      } else {
        _filteredOrders = _orders.where((o) {
          return o.orderNumber.toLowerCase().contains(query) ||
                 o.customerName.toLowerCase().contains(query) ||
                 o.customerCode.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  Future<void> _fetchOrders() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repository = context.read<DeliveryRepository>();
      final soNumbers = await repository.getScannedDeliveryOrderNumbers();
      final results = await repository.fetchSalesOrderHeadersByNumbers(soNumbers);

      setState(() {
        _orders = results;
        _filteredOrders = results;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _scanManifest() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'SCAN CRATE OR PALETTE',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: AppBarcodeScanner(
                  onScan: (code) {
                    Navigator.pop(context);
                    _processScan(code);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _processScan(String rawData) async {
    setState(() => _isLoading = true);
    try {
      final parsed = LabelQrGenerator.parse(rawData);
      if (parsed.isEmpty || (parsed['type'] != 'CRATE' && parsed['type'] != 'PALETTE')) {
        throw 'Invalid label for delivery dispatch. Please scan a CRATE or PALETTE label.';
      }

      List<String> soList = [];
      if (parsed['type'] == 'CRATE') {
        final so = parsed['soNumber'] ?? '';
        if (so.isNotEmpty && so != 'N/A') soList.add(so);
      } else if (parsed['type'] == 'PALETTE') {
        final manifest = parsed['manifest'] ?? '';
        final parts = manifest.split(';');
        for (var part in parts) {
          final chunks = part.split(':');
          if (chunks.isNotEmpty && chunks[0].isNotEmpty) {
            soList.add(chunks[0]);
          }
        }
      }

      if (soList.isEmpty) throw 'No matching Sales Orders found in this QR payload.';

      final repository = context.read<DeliveryRepository>();
      await repository.addDeliveryScan(soList, rawData);

      await _fetchOrders();
      if (mounted) {
        final theme = Theme.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Successfully added to Manifest',
              style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
            ),
            backgroundColor: theme.colorScheme.surface,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        showDialog(
          context: context, 
          builder: (_) => AlertDialog(
            backgroundColor: isDark ? const Color(0xFF422222) : Colors.red[50], 
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red),
                const SizedBox(width: 8),
                Text('SCAN REJECTED', style: TextStyle(color: isDark ? Colors.white : Colors.red[900], fontWeight: FontWeight.bold)),
              ],
            ), 
            content: Text(e.toString(), style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)), 
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('OK', style: TextStyle(color: isDark ? Colors.white54 : Colors.red[900])),
              ),
            ],
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _manualLoadSalesOrder(String soCode) async {
    setState(() => _isLoading = true);
    try {
      final repository = context.read<DeliveryRepository>();
      final rawData = 'MANUAL:$soCode';
      await repository.addDeliveryScan([soCode], rawData);
      
      await _fetchOrders();
      if (mounted) {
        final theme = Theme.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Successfully loaded Sales Order $soCode',
              style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
            ),
            backgroundColor: theme.colorScheme.surface,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: isDark ? const Color(0xFF422222) : Colors.red[50],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red),
                const SizedBox(width: 8),
                Text('LOAD REJECTED', style: TextStyle(color: isDark ? Colors.white : Colors.red[900], fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(e.toString(), style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('OK', style: TextStyle(color: isDark ? Colors.white54 : Colors.red[900])),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showManualEntryDialog() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);
    List<SalesOrder> allClosedOrders = [];
    try {
      allClosedOrders = await context.read<DeliveryRepository>().fetchSalesOrderHeaders(
        status: 'closed',
        limit: 2000,
      );
    } catch (e) {
      // ignore
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }

    final loadedOrderNumbers = _orders.map((o) => o.orderNumber).toSet();

    final validOrderNumbers = allClosedOrders
        .where((o) => o.isPreparedForShipment == false && !loadedOrderNumbers.contains(o.orderNumber))
        .map((o) => o.orderNumber)
        .toList();

    if (!mounted) return;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;
    String currentText = '';

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: theme.colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: isDark ? Colors.white10 : Colors.black12,
              width: 1,
            ),
          ),
          title: Row(
            children: [
              Icon(Icons.edit_note_rounded, color: orange, size: 28),
              const SizedBox(width: 12),
              Text(
                'Manual Entry',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Search or enter the Sales Order number to manually load it into the manifest.',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                Autocomplete<String>(
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    final query = textEditingValue.text.trim().toLowerCase();
                    if (query.isEmpty) {
                      return const Iterable<String>.empty();
                    }
                    return validOrderNumbers.where((number) {
                      return number.toLowerCase().contains(query);
                    }).take(10);
                  },
                  onSelected: (String selection) {
                    currentText = selection;
                  },
                  fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                    controller.addListener(() {
                      currentText = controller.text;
                    });
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      autofocus: true,
                      textCapitalization: TextCapitalization.characters,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                      decoration: InputDecoration(
                        labelText: 'Sales Order Number',
                        labelStyle: TextStyle(color: orange),
                        hintText: 'e.g., 1234 or SO001234',
                        hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.black26),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: orange, width: 2),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDark ? Colors.white10 : Colors.black12,
                          ),
                        ),
                        filled: true,
                        fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                      ),
                      onSubmitted: (String value) {
                        onFieldSubmitted();
                        if (currentText.trim().isNotEmpty) {
                          Navigator.pop(context);
                          _manualLoadSalesOrder(currentText.trim());
                        }
                      },
                    );
                  },
                  optionsViewBuilder: (context, onSelected, options) {
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4.0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                        ),
                        color: theme.colorScheme.surface,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300),
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: options.length,
                            itemBuilder: (BuildContext context, int index) {
                              final option = options.elementAt(index);
                              return InkWell(
                                onTap: () => onSelected(option),
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Text(
                                    option,
                                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'CANCEL',
                style: TextStyle(
                  color: isDark ? Colors.white54 : Colors.black54,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                final text = currentText.trim();
                if (text.isNotEmpty) {
                  Navigator.pop(context);
                  _manualLoadSalesOrder(text);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              child: const Text(
                'LOAD',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _clearManifest() async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final repository = context.read<DeliveryRepository>();

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        title: Text(
          'Clear Manifest?',
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        content: Text(
          'This will clear the current unloading queue. Proceed?',
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true), 
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('CLEAR', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await repository.clearDeliveryScans();
      await _fetchOrders();
    }
  }

  Future<void> _processEndOfDay() async {
    if (!mounted) return;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;
    final repository = context.read<DeliveryRepository>();

    // Phase 1: Trigger sync first and wait for it to complete
    final syncBloc = context.read<SyncBloc>();
    syncBloc.add(const StartSyncRequested());

    final syncResult = await syncBloc.stream.firstWhere(
      (state) => state is SyncSuccess || state is SyncFailure,
    );

    if (!mounted) return;

    if (syncResult is SyncFailure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sync failed before sending to X3: ${syncResult.error}'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Phase 2: Sync succeeded — confirm X3 export
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        title: Text(
          'Export to Sage X3',
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        content: Text(
          'Sync completed. This will process all pending staging records and import them into Sage X3.\n Proceed?',
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true), 
            style: ElevatedButton.styleFrom(backgroundColor: orange),
            child: const Text('PROCESS', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final completer = Completer<Map<String, dynamic>>();

    setState(() => _isLoading = true);

    syncBloc.add(StartX3SoapExportRequested(
      message: 'Exporting Delivery Manifest to Sage X3...',
      exportAction: () async {
        try {
          final response = await repository.processEndOfDay();
          completer.complete(response);
          return response;
        } catch (e) {
          completer.completeError(e.toString());
          rethrow;
        }
      },
    ));

    try {
      final response = await completer.future;
      if (mounted) {
        _showEndOfDayResults(response);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red)
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showEndOfDayResults(Map<String, dynamic> data) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final results = data['results'] as List? ?? [];
    final successCount = data['successCount'] ?? 0;
    final failureCount = data['failureCount'] ?? 0;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        title: Text(
          'DELIVERY DISPATCH',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statusChip('SUCCESS', successCount.toString(), Colors.green, isDark),
                  _statusChip('FAILED', failureCount.toString(), Colors.red, isDark),
                ],
              ),
              Divider(color: isDark ? Colors.white12 : Colors.black12, height: 24),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final res = results[index];
                    final bool success = res['success'] ?? false;
                    final List messages = res['messages'] as List? ?? [];
                    
                    return Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        leading: Icon(
                          success ? Icons.check_circle : Icons.error,
                          color: success ? Colors.green : Colors.red,
                        ),
                        title: Text(
                          res['identifier'] ?? 'Unknown SO',
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          success ? 'Imported Successfully' : 'Import Failed',
                          style: TextStyle(
                            color: success 
                                ? (isDark ? Colors.green[200] : Colors.green[700]) 
                                : (isDark ? Colors.red[200] : Colors.red[700]),
                            fontSize: 12,
                          ),
                        ),
                        children: messages.map((m) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('• ', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
                              Expanded(
                                child: Text(
                                  m.toString(),
                                  style: TextStyle(
                                    color: isDark ? Colors.white70 : Colors.black87,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )).toList(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CLOSE', style: TextStyle(color: Color(0xFFFF9800)))),
        ],
      ),
    );
  }

  Widget _statusChip(String label, String value, Color color, bool isDark) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 10)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    return IndustrialModuleLayout(
      title: 'DELIVERY',
      extraActions: [
        IconButton(
          tooltip: 'End of Day Import',
          icon: Icon(Icons.send_and_archive, color: _canUpdate ? orange : Colors.grey),
          onPressed: _canUpdate ? _processEndOfDay : null,
        ),
      ],
      floatingActionButton: _canUpdate ? FloatingActionButton(
        onPressed: _showManualEntryDialog,
        backgroundColor: orange,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, size: 28),
      ) : null,
      body: Column(
        children: [
          SyncStatusHeader(lastSync: _lastSync),
          
          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                hintText: 'Search Scanned Manifest...',
                hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.black26),
                prefixIcon: Icon(Icons.search, color: isDark ? Colors.grey : Colors.grey[600]),
                filled: true,
                fillColor: theme.cardColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),

          // Scanner / Empty State OR List
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: orange))
                : _errorMessage != null
                ? Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)))
                : _filteredOrders.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.qr_code_scanner, size: 80, color: isDark ? Colors.grey[800] : Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text('No Items in Manifest', style: TextStyle(color: isDark ? Colors.grey : Colors.grey[600], fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text('Scan a Crate or Palette sequence to begin loading.', style: TextStyle(color: isDark ? Colors.grey : Colors.grey[600], fontSize: 12)),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _canUpdate ? _scanManifest : null,
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('START SCANNING'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: orange,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: isDark ? Colors.white12 : Colors.black12,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                        )
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _filteredOrders.length,
                    padding: const EdgeInsets.all(16),
                    itemBuilder: (context, index) {
                      return SalesOrderCard(
                        order: _filteredOrders[index],
                        onRefresh: _fetchOrders,
                        isDeliveryMode: true,
                        permissions: widget.permissions,
                      );
                    },
                  ),
          ),
          
          // Bottom Action Bar for active manifests
          if (_filteredOrders.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(top: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _canUpdate ? _clearManifest : null,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('CLEAR QUEUE'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red[300],
                        side: BorderSide(color: _canUpdate ? Colors.red[900]! : Colors.transparent),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _canUpdate ? _scanManifest : null,
                      icon: const Icon(Icons.add_a_photo),
                      label: const Text('SCAN NEXT'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: orange,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: isDark ? Colors.white12 : Colors.black12,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
