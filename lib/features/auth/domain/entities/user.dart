import 'package:equatable/equatable.dart';

class User extends Equatable {
  final String id;
  final String username;
  final String email;
  final List<String> permissions;

  const User({
    required this.id,
    required this.username,
    required this.email,
    required this.permissions,
  });

  @override
  List<Object?> get props => [id, username, email, permissions];
}
