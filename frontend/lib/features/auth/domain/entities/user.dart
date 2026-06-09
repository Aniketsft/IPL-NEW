import 'package:equatable/equatable.dart';

class User extends Equatable {
  final String id;
  final String username;
  final String email;
  final List<String> permissions;
  final String? siteCode;

  const User({
    required this.id,
    required this.username,
    required this.email,
    required this.permissions,
    this.siteCode,
  });

  @override
  List<Object?> get props => [id, username, email, permissions, siteCode];
}
