import '../local/local_database_helper.dart';

class ProductMasterDto {
  final String productCode;
  final String productDescription;
  final String stockUnit;
  final String salesUnit;

  ProductMasterDto({
    required this.productCode,
    required this.productDescription,
    required this.stockUnit,
    required this.salesUnit,
  });

  factory ProductMasterDto.fromJson(Map<String, dynamic> json) {
    return ProductMasterDto(
      productCode: json['productCode'] ?? '',
      productDescription: json['productDescription'] ?? '',
      stockUnit: json['stockUnit'] ?? '',
      salesUnit: json['salesUnit'] ?? '',
    );
  }

  Map<String, dynamic> toSqlMap() {
    return {
      LocalDatabaseHelper.colProdCode: productCode,
      LocalDatabaseHelper.colProdDesc: productDescription,
      LocalDatabaseHelper.colProdStu: stockUnit,
      LocalDatabaseHelper.colProdSau: salesUnit,
    };
  }
}
