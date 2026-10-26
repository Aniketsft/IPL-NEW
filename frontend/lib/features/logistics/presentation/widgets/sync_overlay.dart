import 'dart:ui';
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
                  message = "Sync Completed";
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
                child: Stack(
                  children: [
                    // Frosted Glass Backdrop
                    Positioned.fill(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          color: Colors.black.withOpacity(isDark ? 0.65 : 0.45),
                        ),
                      ),
                    ),

                    // Centered Minimalist Glass HUD Card
                    Center(
                      child: Container(
                        width: 290,
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1B1B1F).withOpacity(0.94)
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
                            _buildHeaderIcon(isSuccess, isError, orange),
                            const SizedBox(height: 16),
                            Text(
                              isSuccess ? "Sync Completed" : (isError ? "Sync Failed" : "Synchronizing"),
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
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w400,
                                height: 1.35,
                                color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
                              ),
                            ),
                            if (!isError) ...[
                              const SizedBox(height: 18),
                              Container(
                                height: 2.5,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: (isDark ? Colors.white : Colors.black).withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(100),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(100),
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    backgroundColor: Colors.transparent,
                                    color: isSuccess ? Colors.green : orange,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${(progress * 100).toInt()}%',
                                style: TextStyle(
                                  color: isSuccess ? Colors.green : orange,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                            if (isError)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: SizedBox(
                                  width: double.infinity,
                                  height: 38,
                                  child: TextButton(
                                    style: TextButton.styleFrom(
                                      backgroundColor: Colors.redAccent.withOpacity(0.12),
                                      foregroundColor: Colors.redAccent,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    onPressed: () {
                                      if (isMfgFailure) {
                                        context.read<ManufacturingBloc>().add(
                                              LoadProductionTrackingRequested(
                                                siteCode: mfgState.currentSiteCode,
                                                date: mfgState.selectedDate,
                                              ),
                                            );
                                      } else {
                                        context.read<SyncBloc>().add(const ResetSyncRequested());
                                      }
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
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildHeaderIcon(bool isSuccess, bool isError, Color orange) {
    if (isError) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.redAccent.withOpacity(0.12),
        ),
        child: const Center(
          child: Icon(Icons.close_rounded, size: 24, color: Colors.redAccent),
        ),
      );
    }
    if (isSuccess) {
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
