import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_event.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_state.dart';
import 'package:enterprise_auth_mobile/features/auth/data/repositories/auth_repository.dart';

class InactivityWatcher extends StatefulWidget {
  final Widget child;

  const InactivityWatcher({super.key, required this.child});

  @override
  State<InactivityWatcher> createState() => _InactivityWatcherState();
}

class _InactivityWatcherState extends State<InactivityWatcher> {
  Timer? _inactivityTimer;
  Timer? _refreshTimer;

  // 30 minutes timeout for inactivity
  static const Duration timeoutDuration = Duration(minutes: 30);
  // 5 minutes interval to refresh token if active
  static const Duration refreshInterval = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    _startTimers();
  }

  void _startTimers() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(timeoutDuration, _onTimeout);

    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(refreshInterval, (timer) {
      _refreshToken();
    });
  }

  void _onTimeout() {
    context.read<AuthBloc>().add(LogoutRequested());
  }

  Future<void> _refreshToken() async {
    // Only refresh if the user is authenticated.
    // If they are on the login screen, don't ping the refresh endpoint.
    final authState = context.read<AuthBloc>().state;
    if (authState is Authenticated) {
      await context.read<AuthRepository>().refreshToken();

      // // Enforce Offline TTL
      // final isValid = await context
      //     .read<AuthRepository>()
      //     .isOfflineSessionValid();
      // if (!isValid) {
      //   if (mounted) {
      //     context.read<AuthBloc>().add(LogoutRequested());
      //   }
      // }
    }
  }

  void _handleInteraction([_]) {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(timeoutDuration, _onTimeout);
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
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
