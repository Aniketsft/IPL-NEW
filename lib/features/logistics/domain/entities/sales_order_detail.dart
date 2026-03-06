import 'package:equatable/equatable.dart';

class SalesOrderDetail extends Equatable {
  final String soNumber;
  final String? poNumber;
  final String? customerCode;
  final String? customerName;
  final DateTime? deliveryDate;
  final String? productCode;
  final String? productDescription;
  final String? barcodeType;
  final double orderedQuantity;
  final String? remainingQuantity;
  final String? manufactured;
  final String? salesMan1;
  final String? salesMan2;

  const SalesOrderDetail({
    required this.soNumber,
    this.poNumber,
    this.customerCode,
    this.customerName,
    this.deliveryDate,
    this.productCode,
    this.productDescription,
    this.barcodeType,
    required this.orderedQuantity,
    this.remainingQuantity,
    this.manufactured,
    this.salesMan1,
    this.salesMan2,
  });

  @override
  List<Object?> get props => [
    soNumber,
    poNumber,
    customerCode,
    customerName,
    deliveryDate,
    productCode,
    productDescription,
    barcodeType,
    orderedQuantity,
    remainingQuantity,
    manufactured,
    salesMan1,
    salesMan2,
  ];
}
