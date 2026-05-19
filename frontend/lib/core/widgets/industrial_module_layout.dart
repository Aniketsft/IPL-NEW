import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sync_bloc.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sync_state.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/widgets/sync_overlay.dart';
import 'package:enterprise_auth_mobile/features/manufacturing/bloc/manufacturing_bloc.dart';
import 'package:enterprise_auth_mobile/features/manufacturing/bloc/manufacturing_state.dart';

class IndustrialModuleLayout extends StatelessWidget {
  final String title;
  final Widget body;
  final Widget? floatingActionButton;
  final List<Widget>? extraActions;
  final bool showLogout;
  final bool showPlantName;
  final bool showHome;

  const IndustrialModuleLayout({
    super.key,
    required this.title,
    required this.body,
    this.floatingActionButton,
    this.extraActions,
    this.showLogout = false,
    this.showPlantName = false,
    this.showHome = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return BlocBuilder<SyncBloc, SyncState>(
      builder: (context, syncState) {
        return BlocBuilder<ManufacturingBloc, ManufacturingState>(
          builder: (context, mfgState) {
            final isSyncing = syncState is SyncInProgress ||
                mfgState is ManufacturingSyncProgress;

            final scaffold = Scaffold(
              backgroundColor: theme.scaffoldBackgroundColor,
              appBar: AppBar(
                backgroundColor: theme.colorScheme.surface,
                elevation: 0,
                iconTheme: IconThemeData(
                    color: isDark ? Colors.white70 : Colors.black87),
                title: Text(
                  title,
                  style: TextStyle(
                    color: theme.primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                actions: [
                  if (extraActions != null) ...extraActions!,
                  if (showHome)
                    IconButton(
                      icon: Icon(Icons.home_rounded,
                          color: theme.primaryColor, size: 24),
                      tooltip: 'Back to Home',
                      onPressed: isSyncing
                          ? null
                          : () => Navigator.of(context)
                              .popUntil((route) => route.isFirst),
                    ),
                  if (showPlantName || showLogout)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 16.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (showPlantName)
                              Text(
                                'Main Plant',
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.blueGrey
                                      : Colors.grey[600],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            if (showPlantName && showLogout)
                              const SizedBox(width: 8),
                            if (showLogout)
                              InkWell(
                                onTap: isSyncing
                                    ? null
                                    : () {
                                        // Logout action could go here
                                      },
                                borderRadius: BorderRadius.circular(20),
                                child: Padding(
                                  padding: const EdgeInsets.all(4.0),
                                  child: Icon(
                                    Icons.exit_to_app_rounded,
                                    color: isDark
                                        ? Colors.white60
                                        : Colors.black54,
                                    size: 22,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              body: body,
              floatingActionButton: isSyncing ? null : floatingActionButton,
            );

            return PopScope(
              canPop: !isSyncing,
              child: Stack(
                children: [
                  scaffold,
                  const SyncOverlay(),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
