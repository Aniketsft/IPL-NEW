class Company {
  final String id;
  final String name;

  Company({required this.id, required this.name});

  factory Company.fromJson(Map<String, dynamic> json) {
    return Company(id: json['id'], name: json['name']);
  }

  // Example of what the mock will generate
  static List<Company> get mockCompanies => [
    Company(id: 'COMP-001', name: 'Hipo Food Corp'),
    Company(id: 'COMP-002', name: 'Hipo Logistics Ltd'),
    Company(id: 'COMP-003', name: 'Hipo Industrial Systems'),
  ];
}
