import '../../domain/entities/location_lookup.dart';

class LocationLookupDto {
  final String? site;
  final String? location;
  final String? warehouse;
  final String? warehouseName;
  final String? locationType;
  final String? locationTypeName;

  LocationLookupDto({
    this.site,
    this.location,
    this.warehouse,
    this.warehouseName,
    this.locationType,
    this.locationTypeName,
  });

  factory LocationLookupDto.fromJson(Map<String, dynamic> json) {
    return LocationLookupDto(
      site: json['site'],
      location: json['location'],
      warehouse: json['warehouse'],
      warehouseName: json['warehouseName'],
      locationType: json['locationType'],
      locationTypeName: json['locationTypeName'],
    );
  }

  LocationLookup toEntity() {
    return LocationLookup(
      site: site,
      location: location,
      warehouse: warehouse,
      warehouseName: warehouseName,
      locationType: locationType,
      locationTypeName: locationTypeName,
    );
  }

  Map<String, dynamic> toSqlMap() {
    return {
      'site': site,
      'location': location,
      'warehouse': warehouse,
      'warehouseName': warehouseName,
      'locationType': locationType,
      'locationTypeName': locationTypeName,
    };
  }
}
