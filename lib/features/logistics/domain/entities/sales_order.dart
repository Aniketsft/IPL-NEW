import 'package:equatable/equatable.dart';
import 'sales_order_detail.dart';

/// Domain entity for a Sales Order header.
/// Used by ViewSalesOrderScreen and DeliveryScreen.
class SalesOrder extends Equatable {
  final String id;
  final String orderNumber;
  final String customerCode;
  final String customerName;

  /// The delivery date (string, for display from API).
  final String deliveryDate;

  /// The delivery date as a [DateTime] for calculations.
  final DateTime date;

  /// The SO creation / order date (distinct from deliveryDate).
  final DateTime? soDate;

  final String? purchaseOrderNumber;
  final bool isClosed;
  final bool isEditable;
  final String salesManCode1;
  final String salesManCode2;
  final String? site;

  // Delivery-specific fields
  final String? deliveryNo;
  final String? deliveryFrom;
  final String? deliveryLorry;
  final String? deliverySalesman;
  final String? soLorry;
  final String? originalSoLorry;

  const SalesOrder({
    required this.id,
    required this.orderNumber,
    required this.customerCode,
    required this.customerName,
    required this.deliveryDate,
    required this.date,
    required this.salesManCode1,
    required this.salesManCode2,
    this.soDate,
    this.purchaseOrderNumber,
    this.isClosed = false,
    this.isEditable = true,
    this.deliveryNo,
    this.deliveryFrom,
    this.deliveryLorry,
    this.deliverySalesman,
    this.soLorry,
    this.originalSoLorry,
    this.site,
  });

  factory SalesOrder.fromDetail(SalesOrderDetail detail) {
    return SalesOrder(
      id: detail.soNumber,
      orderNumber: detail.soNumber,
      customerCode: detail.customerCode ?? '',
      customerName: detail.customerName ?? '',
      deliveryDate:
          detail.deliveryDate?.toIso8601String().split('T').first ?? '',
      date: detail.deliveryDate ?? DateTime.now(),
      soDate: null,
      purchaseOrderNumber: detail.poNumber,
      salesManCode1: detail.salesMan1 ?? '',
      salesManCode2: detail.salesMan2 ?? '',
      site: detail.site,
      isClosed: false,
      isEditable: true,
    );
  }

  SalesOrder copyWith({
    bool? isClosed,
    bool? isEditable,
    DateTime? soDate,
    String? deliveryNo,
    String? deliveryFrom,
    String? deliveryLorry,
    String? deliverySalesman,
    String? soLorry,
    String? originalSoLorry,
  }) {
    return SalesOrder(
      id: id,
      orderNumber: orderNumber,
      customerCode: customerCode,
      customerName: customerName,
      deliveryDate: deliveryDate,
      date: date,
      salesManCode1: salesManCode1,
      salesManCode2: salesManCode2,
      soDate: soDate ?? this.soDate,
      purchaseOrderNumber: purchaseOrderNumber,
      isClosed: isClosed ?? this.isClosed,
      isEditable: isEditable ?? this.isEditable,
      deliveryNo: deliveryNo ?? this.deliveryNo,
      deliveryFrom: deliveryFrom ?? this.deliveryFrom,
      deliveryLorry: deliveryLorry ?? this.deliveryLorry,
      deliverySalesman: deliverySalesman ?? this.deliverySalesman,
      soLorry: soLorry ?? this.soLorry,
      originalSoLorry: originalSoLorry ?? this.originalSoLorry,
      site: site ?? this.site,
    );
  }

  @override
  List<Object?> get props => [
    id,
    orderNumber,
    customerCode,
    customerName,
    deliveryDate,
    date,
    soDate,
    purchaseOrderNumber,
    isClosed,
    isEditable,
    salesManCode1,
    salesManCode2,
    deliveryNo,
    deliveryFrom,
    deliveryLorry,
    deliverySalesman,
    soLorry,
    originalSoLorry,
    site,
  ];
}
