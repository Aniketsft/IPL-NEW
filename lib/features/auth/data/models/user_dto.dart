class UserDto {
  final String id; // Guid from backend
  final String username;
  final String email;
  final List<String> permissions;
  final String token;
  final String? siteCode;

  UserDto({
    required this.id,
    required this.username,
    required this.email,
    required this.permissions,
    required this.token,
    this.siteCode,
  });

  factory UserDto.fromJson(Map<String, dynamic> json) {
    return UserDto(
      id: json['id'] ?? '',
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      permissions: List<String>.from(json['permissions'] ?? []),
      token: json['token'] ?? '',
      siteCode: json['siteCode'],
    );
  }
}
