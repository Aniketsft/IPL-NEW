import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:enterprise_auth_mobile/core/network_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'package:enterprise_auth_mobile/features/manufacturing/logic/eod_pdf_generator.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sync_bloc.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sync_event.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sync_state.dart';
import '../../../../core/widgets/industrial_module_layout.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/delivery_repository.dart';

// Model
class WorkOrderHeader {
  final String workOrder;
  final DateTime? date;

  WorkOrderHeader({required this.workOrder, this.date});

  factory WorkOrderHeader.fromJson(Map<String, dynamic> json) => WorkOrderHeader(
        workOrder: json['workOrder'] as String? ?? '',
        date: json['date'] != null ? DateTime.tryParse(json['date'].toString()) : null,
      );
}

class ProductionTrackingItem {
  final String soNumber;
  final String itemCode;
  final String description;
  final double quantity;
  final double manufactured;
  final String lotNumber;
  final String unit;
  final double conversion;
  final String location;
  final String statusLabel;
  final double eaQuantity;
  final DateTime? createdAt;

  const ProductionTrackingItem({
    required this.soNumber,
    required this.itemCode,
    required this.description,
    required this.quantity,
    required this.manufactured,
    required this.lotNumber,
    required this.unit,
    required this.conversion,
    required this.location,
    required this.statusLabel,
    this.eaQuantity = 0.0,
    this.createdAt,
  });

  DateTime? get expiryDate => createdAt?.add(const Duration(days: 5));

  factory ProductionTrackingItem.fromJson(Map<String, dynamic> json) =>
      ProductionTrackingItem(
        soNumber: json['soNumber'] as String? ?? '',
        itemCode: json['itemCode'] as String? ?? '',
        description: json['description'] as String? ?? '',
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
        manufactured: (json['manufactured'] as num?)?.toDouble() ?? 0.0,
        lotNumber: json['lotNumber'] as String? ?? '',
        unit: json['unit'] as String? ?? 'KG',
        conversion: (json['conversion'] as num?)?.toDouble() ?? 1.0,
        location: json['location'] as String? ?? '',
        statusLabel: json['statusLabel'] as String? ?? 'A',
        eaQuantity: (json['eaQuantity'] as num?)?.toDouble() ?? 0.0,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'].toString())
            : null,
      );

  Map<String, dynamic> toJson() => {
        'soNumber': soNumber,
        'itemCode': itemCode,
        'description': description,
        'quantity': quantity,
        'manufactured': manufactured,
        'lotNumber': lotNumber,
        'unit': unit,
        'conversion': conversion,
        'location': location,
        'statusLabel': statusLabel,
        'eaQuantity': eaQuantity,
        'createdAt': createdAt?.toIso8601String(),
      };
}

// Screen
class EndOfDayScreen extends StatefulWidget {
  final List<String> permissions;
  const EndOfDayScreen({super.key, required this.permissions});

  @override
  State<EndOfDayScreen> createState() => _EndOfDayScreenState();
}

