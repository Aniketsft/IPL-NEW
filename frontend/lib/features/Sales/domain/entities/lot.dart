class Lot {
  final String lotNumber;
  final String warehouse;
  final String location;
  final String type;
  final bool isDepleted;

  Lot({
    required this.lotNumber,
    required this.warehouse,
    required this.location,
    required this.type,
    this.isDepleted = false,
  });
}
