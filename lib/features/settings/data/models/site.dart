class Site {
  final String id;
  final String companyId;
  final String name;

  Site({required this.id, required this.companyId, required this.name});

  factory Site.fromJson(Map<String, dynamic> json) {
    return Site(
      id: json['id'],
      companyId: json['companyId'],
      name: json['name'],
    );
  }

  // Example of what the mock will generate
  static List<Site> get mockSites => [
    Site(id: 'IPL', companyId: 'COMP-001', name: 'Innodis Plant (IPL)'),
    Site(id: 'SFT', companyId: 'COMP-001', name: 'SFT Warehouse'),
    Site(
      id: 'DC-ALPHA',
      companyId: 'COMP-002',
      name: 'Distribution Center Alpha',
    ),
  ];
}
