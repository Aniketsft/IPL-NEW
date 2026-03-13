class LookupDto {
  final String code;
  final String name;

  LookupDto({required this.code, required this.name});

  factory LookupDto.fromJson(Map<String, dynamic> json) {
    return LookupDto(
      code: (json['code'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toSqlMap() {
    return {'code': code, 'name': name};
  }
}
