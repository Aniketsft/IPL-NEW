class SalesRepModel {
  final String code;
  final String name;
  final String assignedSite;

  SalesRepModel({
    required this.code,
    required this.name,
    this.assignedSite = '',
  });

  SalesRepModel copyWith({
    String? code,
    String? name,
    String? assignedSite,
  }) {
    return SalesRepModel(
      code: code ?? this.code,
      name: name ?? this.name,
      assignedSite: assignedSite ?? this.assignedSite,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'code': code,
      'name': name,
      'assignedSite': assignedSite,
    };
  }

  factory SalesRepModel.fromMap(Map<String, dynamic> map) {
    return SalesRepModel(
      code: (map['code'] ?? map['salesRepCode'] ?? map['SalesRepCode'] ?? '').toString(),
      name: (map['name'] ?? map['salesRepName'] ?? map['SalesRepName'] ?? '').toString(),
      assignedSite: (map['assignedSite'] ?? map['AssignedSite'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => toMap();

  factory SalesRepModel.fromJson(Map<String, dynamic> json) => SalesRepModel.fromMap(json);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SalesRepModel &&
          runtimeType == other.runtimeType &&
          code == other.code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => '$code - $name';
}
