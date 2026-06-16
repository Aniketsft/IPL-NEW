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

    return BlocListener<SalesInvoiceSyncBloc, SalesInvoiceSyncState>(
      listener: (context, syncState) {
        if (syncState is SalesInvoiceSyncSuccess) {
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (context.mounted) {
              context.read<SalesInvoiceSyncBloc>().add(const ResetSalesInvoiceSyncRequested());
            }
          });
        }
      },
      child: BlocBuilder<SalesInvoiceSyncBloc, SalesInvoiceSyncState>(
        builder: (context, syncState) {
          String message = "Working...";
          double progress = 0.5; // Indeterminate-like
          bool isSuccess = false;
          bool isError = false;
          bool showOverlay = false;

          if (syncState is! SalesInvoiceSyncInitial) {
            showOverlay = true;
            if (syncState is SalesInvoiceSyncInProgress) {
              message = syncState.message;
            } else if (syncState is SalesInvoiceSyncSuccess) {
              message = "Sync Completed!";
              progress = 1.0;
              isSuccess = true;
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
                      if (!isError && !isSuccess)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            backgroundColor: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
                            color: orange,
                            minHeight: 8,
                          ),
                        ),
                      if (isError)
                        Column(
                          children: [
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () {
                                context.read<SalesInvoiceSyncBloc>().add(const ResetSalesInvoiceSyncRequested());
                              },
                              child: const Text(
                                'DISMISS',
                                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
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
      ),
    );
  }

  Widget _buildAnimatedIcon(BuildContext context, bool isSuccess, bool isError, Color orange) {
    if (isError) {
      return const Icon(Icons.error_outline, size: 64, color: Colors.red);
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
