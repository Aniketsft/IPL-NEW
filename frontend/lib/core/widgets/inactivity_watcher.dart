import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_event.dart';

class InactivityWatcher extends StatelessWidget {
  final Widget child;

  const InactivityWatcher({super.key, required this.child});

  void _handleInteraction(BuildContext context, [_]) {
    context.read<AuthBloc>().add(UserInteracted());
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => _handleInteraction(context, e),
      onPointerMove: (e) => _handleInteraction(context, e),
      onPointerUp: (e) => _handleInteraction(context, e),
      child: child,
    );
  }
}
