import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/manufacturing_bloc.dart';
import '../../bloc/manufacturing_state.dart';

class SyncProgressDialog extends StatelessWidget {
  const SyncProgressDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<ManufacturingBloc, ManufacturingState>(
      listener: (context, state) {
        if (state is ProductionTrackingLoaded ||
            state is ManufacturingFailure) {
          // Close dialog when sync is done or failed
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          });
        }
      },
      child: BlocBuilder<ManufacturingBloc, ManufacturingState>(
        builder: (context, state) {
          String message = "Working...";
          double progress = 0.1;
          bool isSuccess = false;
          bool isError = false;

          if (state is ManufacturingSyncProgress) {
            message = state.message;
            progress = state.progress;
            isSuccess = state.phase == SyncPhase.success;
          } else if (state is ProductionTrackingLoaded) {
            message = "Sync Completed!";
            progress = 1.0;
            isSuccess = true;
          } else if (state is ManufacturingFailure) {
            message = "Sync Failed: ${state.message}";
            isError = true;
          }

          return Dialog(
            backgroundColor: const Color(0xFF121212),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildAnimatedIcon(isSuccess, isError),
                    const SizedBox(height: 24),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
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
                              backgroundColor: Colors.white.withOpacity(0.1),
                              color: const Color(0xFFFF9800),
                              minHeight: 8,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${(progress * 100).toInt()}%',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    if (isError)
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'DISMISS',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAnimatedIcon(bool isSuccess, bool isError) {
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

    return const SizedBox(
      height: 64,
      width: 64,
      child: CircularProgressIndicator(
        strokeWidth: 5,
        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF9800)),
      ),
    );
  }
}
