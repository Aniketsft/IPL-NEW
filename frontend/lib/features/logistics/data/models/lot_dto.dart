import '../local/local_database_helper.dart';

class LotDto {
  final String itemCode;
  final String siteCode;
  final String lot;

  LotDto({
    required this.itemCode,
    required this.siteCode,
    required this.lot,
  });

  factory LotDto.fromJson(Map<String, dynamic> json) {
    return LotDto(
      itemCode: json['itemCode']?.toString() ?? '',
      siteCode: json['siteCode']?.toString() ?? '',
      lot: json['lot']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toSqlMap() {
    return {
      LocalDatabaseHelper.colLotItemCode: itemCode,
      LocalDatabaseHelper.colLotSiteCode: siteCode,
      LocalDatabaseHelper.colLotNumber: lot,
    };
  }
}
