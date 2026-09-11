import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_event.dart';

/// Wraps the entire application to detect user interactions and lifecycle changes.
/// Hand-in-hand with [AuthBloc] and [AuthConfig], it ensures timely inactivity tracking
/// and immediate session validation upon app foregrounding.
class InactivityWatcher extends StatefulWidget {
  final Widget child;

  const InactivityWatcher({super.key, required this.child});

  @override
  State<InactivityWatcher> createState() => _InactivityWatcherState();
}

class _InactivityWatcherState extends State<InactivityWatcher> with WidgetsBindingObserver {
  DateTime _lastInteractionDispatched = DateTime.fromMillisecondsSinceEpoch(0);
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
    if (state == AppLifecycleState.resumed && mounted) {
      // Validate session immediately when user returns from background/sleep
      context.read<AuthBloc>().add(ValidateSession());
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
      onPointerMove: _handleInteraction,
      onPointerUp: _handleInteraction,
      child: widget.child,
    );
  }
}
