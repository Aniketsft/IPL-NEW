import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/sync_bloc.dart';
import '../bloc/sync_event.dart';
import '../bloc/sync_state.dart';
import 'package:enterprise_auth_mobile/features/manufacturing/bloc/manufacturing_bloc.dart';
import 'package:enterprise_auth_mobile/features/manufacturing/bloc/manufacturing_event.dart';
import 'package:enterprise_auth_mobile/features/manufacturing/bloc/manufacturing_state.dart';

class SyncOverlay extends StatelessWidget {
  const SyncOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    return BlocListener<SyncBloc, SyncState>(
      listener: (context, syncState) {
        if (syncState is SyncSuccess) {
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (context.mounted) {
              context.read<SyncBloc>().add(const ResetSyncRequested());
            }
          });
        }
      },
      child: BlocBuilder<SyncBloc, SyncState>(
        builder: (context, syncState) {
          return BlocBuilder<ManufacturingBloc, ManufacturingState>(
            builder: (context, mfgState) {
              String message = "Working...";
              double progress = 0.1;
              bool isSuccess = false;
              bool isError = false;
              bool isMfgFailure = false;
              bool showOverlay = false;

              if (syncState is! SyncInitial) {
                showOverlay = true;
                if (syncState is SyncInProgress) {
                  message = syncState.message;
                  progress = syncState.progress;
                } else if (syncState is SyncSuccess) {
                  message = "Sync Completed!";
                  progress = 1.0;
                  isSuccess = true;
                } else if (syncState is SyncFailure) {
                  message = "Sync Failed: ${syncState.error}";
                  isError = true;
                }
              } else if (mfgState is ManufacturingSyncProgress ||
                  mfgState is ManufacturingFailure) {
                showOverlay = true;
                if (mfgState is ManufacturingSyncProgress) {
                  message = mfgState.message;
                  progress = mfgState.progress;
                  isSuccess = mfgState.phase == SyncPhase.success;
                } else if (mfgState is ManufacturingFailure) {
                  message = mfgState.message;
                  isError = true;
                  isMfgFailure = true;
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
                            color: Colors.black
                                .withValues(alpha: isDark ? 0.5 : 0.1),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildAnimatedIcon(
                              context, isSuccess, isError, orange),
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
                          if (!isError)
                            Column(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    backgroundColor:
                                        (isDark ? Colors.white : Colors.black)
                                            .withValues(alpha: 0.1),
                                    color: isSuccess ? Colors.green : orange,
                                    minHeight: 8,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${(progress * 100).toInt()}%',
                                  style: TextStyle(
                                    color: isSuccess ? Colors.green : orange,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          if (isError)
                            Column(
                              children: [
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: () {
                                    if (isMfgFailure) {
                                      context.read<ManufacturingBloc>().add(
                                            LoadProductionTrackingRequested(
                                              siteCode:
                                                  mfgState.currentSiteCode,
                                              date: mfgState.selectedDate,
                                            ),
                                          );
                                    } else {
                                      context
                                          .read<SyncBloc>()
                                          .add(const ResetSyncRequested());
                                    }
                                  },
                                  child: const Text(
                                    'DISMISS',
                                    style: TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.bold),
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
        },
      ),
    );
  }

  Widget _buildAnimatedIcon(
      BuildContext context, bool isSuccess, bool isError, Color orange) {
    if (isError) {
      return const Icon(Icons.error_outline, size: 64, color: Colors.red);
    }
    if (isSuccess) {
      return const Icon(
        Icons.check_circle_outline,
        size: 64,
        color: Colors.green,
      );
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
