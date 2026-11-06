import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_event.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_state.dart';
import 'package:enterprise_auth_mobile/features/inventory/ui/screens/qr_label_screen.dart';
import 'package:enterprise_auth_mobile/features/manufacturing/ui/screens/manufacturing_screen.dart';
import 'package:enterprise_auth_mobile/features/settings/ui/screens/settings_modules_screen.dart';
import 'package:enterprise_auth_mobile/features/settings/ui/screens/printer_settings_screen.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/pages/delivery_screen.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/pages/sales_invoice/customer_selection_screen.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/pages/sales_invoice/sales_reports_screen.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/pages/sales_invoice/otp_generation_screen.dart';
import 'package:enterprise_auth_mobile/core/theme_cubit.dart';
import 'package:enterprise_auth_mobile/features/administration/ui/screens/user_management_screen.dart';
import 'package:enterprise_auth_mobile/features/administration/ui/screens/devices_screen.dart';
import 'package:enterprise_auth_mobile/features/administration/ui/screens/sync_logs_screen.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'package:enterprise_auth_mobile/features/manufacturing/bloc/manufacturing_bloc.dart';
import 'package:enterprise_auth_mobile/features/manufacturing/bloc/manufacturing_state.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sync_bloc.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sync_state.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/widgets/sync_overlay.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_sync_bloc.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_sync_event.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_sync_state.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/widgets/sales_invoice_sync_overlay.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/widgets/sales_rep_selection_dialog.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/widgets/sync_soap_error_modal.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/sales_invoice_sync_repository.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatefulWidget {
  final String username;
  final List<String> permissions;

  static String? _promptedSessionUser;

  static void resetSessionPrompt() {
    _promptedSessionUser = null;
  }

  const HomeScreen({
    super.key,
    required this.username,
    required this.permissions,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  String _lastSyncStr = 'Never';
  List<Map<String, dynamic>> _selectedSalesReps = [];
  bool _syncJustSucceeded = false;
  bool _isManualHomeSyncTriggered = false;
  bool _lastSyncWasExportOnly = false;
  UnsyncedSummary _unsyncedSummary = const UnsyncedSummary();

  bool _hasAccess(String permissionString) {
    return widget.permissions.contains(permissionString);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadLastSync();
    _loadUnsyncedSummary();
    _loadSelectedSalesReps();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndPromptSalesRepSelection();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HomeScreen.resetSessionPrompt();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadLastSync();
      _loadUnsyncedSummary();
    }
  }

  Future<void> _loadSelectedSalesReps() async {
    try {
      final reps = await LocalDatabaseHelper.instance.getSelectedSalesReps(
        username: widget.username,
      );
      if (mounted) {
        setState(() {
          _selectedSalesReps = reps;
        });
      }
    } catch (e) {
      debugPrint("Home: Error loading selected sales reps: $e");
    }
  }

  Future<void> _checkAndPromptSalesRepSelection({bool force = false}) async {
    await _loadSelectedSalesReps();
    if (!mounted) return;

    // Guard: On initial startup or before data sync, SQLite has 0 sales reps.
    // Never show an empty blocking dialog when no local data exists yet.
    final repCount = await LocalDatabaseHelper.instance.getSalesRepsCount();
    if (repCount == 0) {
      debugPrint("Home: Skipping sales rep prompt - local database has 0 sales reps. Waiting for initial sync.");
      if (force && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No sales representatives found locally. Please perform Data Sync first.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final isNewLoginPrompt = HomeScreen._promptedSessionUser != widget.username;
    if (_selectedSalesReps.isEmpty || force || isNewLoginPrompt) {
      HomeScreen._promptedSessionUser = widget.username;
      final authState = context.read<AuthBloc>().state;
      final siteCode = (authState is Authenticated &&
              authState.siteCode != null &&
              authState.siteCode!.isNotEmpty &&
              authState.siteCode != 'ALL')
          ? authState.siteCode
          : null;

      final syncRepo = context.read<SalesInvoiceSyncRepository>();
      await SalesRepSelectionDialog.show(
        context,
        canDismiss: _selectedSalesReps.isNotEmpty && !force && !isNewLoginPrompt,
        userSiteCode: siteCode,
        syncRepository: syncRepo,
        username: widget.username,
      );
      await _loadSelectedSalesReps();
    }
  }

  Future<void> _loadLastSync() async {
    try {
      final history = await LocalDatabaseHelper.instance.getSyncHistory();
      if (history.isNotEmpty) {
        // Find latest 'Success' or 'Partial' entry
        final last = history.firstWhere(
          (h) => h[LocalDatabaseHelper.colSyncStatus] == 'Success' || h[LocalDatabaseHelper.colSyncStatus] == 'Partial',
          orElse: () => history.first,
        );
        final timestampStr =
            last[LocalDatabaseHelper.colSyncTimestamp] as String?;
        if (timestampStr != null && timestampStr.isNotEmpty) {
          final timestamp = DateTime.tryParse(timestampStr);
          if (timestamp != null) {
            if (mounted) {
              setState(() {
                _lastSyncStr = DateFormat('yyyy-MM-dd HH:mm').format(timestamp.toLocal());
              });
            }
            return;
          }
        }
      }

      // Fallback to SharedPreferences if tbl_sync_history has no records yet
      final prefs = await SharedPreferences.getInstance();
      final prefTimestampStr = prefs.getString('last_sync_timestamp');
      if (prefTimestampStr != null && prefTimestampStr.isNotEmpty) {
        final prefTimestamp = DateTime.tryParse(prefTimestampStr);
        if (prefTimestamp != null) {
          if (mounted) {
            setState(() {
              _lastSyncStr = DateFormat('yyyy-MM-dd HH:mm').format(prefTimestamp.toLocal());
            });
          }
          return;
        }
      }
    } catch (e) {
      debugPrint("Home: Error loading last sync: $e");
    }
  }

  Future<void> _loadUnsyncedSummary() async {
    try {
      final summary = await LocalDatabaseHelper.instance.getUnsyncedSummary();
      if (mounted) {
        setState(() {
          _unsyncedSummary = summary;
        });
      }
    } catch (e) {
      debugPrint("Home: Error loading unsynced summary: $e");
    }
  }

  void _triggerSync() {
    _lastSyncWasExportOnly = false;
    final authState = context.read<AuthBloc>().state;
    final siteCode = (authState is Authenticated &&
            authState.siteCode != null &&
            authState.siteCode!.isNotEmpty &&
            authState.siteCode != 'ALL')
        ? authState.siteCode
        : null;

    if (siteCode == null || siteCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot sync: No assigned site code found for logged in user.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    _isManualHomeSyncTriggered = true;
    context.read<SalesInvoiceSyncBloc>().add(
          StartSalesInvoiceSyncRequested(siteCode: siteCode),
        );

    // Periodically check if sync is done to refresh timestamp & unsynced counts
    Future.delayed(const Duration(seconds: 3), () {
      _loadLastSync();
      _loadUnsyncedSummary();
    });
    Future.delayed(const Duration(seconds: 10), () {
      _loadLastSync();
      _loadUnsyncedSummary();
    });
  }

  void _triggerExportToX3() {
    final authState = context.read<AuthBloc>().state;
    final siteCode = (authState is Authenticated &&
            authState.siteCode != null &&
            authState.siteCode!.isNotEmpty &&
            authState.siteCode != 'ALL')
        ? authState.siteCode
        : null;

    if (siteCode == null || siteCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot export: No assigned site code found for logged in user.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    _lastSyncWasExportOnly = true;
    _isManualHomeSyncTriggered = true;
    context.read<SalesInvoiceSyncBloc>().add(
          StartSalesInvoiceSyncRequested(siteCode: siteCode, uploadOnly: true),
        );

    // Periodically check if sync is done to refresh timestamp & unsynced counts
    Future.delayed(const Duration(seconds: 2), () {
      _loadLastSync();
      _loadUnsyncedSummary();
    });
    Future.delayed(const Duration(seconds: 6), () {
      _loadLastSync();
      _loadUnsyncedSummary();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return BlocListener<SalesInvoiceSyncBloc, SalesInvoiceSyncState>(
      listener: (context, salesSyncState) {
        if (salesSyncState is SalesInvoiceSyncSuccess) {
          _loadLastSync();
          _loadUnsyncedSummary();

          if (_isManualHomeSyncTriggered) {
            _isManualHomeSyncTriggered = false;
            if (salesSyncState.batchResult.hasUploadItems || salesSyncState.batchResult.hasFailures) {
              SyncSoapErrorModal.showResults(
                context,
                batchResult: salesSyncState.batchResult,
                onRetry: _lastSyncWasExportOnly ? _triggerExportToX3 : _triggerSync,
                onDismiss: () {
                  context.read<SalesInvoiceSyncBloc>().add(const ResetSalesInvoiceSyncRequested());
                },
              );
            } else {
              _syncJustSucceeded = true;
              if (_lastSyncWasExportOnly && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Export to X3: All documents already synchronized to Sage X3.'),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            }
          } else {
            if (salesSyncState.batchResult.isCleanSuccess) {
              _syncJustSucceeded = true;
            }
          }
        } else if (salesSyncState is SalesInvoiceSyncFailure) {
          _loadLastSync();
          _loadUnsyncedSummary();

          if (_isManualHomeSyncTriggered) {
            _isManualHomeSyncTriggered = false;
            final failedReports = salesSyncState.batchResult?.failedReports.isNotEmpty == true
                ? salesSyncState.batchResult!.failedReports
                : [
                    SyncEntityReport(
                      entityName: 'Sage X3 Global Sync',
                      direction: SyncDirection.upload,
                      status: SyncStatus.failed,
                      errorCode: 'ERR_SYNC_FAILED',
                      userMessage: salesSyncState.error,
                      messages: [salesSyncState.error],
                    ),
                  ];
            SyncSoapErrorModal.show(
              context,
              failedReports: failedReports,
              allReports: salesSyncState.batchResult?.uploadReports.isNotEmpty == true
                  ? salesSyncState.batchResult!.uploadReports
                  : failedReports,
              failureCount: salesSyncState.batchResult?.failures.isNotEmpty == true ? salesSyncState.batchResult!.failures.length : 1,
              successCount: salesSyncState.batchResult?.successes.length ?? 0,
              onRetry: _lastSyncWasExportOnly ? _triggerExportToX3 : _triggerSync,
              onDismiss: () {
                context.read<SalesInvoiceSyncBloc>().add(const ResetSalesInvoiceSyncRequested());
              },
            );
          }
        } else if (salesSyncState is SalesInvoiceSyncInitial && _syncJustSucceeded) {
          _syncJustSucceeded = false;
          _loadLastSync();
          _loadUnsyncedSummary();
          // After sync is successfully finished and dismissed, prompt to select sales rep if needed
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _checkAndPromptSalesRepSelection();
            }
          });
        }
      },
      child: BlocBuilder<SyncBloc, SyncState>(
        builder: (context, syncState) {
          return BlocBuilder<ManufacturingBloc, ManufacturingState>(
            builder: (context, mfgState) {
              return BlocBuilder<SalesInvoiceSyncBloc, SalesInvoiceSyncState>(
                builder: (context, salesSyncState) {
                  final isSyncing =
                      syncState is SyncInProgress ||
                      mfgState is ManufacturingSyncProgress ||
                      salesSyncState is SalesInvoiceSyncInProgress;

                  return PopScope(
                    canPop: false,
                    onPopInvoked: (didPop) async {
                      if (didPop) return;
                      if (isSyncing) return; // Block exiting during sync
                      final bool? shouldExit = await _showExitConfirmation(context);
                      if (shouldExit == true) {
                        SystemNavigator.pop();
                      }
                    },
                    child: Scaffold(
                          backgroundColor: theme.scaffoldBackgroundColor,
                          appBar: AppBar(
                            backgroundColor: theme.colorScheme.surface,
                            elevation: 0,
                            leading: Builder(
                              builder: (context) => IconButton(
                                icon: Icon(
                                  Icons.menu,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                                onPressed: isSyncing
                                    ? null
                                    : () => Scaffold.of(context).openDrawer(),
                              ),
                            ),
                            title: Text(
                              'HIPO CLOUD',
                              style: TextStyle(
                                color: theme.primaryColor,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                            actions: [
                              IconButton(
                                key: const Key('btn_export_to_x3'),
                                tooltip: 'Export to X3',
                                icon: _unsyncedSummary.salesCount > 0
                                    ? Badge.count(
                                        count: _unsyncedSummary.salesCount,
                                        backgroundColor: const Color(0xFFF57C00),
                                        textColor: Colors.white,
                                        child: const Icon(
                                          Icons.send_and_archive,
                                          color: Color(0xFFF57C00),
                                        ),
                                      )
                                    : Icon(
                                        Icons.send_and_archive,
                                        color: isDark ? Colors.white70 : Colors.black87,
                                      ),
                                onPressed: isSyncing ? null : _triggerExportToX3,
                              ),
                              IconButton(
                                icon: Icon(
                                  isDark
                                      ? Icons.light_mode_rounded
                                      : Icons.dark_mode_rounded,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                                onPressed: isSyncing
                                    ? null
                                    : () => context.read<ThemeCubit>().toggleTheme(),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ),
                          drawer: isSyncing ? null : _buildDrawer(context),
                          body: _buildBody(context),
                        ),
                    );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<bool?> _showExitConfirmation(BuildContext context) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Confirm Exit',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to close the application?',
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primaryColor,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'EXIT APP',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (!widget.permissions.any((p) => p.startsWith('app.home.'))) {
      return _buildRestrictedUI(
        context,
        'NO PERMISSIONS ASSIGNED',
        'Your account (${widget.username}) does not have dashboard access. Please contact your system administrator.',
      );
    }

    final bool hasSalesman = _hasAccess('logistics.salesman.read') ||
        _hasAccess('logistics.sales_invoice.read') ||
        widget.permissions.any((p) => p.startsWith('logistics.sales.'));
    final bool hasReports = _hasAccess('logistics.reports.read') ||
        _hasAccess('logistics.sales.reports.read');
    final bool hasOtp = _hasAccess('logistics.otp_generation.read') ||
        _hasAccess('logistics.sales.supervisor_otp.read');

    final bool hasPending = _unsyncedSummary.hasUnsynced;
    final int pendingTotal = _unsyncedSummary.totalCount;

    final List<Widget> menuItems = [
      _buildMenuButton(
        context,
        'Data Sync',
        hasPending ? Icons.sync_problem_rounded : Icons.sync_rounded,
        null,
        onTapOverride: _triggerSync,
        subtitle: hasPending
            ? '⚠️ $pendingTotal items to sync\nLast: $_lastSyncStr'
            : '✓ Up to date\nLast: $_lastSyncStr',
        badgeCount: pendingTotal,
        isWarning: hasPending,
        badgeLabel: hasPending ? '$pendingTotal Pending' : null,
      ),
      if (_hasAccess('logistics.delivery.read'))
        _buildMenuButton(
          context,
          'Delivery',
          Icons.local_shipping_rounded,
          DeliveryScreen(permissions: widget.permissions),
        ),
      if (hasSalesman)
        _buildMenuButton(
          context,
          'Sales',
          Icons.point_of_sale_rounded,
          null,
          onTapOverride: () async {
            if (_selectedSalesReps.isEmpty) {
              await _checkAndPromptSalesRepSelection(force: true);
              if (_selectedSalesReps.isEmpty && mounted) {
                final repCount =
                    await LocalDatabaseHelper.instance.getSalesRepsCount();
                if (repCount > 0) {
                  return;
                }
              }
            }
            if (context.mounted) {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CustomerSelectionScreen(),
                  settings:
                      const RouteSettings(name: '/sales_customer_selection'),
                ),
              );
              _loadUnsyncedSummary();
              _loadLastSync();
            }
          },
        ),
      if (hasReports)
        _buildMenuButton(
          context,
          'Sales Reports',
          Icons.analytics_rounded,
          SalesReportsScreen(permissions: widget.permissions),
          subtitle: 'Sales & EOD PDF',
        ),
      if (hasOtp)
        _buildMenuButton(
          context,
          'OTP Generation',
          Icons.pin_outlined,
          const OtpGenerationScreen(),
          subtitle: 'Supervisor Override PIN',
        ),
      if (_hasAccess('manufacturing.all.read'))
        _buildMenuButton(
          context,
          'Manufacturing',
          Icons.precision_manufacturing_rounded,
          ManufacturingScreen(permissions: widget.permissions),
        ),

      if (_hasAccess('inventory.by_identifier.read'))
        _buildMenuButton(
          context,
          'QR Label',
          Icons.qr_code_scanner_rounded,
          QrLabelScreen(permissions: widget.permissions),
        ),
      if (_hasAccess('settings.printer.read'))
        _buildMenuButton(
          context,
          'Printer Settings',
          Icons.print_rounded,
          PrinterSettingsScreen(permissions: widget.permissions),
        ),
    ];

    if (menuItems.isEmpty) {
      return _buildRestrictedUI(
        context,
        'NO AUTHORIZED MODULES',
        'Your account has permissions ${widget.permissions.take(3).toList()}... but none match the dashboard modules.',
      );
    }

    return Column(
      children: [
        _buildSalesRepBanner(context, theme, isDark),
        Expanded(
          child: GridView.count(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.9,
            children: menuItems,
          ),
        ),
      ],
    );
  }

  Widget _buildSalesRepBanner(
    BuildContext context,
    ThemeData theme,
    bool isDark,
  ) {
    final hasReps = _selectedSalesReps.isNotEmpty;
    final repText = hasReps
        ? _selectedSalesReps
            .map((r) => '${r['code']} (${r['name']})')
            .join(', ')
        : 'None selected (Tap to choose active reps)';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      decoration: BoxDecoration(
        color: hasReps
            ? (isDark ? Colors.blueGrey.shade900.withOpacity(0.6) : Colors.blue.shade50)
            : (isDark ? Colors.red.shade900.withOpacity(0.4) : Colors.amber.shade50),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasReps
              ? theme.primaryColor.withOpacity(0.3)
              : Colors.amber.withOpacity(0.6),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _checkAndPromptSalesRepSelection(force: true),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: hasReps
                        ? theme.primaryColor.withOpacity(0.15)
                        : Colors.amber.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    hasReps
                        ? Icons.assignment_ind_rounded
                        : Icons.warning_amber_rounded,
                    color: hasReps ? theme.primaryColor : Colors.amber.shade800,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Active Sales Reps',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                          if (hasReps) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: theme.primaryColor.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${_selectedSalesReps.length}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: theme.primaryColor,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        repText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: hasReps
                              ? (isDark ? Colors.white : Colors.black87)
                              : Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _checkAndPromptSalesRepSelection(force: true),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: theme.primaryColor,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                  child: const Text(
                    'Change',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRestrictedUI(
    BuildContext context,
    String title,
    String message,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_person_rounded,
              size: 64,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black54,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuButton(
    BuildContext context,
    String title,
    IconData icon,
    Widget? screen, {
    VoidCallback? onTapOverride,
    String? subtitle,
    int badgeCount = 0,
    bool isWarning = false,
    String? badgeLabel,
    Color? iconColor,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final syncState = context.watch<SyncBloc>().state;
    final mfgState = context.watch<ManufacturingBloc>().state;
    final salesSyncState = context.watch<SalesInvoiceSyncBloc>().state;
    final isSyncing =
        syncState is SyncInProgress || mfgState is ManufacturingSyncProgress || salesSyncState is SalesInvoiceSyncInProgress;

    final Color cardBg = isWarning
        ? (isDark ? const Color(0xFF261D10) : const Color(0xFFFFFBEB))
        : theme.cardColor;

    final Border? cardBorder = isWarning
        ? Border.all(color: Colors.amber.shade700, width: 1.5)
        : (isDark ? Border.all(color: Colors.white10, width: 1) : null);

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: cardBorder,
          boxShadow: [
            if (!isDark && !isWarning)
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            if (isWarning)
              BoxShadow(
                color: Colors.amber.withOpacity(isDark ? 0.2 : 0.15),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: InkWell(
          onTap: isSyncing
              ? null
              : () async {
                  if (onTapOverride != null) {
                    onTapOverride();
                  } else if (screen != null) {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => screen,
                        settings: RouteSettings(
                          name: '/${title.toLowerCase().replaceAll(' ', '_')}',
                        ),
                      ),
                    );
                    _loadUnsyncedSummary();
                    _loadLastSync();
                  }
                },
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        size: 38,
                        color: isWarning
                            ? Colors.amber.shade700
                            : (iconColor ?? theme.primaryColor),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isWarning
                                ? (isDark ? Colors.amber.shade300 : Colors.amber.shade900)
                                : (isDark
                                    ? Colors.white.withValues(alpha: 0.5)
                                    : Colors.black45),
                            fontSize: 10,
                            fontWeight: isWarning ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (badgeCount > 0 || badgeLabel != null)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: isWarning ? Colors.amber.shade700 : theme.primaryColor,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isWarning ? Icons.cloud_off_rounded : Icons.info_outline,
                          size: 10,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          badgeLabel ?? '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Drawer(
      backgroundColor: theme.colorScheme.surface,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                DrawerHeader(
                  decoration: BoxDecoration(
                    color: isDark
                        ? theme.colorScheme.primaryContainer.withValues(
                            alpha: 0.1,
                          )
                        : theme.primaryColor.withValues(alpha: 0.1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      CircleAvatar(
                        backgroundColor: theme.primaryColor,
                        child: const Icon(Icons.person, color: Colors.black),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.username.toUpperCase(),
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'System Administrator',
                        style: TextStyle(
                          color: isDark ? Colors.white38 : Colors.black45,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                ListTile(
                  leading: Icon(
                    Icons.dashboard,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                  title: Text(
                    'Dashboard',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  onTap: () => Navigator.pop(context),
                ),
                if (_hasAccess('settings.general.read'))
                  ListTile(
                    leading: Icon(
                      Icons.settings,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    title: Text(
                      'Settings',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SettingsModulesScreen(),
                        ),
                      );
                    },
                  ),
                if (_hasAccess('administration.user_management.read'))
                  ListTile(
                    leading: Icon(
                      Icons.admin_panel_settings_rounded,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    title: Text(
                      'User Admin',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const UserManagementScreen(),
                        ),
                      );
                    },
                  ),
                if (_hasAccess('administration.sync_logs.read'))
                  ListTile(
                    leading: Icon(
                      Icons.sync_alt,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    title: Text(
                      'Sync Logs',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SyncLogsScreen(),
                        ),
                      );
                    },
                  ),
                if (_hasAccess('administration.devices.read'))
                  ListTile(
                    leading: Icon(
                      Icons.devices_other_rounded,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    title: Text(
                      'Devices',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DevicesScreen(),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
          Divider(color: isDark ? Colors.white10 : Colors.black12),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text(
              'Log out',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
            onTap: () {
              HomeScreen.resetSessionPrompt();
              context.read<AuthBloc>().add(LogoutRequested());
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
