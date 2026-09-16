import 'package:equatable/equatable.dart';

abstract class AuthEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class AppStarted extends AuthEvent {}

class LoginSubmitted extends AuthEvent {
  final String username;
  final String password;

  LoginSubmitted({required this.username, required this.password});

  @override
  List<Object?> get props => [username, password];
}

class RegisterSubmitted extends AuthEvent {
  final String email;
  final String username;
  final String password;

  RegisterSubmitted({
    required this.email,
    required this.username,
    required this.password,
  });

  @override
  List<Object?> get props => [email, username, password];
}

class LogoutRequested extends AuthEvent {}

class ForgotPasswordSubmitted extends AuthEvent {
  final String email;
  ForgotPasswordSubmitted({required this.email});
  @override
  List<Object?> get props => [email];
}

class UserInteracted extends AuthEvent {}

class PerformTokenRefresh extends AuthEvent {}

class ValidateSession extends AuthEvent {}

/// Fired by InactivityWatcher when the app resumes and the elapsed time is
/// within the active session window. Does NOT perform any logout checks —
/// it simply slides the inactivity timer to prevent premature idle-timeout.
class SoftSessionCheck extends AuthEvent {}
