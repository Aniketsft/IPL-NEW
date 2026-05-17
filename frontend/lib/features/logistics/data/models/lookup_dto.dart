class LookupDto {
  final String code;
  final String name;

  LookupDto({required this.code, required this.name});

  factory LookupDto.fromJson(Map<String, dynamic> json) {
    return LookupDto(
      code: (json['code'] ??
              json['customerCode'] ??
              json['repCode'] ??
              json['salesmanCode'] ??
              json['siteCode'] ??
              '')
          .toString(),
      name: (json['name'] ??
              json['customerName'] ??
              json['repName'] ??
              json['salesmanName'] ??
              json['siteName'] ??
              '')
          .toString(),
    );
  }

  Map<String, dynamic> toSqlMap() {
    return {'code': code, 'name': name};
  }
}
