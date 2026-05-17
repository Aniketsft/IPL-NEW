import 'package:equatable/equatable.dart';

abstract class AuthState extends Equatable {
  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class Authenticated extends AuthState {
  final String username;
  final List<String> permissions;
  final String? siteCode;

  Authenticated({
    required this.username,
    required this.permissions,
    this.siteCode,
  });

  @override
  List<Object?> get props => [username, permissions, siteCode];
}

class Unauthenticated extends AuthState {}

class AuthFailure extends AuthState {
  final String message;

  AuthFailure(this.message);

  @override
  List<Object?> get props => [message];
}

class AuthSuccess extends AuthState {
  final String message;
  AuthSuccess(this.message);
  @override
  List<Object?> get props => [message];
}
