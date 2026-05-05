class Customer {
  final String id;
  final String name;
  final String type; // e.g., Credit, Cash
  final String location;
  final String code; // e.g., ACC-8902
  final String status; // e.g., On Hold, Active
  final double creditLimit;
  final double outstanding;
  final String currency;

  Customer({
    required this.id,
    required this.name,
    required this.type,
    required this.location,
    required this.code,
    required this.status,
    required this.creditLimit,
    required this.outstanding,
    this.currency = 'Rs.',
  });
}
