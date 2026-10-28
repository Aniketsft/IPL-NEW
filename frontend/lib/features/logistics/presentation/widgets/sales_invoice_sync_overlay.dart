import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../data/repositories/sales_invoice_sync_repository.dart';
import '../bloc/sales_invoice_sync_bloc.dart';
import '../bloc/sales_invoice_sync_event.dart';
import '../bloc/sales_invoice_sync_state.dart';

class SalesInvoiceSyncOverlay extends StatefulWidget {
  const SalesInvoiceSyncOverlay({super.key});

  @override
  State<SalesInvoiceSyncOverlay> createState() => _SalesInvoiceSyncOverlayState();
}

class _SalesInvoiceSyncOverlayState extends State<SalesInvoiceSyncOverlay> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    return BlocListener<SalesInvoiceSyncBloc, SalesInvoiceSyncState>(
      listener: (context, syncState) {
        if (syncState is SalesInvoiceSyncSuccess) {
          final isClean = syncState.batchResult.isCleanSuccess;
          if (isClean) {
            // Auto-dismiss cleanly on 100% success after 3.2s so user can see it properly
            Future.delayed(const Duration(milliseconds: 3200), () {
              if (context.mounted) {
                final current = context.read<SalesInvoiceSyncBloc>().state;
                if (current is SalesInvoiceSyncSuccess && current.batchResult.isCleanSuccess) {
                  context.read<SalesInvoiceSyncBloc>().add(const ResetSalesInvoiceSyncRequested());
                }
              }
            });
          }
        } else if (syncState is SalesInvoiceCustomerSyncSuccess) {
          // Auto-dismiss cleanly on customer sync success after 3.2s
          Future.delayed(const Duration(milliseconds: 3200), () {
            if (context.mounted) {
              final current = context.read<SalesInvoiceSyncBloc>().state;
              if (current is SalesInvoiceCustomerSyncSuccess) {
                context.read<SalesInvoiceSyncBloc>().add(const ResetSalesInvoiceSyncRequested());
              }
            }
          });
        }
      },
      child: BlocBuilder<SalesInvoiceSyncBloc, SalesInvoiceSyncState>(
        builder: (context, syncState) {
          String title = "Mobile Sales Data";
          String message = "Synchronizing Mobile Sales Data...";
          bool isCleanSuccess = false;
          bool isPartial = false;
          bool isError = false;
          bool showOverlay = false;
          final isSyncing = syncState is SalesInvoiceSyncInProgress ||
              syncState is SalesInvoiceCustomerSyncInProgress;
          List<SyncEntityReport> reportList = [];
          SyncBatchResult? currentBatchResult;

          if (syncState is! SalesInvoiceSyncInitial) {
            showOverlay = true;
            if (syncState is SalesInvoiceSyncInProgress) {
              title = "Synchronizing";
              message = syncState.message;
            } else if (syncState is SalesInvoiceCustomerSyncInProgress) {
              title = "Syncing Customer";
              message = syncState.message;
            } else if (syncState is SalesInvoiceCustomerSyncSuccess) {
              isCleanSuccess = true;
              title = "Customer Synchronized";
              final balanceStr = CurrencyFormatter.format(syncState.result.liveBalance);
              message = "${syncState.customerName}\nBalance: $balanceStr • ${syncState.result.openInvoicesCount} Open Invoices • ${syncState.result.x3HistoryInvoicesCount} X3 Invoices";
              reportList = [];
            } else if (syncState is SalesInvoiceCustomerSyncFailure) {
              isError = true;
              title = "Customer Sync Failed";
              message = syncState.error;
            } else if (syncState is SalesInvoiceSyncSuccess) {
              currentBatchResult = syncState.batchResult;
              if (syncState.batchResult.isCleanSuccess) {
                isCleanSuccess = true;
                title = "Sync Complete";
                message = "All records updated successfully";
                reportList = []; // Clean success: no details box needed
              } else {
                isPartial = true;
                title = "Sync Attention";
                final successCount = syncState.batchResult.successfulReports.length;
                final failCount = syncState.batchResult.failedReports.length;
                message = "Completed with issues ($successCount updated, $failCount failed)";
                reportList = syncState.batchResult.failedReports; // Only show failed items
              }
            } else if (syncState is SalesInvoiceSyncFailure) {
              isError = true;
              currentBatchResult = syncState.batchResult;
              if (syncState.batchResult != null) {
                reportList = syncState.batchResult!.failedReports;
              }
              final isOfflineBlocked = syncState.error.toLowerCase().contains('offline');
              title = isOfflineBlocked ? "Sync Blocked" : "Sync Failed";
              message = syncState.error;
            }
          }

          if (!showOverlay) {
            return const SizedBox.shrink();
          }

          return PopScope(
            canPop: !isSyncing,
            child: Material(
              type: MaterialType.transparency,
              child: Stack(
                children: [
                  // 1. Frosted Glass Backdrop with touch barrier
                  Positioned.fill(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        color: Colors.black.withOpacity(isDark ? 0.65 : 0.45),
                      ),
                    ),
                  ),

                  // 2. Centered Minimalist Glass HUD Card
                  Center(
                    child: Container(
                      width: 300,
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                      decoration: BoxDecoration(
                        color: isDark 
                            ? const Color(0xFF1B1B1F).withOpacity(0.95) 
                            : Colors.white.withOpacity(0.96),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: (isDark ? Colors.white : Colors.black).withOpacity(0.08),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(isDark ? 0.45 : 0.15),
                            blurRadius: 32,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildHeaderIcon(isCleanSuccess, isPartial, isError, orange, isDark),
                          const SizedBox(height: 16),
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                              color: isDark ? Colors.white : const Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            message,
                            textAlign: TextAlign.center,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w400,
                              height: 1.35,
                              color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
                            ),
                          ),
                          if ((isPartial || isError) && reportList.isNotEmpty && !isSyncing) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              constraints: const BoxConstraints(maxHeight: 130),
                              decoration: BoxDecoration(
                                color: (isDark ? Colors.white : Colors.black).withOpacity(0.04),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: reportList.length,
                                itemBuilder: (context, index) {
                                  final report = reportList[index];
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 2.5),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.error_outline_rounded,
                                          size: 13,
                                          color: Colors.redAccent,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            report.entityName,
                                            style: TextStyle(
                                              color: isDark ? Colors.white70 : const Color(0xFF374151),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Text(
                                          report.errorCode ?? 'Failed',
                                          style: const TextStyle(
                                            color: Colors.redAccent,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                          if (isSyncing)
                            Container(
                              height: 2.5,
                              width: double.infinity,
                              margin: const EdgeInsets.only(top: 18),
                              decoration: BoxDecoration(
                                color: (isDark ? Colors.white : Colors.black).withOpacity(0.06),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(100),
                                child: LinearProgressIndicator(
                                  backgroundColor: Colors.transparent,
                                  valueColor: AlwaysStoppedAnimation<Color>(orange),
                                ),
                              ),
                            ),
                          if (!isSyncing && (isPartial || isError))
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Row(
                                children: [
                                  if (currentBatchResult != null) ...[
                                    Expanded(
                                      child: SizedBox(
                                        height: 38,
                                        child: OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: isDark ? Colors.white70 : const Color(0xFF374151),
                                            side: BorderSide(
                                              color: (isDark ? Colors.white : Colors.black).withOpacity(0.12),
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            padding: const EdgeInsets.symmetric(horizontal: 8),
                                          ),
                                          onPressed: () {
                                            final diagText = currentBatchResult?.toDiagnosticJson() ?? 'No diagnostics available';
                                            Clipboard.setData(ClipboardData(
                                              text: diagText,
                                            ));
                                            setState(() => _copied = true);
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('Diagnostics copied to clipboard'),
                                                duration: Duration(seconds: 2),
                                              ),
                                            );
                                          },
                                          icon: Icon(
                                            _copied ? Icons.check_rounded : Icons.copy_rounded,
                                            size: 14,
                                          ),
                                          label: Text(
                                            _copied ? 'Copied' : 'Diagnostics',
                                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Expanded(
                                    child: SizedBox(
                                      height: 38,
                                      child: TextButton(
                                        style: TextButton.styleFrom(
                                          backgroundColor: orange,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                        ),
                                        onPressed: () {
                                          setState(() => _copied = false);
                                          context.read<SalesInvoiceSyncBloc>().add(const ResetSalesInvoiceSyncRequested());
                                        },
                                        child: const Text(
                                          'Dismiss',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeaderIcon(bool isCleanSuccess, bool isPartial, bool isError, Color orange, bool isDark) {
    if (isError) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.redAccent.withOpacity(0.12),
        ),
        child: const Center(
          child: Icon(Icons.cloud_off_rounded, size: 24, color: Colors.redAccent),
        ),
      );
    }
    if (isPartial) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.orange.withOpacity(0.12),
        ),
        child: const Center(
          child: Icon(Icons.warning_amber_rounded, size: 24, color: Colors.orange),
        ),
      );
    }
    if (isCleanSuccess) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.green.withOpacity(0.12),
        ),
        child: const Center(
          child: Icon(Icons.check_rounded, size: 24, color: Colors.green),
        ),
      );
    }
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: orange.withOpacity(0.08),
      ),
      child: Center(
        child: SizedBox(
          height: 24,
          width: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            backgroundColor: orange.withOpacity(0.15),
            valueColor: AlwaysStoppedAnimation<Color>(orange),
          ),
        ),
      ),
    );
  }
}
