import '../local/local_database_helper.dart';

class ProductMasterDto {
  final String productCode;
  final String productDescription;
  final String stockUnit;
  final String salesUnit;
  final double standardWeight;
  final String? barcode;
  final String? defaultLocation;
  final int? shelfLifeDays;

  ProductMasterDto({
    required this.productCode,
    required this.productDescription,
    required this.stockUnit,
    required this.salesUnit,
    this.standardWeight = 0.0,
    this.barcode,
    this.defaultLocation,
    this.shelfLifeDays,
  });

  factory ProductMasterDto.fromJson(Map<String, dynamic> json) {
    return ProductMasterDto(
      productCode: (json['productCode'] ?? json['itemCode'] ?? '').toString(),
      productDescription: (json['productDescription'] ??
              json['itemDescription'] ??
              json['description'] ??
              '')
          .toString(),
      stockUnit: (json['stockUnit'] ?? json['baseUnit'] ?? '').toString(),
      salesUnit: (json['salesUnit'] ?? json['unit'] ?? '').toString(),
      standardWeight:
          double.tryParse((json['standardWeight'] ?? '0').toString()) ?? 0.0,
      barcode: json['barcode']?.toString(),
      defaultLocation: json['defaultLocation']?.toString(),
      shelfLifeDays: json['shelfLifeDays'] != null ? int.tryParse(json['shelfLifeDays'].toString()) : null,
    );
  }

  Map<String, dynamic> toSqlMap() {
    return {
      LocalDatabaseHelper.colProdCode: productCode,
      LocalDatabaseHelper.colProdDesc: productDescription,
      LocalDatabaseHelper.colProdStu: stockUnit,
      LocalDatabaseHelper.colProdSau: salesUnit,
      LocalDatabaseHelper.colProdStandardWeight: standardWeight,
      LocalDatabaseHelper.colProdBarcode: barcode,
      LocalDatabaseHelper.colProdDefaultLocation: defaultLocation,
      LocalDatabaseHelper.colProdShelfLifeDays: shelfLifeDays ?? 5,
    };
  }
}
