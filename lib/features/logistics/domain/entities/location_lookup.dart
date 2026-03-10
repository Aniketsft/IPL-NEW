class LocationLookup {
  final String? site;
  final String? location;
  final String? warehouse;
  final String? warehouseName;
  final String? locationType;
  final String? locationTypeName;

  LocationLookup({
    this.site,
    this.location,
    this.warehouse,
    this.warehouseName,
    this.locationType,
    this.locationTypeName,
  });

  String get displayName => location ?? 'Unknown';

  String get fullInfo => '$location ($locationTypeName) - $warehouseName';
}
