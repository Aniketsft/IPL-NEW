class ProductionScan {
  final String timestamp;
  final double quantity;
  final String location;
  final String? status;

  ProductionScan({
    required this.timestamp,
    required this.quantity,
    required this.location,
    this.status,
  });

  factory ProductionScan.fromMap(Map<String, dynamic> map) {
    return ProductionScan(
      timestamp: map['timestamp'] ?? '',
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0.0,
      location: map['location'] ?? '',
      status: map['itemStatus'],
    );
  }
}
