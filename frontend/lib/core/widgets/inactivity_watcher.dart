import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:enterprise_auth_mobile/core/config/auth_config.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_event.dart';

/// Wraps the entire application to detect user interactions and lifecycle changes.
/// Hand-in-hand with [AuthBloc] and [AuthConfig], it ensures timely inactivity tracking
/// and smart session validation upon app foregrounding.
///
/// On resume it dispatches:
/// - [SoftSessionCheck] if the absence is within the [AuthConfig.sessionTimeout] window
///   (e.g. phone briefly locked) — slides the inactivity timer, no logout risk.
/// - [ValidateSession] only if the absence exceeds [AuthConfig.sessionTimeout]
///   (e.g. left overnight) — performs full validation and may logout.
class InactivityWatcher extends StatefulWidget {
  final Widget child;

  const InactivityWatcher({super.key, required this.child});

  @override
  State<InactivityWatcher> createState() => _InactivityWatcherState();
}

class _InactivityWatcherState extends State<InactivityWatcher> with WidgetsBindingObserver {
  DateTime _lastInteractionDispatched = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _pausedAt;
  static const Duration _throttleDuration = Duration(milliseconds: 1500);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // Record when we left so we can calculate absence duration on resume
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed && mounted) {
      final absenceDuration = _pausedAt != null
          ? DateTime.now().difference(_pausedAt!)
          : Duration.zero;

      if (absenceDuration >= AuthConfig.sessionTimeout) {
        // Away for a full shift — perform a hard session validation (may logout)
        context.read<AuthBloc>().add(ValidateSession());
      } else {
        // Brief absence (phone locked, switched apps) — just slide the timer, no logout risk
        context.read<AuthBloc>().add(SoftSessionCheck());
      }
      _pausedAt = null;
    }
  }

  void _handleInteraction([_]) {
    final now = DateTime.now();
    if (now.difference(_lastInteractionDispatched) >= _throttleDuration) {
      _lastInteractionDispatched = now;
      if (mounted) {
        context.read<AuthBloc>().add(UserInteracted());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handleInteraction,
      child: widget.child,
    );
  }
}
