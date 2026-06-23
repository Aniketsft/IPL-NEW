import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/sales_invoice_sync_bloc.dart';
import '../bloc/sales_invoice_sync_event.dart';
import '../bloc/sales_invoice_sync_state.dart';

class SalesInvoiceSyncOverlay extends StatelessWidget {
  const SalesInvoiceSyncOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    return BlocBuilder<SalesInvoiceSyncBloc, SalesInvoiceSyncState>(
      builder: (context, syncState) {
        String message = "Working...";
        bool isSuccess = false;
        bool isError = false;
        bool showOverlay = false;
        List<String> details = [];

        if (syncState is! SalesInvoiceSyncInitial) {
          showOverlay = true;
          if (syncState is SalesInvoiceSyncInProgress) {
            message = syncState.message;
          } else if (syncState is SalesInvoiceSyncSuccess) {
            final successes = syncState.batchResult.successes.length;
            final failures = syncState.batchResult.failures.length;
            
            message = "Sync Summary\nSuccesses: $successes | Failures: $failures";
            details = [
              ...syncState.batchResult.successes.map((s) => "Creation of $s successful"),
              ...syncState.batchResult.failures.map((f) => "Failed: $f")
            ];
            
            if (failures > 0) {
              isError = true; // Show error icon if partial failure
            } else {
              isSuccess = true;
            }
          } else if (syncState is SalesInvoiceSyncFailure) {
            message = "Sync Failed: ${syncState.error}";
            isError = true;
          }
        }

        if (!showOverlay) {
          return const SizedBox.shrink();
        }

        return Material(
          type: MaterialType.transparency,
          child: Container(
            color: theme.colorScheme.surface.withValues(alpha: 0.8),
            child: Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding: const EdgeInsets.all(24),
                constraints: const BoxConstraints(maxHeight: 400),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.1),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildAnimatedIcon(context, isSuccess, isError, orange),
                    const SizedBox(height: 24),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (details.isNotEmpty) ...[
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: details.length,
                          itemBuilder: (context, index) {
                            final detail = details[index];
                            final isItemSuccess = detail.endsWith('successful');
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4.0),
                              child: Text(
                                detail,
                                style: TextStyle(
                                  color: isItemSuccess ? Colors.green : Colors.red, 
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (!isError && !isSuccess)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          backgroundColor: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
                          color: orange,
                          minHeight: 8,
                        ),
                      ),
                    if (isError || isSuccess)
                      Column(
                        children: [
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () {
                              context.read<SalesInvoiceSyncBloc>().add(const ResetSalesInvoiceSyncRequested());
                            },
                            child: const Text(
                              'DISMISS',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAnimatedIcon(BuildContext context, bool isSuccess, bool isError, Color orange) {
    if (isError && !isSuccess) {
      return const Icon(Icons.error_outline, size: 64, color: Colors.red);
    }
    if (isError && isSuccess) {
      // Partial failure
      return const Icon(Icons.warning_amber_rounded, size: 64, color: Colors.orange);
    }
    if (isSuccess) {
      return const Icon(Icons.check_circle_outline, size: 64, color: Colors.green);
    }
    return SizedBox(
      height: 64,
      width: 64,
      child: CircularProgressIndicator(
        strokeWidth: 5,
        valueColor: AlwaysStoppedAnimation<Color>(orange),
      ),
    );
  }
}
