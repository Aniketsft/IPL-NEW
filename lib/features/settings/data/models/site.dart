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
    Site(id: 'SITE-001', companyId: 'COMP-001', name: 'Main Plant'),
    Site(id: 'SITE-002', companyId: 'COMP-001', name: 'North Warehouse'),
    Site(
      id: 'SITE-003',
      companyId: 'COMP-002',
      name: 'Distribution Center Alpha',
    ),
  ];
}