class _EndOfDayScreenState extends State<EndOfDayScreen> {
  WorkOrderHeader? _selectedWorkOrder;
  List<WorkOrderHeader> _workOrders = [];
  List<ProductionTrackingItem> _summaryItems = [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;
  DateTime _selectedDate = DateTime.now();
  String _selectedSite = 'IPL';
  bool _isEodDone = false;
  bool _isSendingToX3 = false;

  bool get _canUpdateEod {
    return widget.permissions.contains('manufacturing.eod.update') ||
           widget.permissions.contains('manufacturing.eod.create') ||
           widget.permissions.contains('manufacturing.eod.delete');
  }

  static const _amber = Color(0xFFFF9800);

  @override
  void initState() {
    super.initState();
    _fetchWorkOrders();
    _fetchProductionSummary(_selectedDate, _selectedSite);
  }



  Future<void> _fetchWorkOrders() async {
    setState(() => _isLoading = true);
    try {
      // Try online first
      final networkService = context.read<NetworkService>();
      final response = await networkService.dio.get('Logistics/work-orders');
      
      final items = (response.data as List<dynamic>)
          .map((e) => WorkOrderHeader.fromJson(e as Map<String, dynamic>))
          .toList();

      setState(() {
        _workOrders = items;
        _errorMessage = null;
      });
      
      // Cache locally for offline use
      final db = LocalDatabaseHelper.instance;
      for (var item in items) {
        await db.insertWorkOrder({
          'workOrder': item.workOrder,
          'date': item.date?.toIso8601String(),
          'cachedAt': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      // Fallback to local DB
      final db = LocalDatabaseHelper.instance;
      final localData = await db.getAllWorkOrders();
      if (localData.isNotEmpty) {
        setState(() {
          _workOrders = localData.map((e) => WorkOrderHeader(
            workOrder: e['workOrder'] as String,
            date: e['date'] != null ? DateTime.tryParse(e['date'].toString()) : null,
          )).toList();
          _errorMessage = null;
        });
      } else {
        setState(() => _errorMessage = 'Failed to load work orders (Offline)');
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchProductionSummary(DateTime date, String site) async {
    setState(() => _isLoading = true);
    try {
      final repository = context.read<DeliveryRepository>();
      final db = LocalDatabaseHelper.instance;
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      
      // Fetch from server directly as the single source of truth
      final data = await repository.getProductionSummaryFromServer(date);
      final isDone = await db.isEodProcessAudited(dateStr);
      
      setState(() {
        _isEodDone = isDone;
        _summaryItems = data.map((e) => ProductionTrackingItem(
          soNumber: e['soNumber'] as String? ?? '',
          itemCode: e['itemCode'] as String? ?? '',
          description: e['description'] as String? ?? '',
          quantity: (e['quantity'] as num?)?.toDouble() ?? 0.0,
          manufactured: (e['manufactured'] as num?)?.toDouble() ?? 0.0,
          lotNumber: e['lotNumber'] as String? ?? '',
          unit: e['unit'] as String? ?? 'KG',
          conversion: (e['conversion'] as num?)?.toDouble() ?? 1.0,
          location: e['location'] as String? ?? 'IPLCH',
          statusLabel: e['statusLabel'] as String? ?? 'A',
          eaQuantity: (e['eaQuantity'] as num?)?.toDouble() ?? 0.0,
          createdAt: e['createdAt'] != null ? DateTime.tryParse(e['createdAt'].toString()) : null,
        )).toList();
        _errorMessage = null;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load: $e';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _completeEndOfDay() async {
    if (_selectedWorkOrder == null) {
      setState(() => _errorMessage = 'Please select a Work Order');
      return;
    }

    if (_summaryItems.isEmpty) {
      setState(() => _errorMessage = 'No products found to finalize');
      return;
    }

    // Read services before first async gap
    final networkService = context.read<NetworkService>();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Confirm End of Day', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to finalize the production for ${DateFormat('dd MMM yyyy').format(_selectedDate)}? This can only be done once.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _amber),
            child: const Text('CONFIRM', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSaving = true);
    try {
      final db = LocalDatabaseHelper.instance;
      final timestamp = DateTime.now().toIso8601String();

      // Clean up any previous unsynced snapshots for this Work Order to prevent duplicates
      await db.deleteUnsyncedStagingEodByWorkOrder(_selectedWorkOrder!.workOrder);

      // Insert staging EOD and local status
      for (var item in _summaryItems) {
        if (item.manufactured <= 0) continue; // Filter out zero-quantity items
        if (item.statusLabel != 'A') continue; // Only populate status A in stagingeod

        final mfgDate = item.createdAt ?? DateTime.now();
        final expiryDate = mfgDate.add(const Duration(days: 5));
        
        await db.insertStagingEod({
          'id': const Uuid().v4(),
          'soNumber': _selectedWorkOrder!.workOrder,
          'productCode': item.itemCode,
          'manufactured_quantity': item.manufactured,
          'timestamp': timestamp,
          'unit': item.unit,
          'location': item.location,
          'itemStatus': item.statusLabel,
          'expiryDate': expiryDate.toIso8601String(),
          'createdAt': mfgDate.toIso8601String(),
          'isSynced': 0,
          'location2': '',
          'location3': '',
          'ea_quantity': item.eaQuantity,
          'lot': item.lotNumber,
        });
      }

      await db.markEodCompleted(DateFormat('yyyy-MM-dd').format(_selectedDate), _selectedWorkOrder!.workOrder);
      await db.insertEodProcessAudit(
        eodDate: DateFormat('yyyy-MM-dd').format(_selectedDate),
        workOrderNumber: _selectedWorkOrder!.workOrder,
      );

      // Offline Audit Log
      await db.insertOfflineAuditLog(
        entity: 'EndOfDay',
        action: 'COMPLETE',
        payload: jsonEncode({
          'date': DateFormat('yyyy-MM-dd').format(_selectedDate),
          'workOrder': _selectedWorkOrder!.workOrder,
          'itemCount': _summaryItems.where((i) => i.manufactured > 0).length,
        }),
      );

      // Trigger BOM Expansion on server (Online Only)
      try {
        await networkService.dio.post('Logistics/complete-eod', data: {
          'workOrder': _selectedWorkOrder!.workOrder,
          'items': _summaryItems
              .where((e) => e.manufactured > 0) // Filter out zero-quantity items
              .map((e) => e.toJson())
              .toList(),
        });
        debugPrint('Server-side processing triggered successfully');
      } catch (e) {
        debugPrint('Server-side BOM expansion failed (offline or error): $e');
        // We don't throw here to allow local save to complete even if offline
      }

      setState(() {
        _isEodDone = true;
        _errorMessage = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('End of Day completed and saved locally.')),
        );
        _printReport();
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error saving EOD: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _printReport() async {
    try {
      await EodPdfGenerator.generateAndPrint(
        workOrder: _selectedWorkOrder?.workOrder ?? 'N/A',
        productionDate: _selectedDate,
        items: _summaryItems.where((item) => item.manufactured > 0).toList(),
      );
    } catch (e) {
      debugPrint('PDF Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate PDF: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _processProductionEod() async {
    if (!mounted) return;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final networkService = context.read<NetworkService>();

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

    // Phase 2: Sync succeeded — now confirm X3 export
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        title: Text('Export to Sage X3',
            style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
        content: Text(
          'Sync completed. This will process all pending production EOD records and import them into Sage X3.\nProceed?',
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _amber),
            child: const Text('PROCESS', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final completer = Completer<Map<String, dynamic>>();

    setState(() => _isSendingToX3 = true);

    syncBloc.add(StartX3SoapExportRequested(
      message: 'Exporting Production EOD to Sage X3...',
      exportAction: () async {
        try {
          final response = await networkService.dio.post(
            'Logistics/production-eod',
            options: Options(
              receiveTimeout: const Duration(minutes: 10),
              sendTimeout: const Duration(minutes: 10),
            ),
          );
          final data = response.data as Map<String, dynamic>? ?? {};
          // ✅ Log successful trigger to local SQLite
          await LocalDatabaseHelper.instance.insertX3SoapAudit(
            endpoint: 'Logistics/production-eod',
            status: 'Success',
            message: 'successCount=${data['successCount'] ?? 0}, failureCount=${data['failureCount'] ?? 0}',
          );
          completer.complete(data);
          return data;
        } on DioException catch (e) {
          final errorMsg = e.message ?? e.error?.toString() ?? 'DioException';
          // ❌ Log failed trigger to local SQLite
          await LocalDatabaseHelper.instance.insertX3SoapAudit(
            endpoint: 'Logistics/production-eod',
            status: 'Failed',
            message: errorMsg,
          );
          completer.completeError(errorMsg);
          throw errorMsg;
        } catch (e) {
          // ❌ Log unexpected error to local SQLite
          await LocalDatabaseHelper.instance.insertX3SoapAudit(
            endpoint: 'Logistics/production-eod',
            status: 'Failed',
            message: e.toString(),
          );
          completer.completeError(e.toString());
          rethrow;
        }
      },
    ));

    try {
      final data = await completer.future;
      if (mounted) {
        _showX3Results(data);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('X3 Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingToX3 = false);
    }
  }

  void _showX3Results(Map<String, dynamic> data) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final results = data['results'] as List? ?? [];
    final successCount = data['successCount'] ?? 0;
    final failureCount = data['failureCount'] ?? 0;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        title: Text(
          'PRODUCTION EOD — SAGE X3',
          style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _x3StatusChip('SUCCESS', successCount.toString(), Colors.green, isDark),
                  _x3StatusChip('FAILED', failureCount.toString(), Colors.red, isDark),
                ],
              ),
              Divider(color: isDark ? Colors.white12 : Colors.black12, height: 24),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final res = results[index] as Map<String, dynamic>? ?? {};
                    final bool success = res['success'] == true;
                    final List messages = res['messages'] as List? ?? [];
                    return Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        leading: Icon(
                          success ? Icons.check_circle : Icons.error,
                          color: success ? Colors.green : Colors.red,
                        ),
                        title: Text(
                          res['identifier']?.toString() ?? 'Unknown WO',
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
                        children: messages
                            .map((m) => Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                                ))
                            .toList(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CLOSE', style: TextStyle(color: _amber)),
          ),
        ],
      ),
    );
  }

  Widget _x3StatusChip(String label, String value, Color color, bool isDark) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 10)),
      ],
    );
  }

  // Build
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return IndustrialModuleLayout(
      title: 'END OF DAY',
      extraActions: [
        if (_isSendingToX3)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: _amber, strokeWidth: 2)),
          )
        else
          IconButton(
            tooltip: 'Export to Sage X3',
            icon: Icon(Icons.send_and_archive, color: _canUpdateEod ? _amber : Colors.grey),
            onPressed: (_isEodDone && _canUpdateEod) ? _processProductionEod : null,
          ),
      ],
      body: Column(
        children: [
          _dateFilter(isDark, theme),
          _workOrderFilter(isDark, theme),
          Expanded(
            child: _isLoading || _isSaving
                ? const Center(
                    child: CircularProgressIndicator(color: _amber),
                  )
                : _errorMessage != null
                    ? Center(child: _errorCard())
                    : _buildProductList(isDark, theme),
          ),
          if (_summaryItems.isNotEmpty && !_isLoading && !_isSaving)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  OutlinedButton.icon(
                    onPressed: _printReport,
                    icon: Icon(_isEodDone ? Icons.print : Icons.picture_as_pdf, size: 20),
                    label: Text(_isEodDone ? 'PRINT REPORT' : 'PREVIEW PDF'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _amber,
                      side: const BorderSide(color: _amber),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _actionButton(),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // Widgets

  Widget _dateFilter(bool isDark, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: InkWell(
        onTap: () async {
          final date = await showDatePicker(
            context: context,
            initialDate: _selectedDate,
            firstDate: DateTime(2020),
            lastDate: DateTime.now().add(const Duration(days: 1)),
            builder: (context, child) => Theme(
              data: Theme.of(context).copyWith(
                colorScheme: ColorScheme.dark(
                  primary: _amber,
                  onPrimary: Colors.black,
                  surface: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  onSurface: isDark ? Colors.white : Colors.black,
                ),
              ),
              child: child!,
            ),
          );
          if (date != null) {
            setState(() => _selectedDate = date);
            _fetchProductionSummary(date, _selectedSite);
          }
        },
        child: Row(
          children: [
            const Icon(Icons.calendar_today, color: _amber, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                DateFormat('d MMM yyyy').format(_selectedDate),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: Colors.white38),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Container(width: 1, height: 24, color: isDark ? Colors.white10 : Colors.black12),
            ),
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedSite,
                dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                items: ['IPL', 'SOP', 'SOPL']
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(s, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _amber)),
                        ))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedSite = val);
                    _fetchProductionSummary(_selectedDate, val);
                  }
                },
                icon: const Icon(Icons.location_on, color: _amber, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _workOrderFilter(bool isDark, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<WorkOrderHeader>(
          value: _selectedWorkOrder,
          isExpanded: true,
          hint: Text(
            _isLoading ? 'Loading Work Orders...' : 'Select Work Order',
            style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 14),
          ),
          dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          icon: const Icon(Icons.arrow_drop_down, color: _amber),
          items: _workOrders.map((w) {
            return DropdownMenuItem<WorkOrderHeader>(
              value: w,
              child: Text(
                w.workOrder,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            );
          }).toList(),
          onChanged: (v) {
            setState(() {
              _selectedWorkOrder = v;
            });
            // Selected work order just stays in memory for the final save
            // No need to fetch production data again, it's filtered by date now
          },
        ),
      ),
    );
  }

  Widget _buildProductList(bool isDark, ThemeData theme) {
    final displayItems = _summaryItems.where((item) {
      final isInternal = item.soNumber.startsWith('CUTS') ||
                         item.soNumber.startsWith('BLK');
      return item.manufactured > 0 || isInternal;
    }).toList();

    if (displayItems.isEmpty) {
      return Center(
        child: Text(
          'No production tracked for this date',
          style: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
        ),
      );
    }

    // Group by itemCode
    final Map<String, List<ProductionTrackingItem>> grouped = {};
    for (final item in displayItems) {
      grouped.putIfAbsent(item.itemCode, () => []).add(item);
    }

    final keys = grouped.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: keys.length,
      itemBuilder: (context, index) {
        final itemCode = keys[index];
        final items = grouped[itemCode]!;
        return _buildProductCard(itemCode, items, isDark, theme);
      },
    );
  }

  Widget _buildProductCard(String itemCode, List<ProductionTrackingItem> items, bool isDark, ThemeData theme) {
    final first = items.first;
    final totalQty = items.fold<double>(0, (sum, item) => sum + item.manufactured);
    final totalEa = items.fold<double>(0, (sum, item) => sum + item.eaQuantity);
    final isEA = first.unit.toUpperCase() == 'EA' || first.unit.toUpperCase() == 'PCS';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
      ),
      elevation: 0,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            itemCode,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          subtitle: Text(
            first.description,
            style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 12),
          ),
          trailing: SizedBox(
            width: 110,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center, 
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    isEA
                        ? '${totalQty.toStringAsFixed(2)} KG / ${totalEa.toStringAsFixed(2)} EA'
                        : '${totalQty.toStringAsFixed(2)} ${first.unit}',
                    style: const TextStyle(color: _amber, fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  '${items.length} Scans',
                  style: TextStyle(color: isDark ? Colors.white24 : Colors.black26, fontSize: 10),
                ),
              ],
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _row('DESCRIPTION', first.description, isDark),
                  _row('TOTAL (KG)', '${totalQty.toStringAsFixed(2)} KG', isDark),
                  if (isEA)
                    _row('TOTAL (EA)', '${totalEa.toStringAsFixed(2)} EA', isDark),
                  _row('LOCATION', first.location, isDark),
                  _row('LOT NUMBER', first.lotNumber, isDark),
                  _row('STATUS', first.statusLabel, isDark),
                  _row('PROD DATE', first.createdAt != null ? DateFormat('dd MMM yyyy HH:mm').format(first.createdAt!) : 'N/A', isDark),
                  _row('EXPIRY DATE', first.expiryDate != null ? DateFormat('dd MMM yyyy').format(first.expiryDate!) : 'N/A', isDark),
                ],
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ...items.map((item) => _buildScanRow(item, isDark)),
          ],
        ),
      ),
    );
  }

  Widget _buildScanRow(ProductionTrackingItem scan, bool isDark) {
    final isEA = scan.unit.toUpperCase() == 'EA' || scan.unit.toUpperCase() == 'PCS';
    final qtyDisplay = isEA 
        ? '${scan.manufactured.toStringAsFixed(2)} KG / ${scan.eaQuantity.toStringAsFixed(2)} EA'
        : '${scan.manufactured.toStringAsFixed(2)} ${scan.unit}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.label_outline, size: 14, color: isDark ? Colors.white38 : Colors.black38),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'LOT: ${scan.lotNumber.isNotEmpty ? scan.lotNumber : "N/A"}',
              style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87),
            ),
          ),
          Text(
            qtyDisplay,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _actionButton() => ElevatedButton.icon(
        onPressed: (_isSaving || _isEodDone || !_canUpdateEod) ? null : _completeEndOfDay,
        icon: const Icon(Icons.check_circle_outline, size: 20),
        label: Text(_isSaving ? 'COMPLETING...' : 'END OF DAY'),
        style: ElevatedButton.styleFrom(
          backgroundColor: (_isEodDone || !_canUpdateEod) ? Colors.grey : _amber,
          foregroundColor: (_isEodDone || !_canUpdateEod) ? Colors.white70 : Colors.black,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1),
        ),
      );

  Widget _row(String label, String value, bool isDark) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _errorCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 13),
              ),
            ),
          ],
        ),
      );


}
