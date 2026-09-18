

class PrinterDevice {
  final String id;
  final String name;
  final String printerModel;
  final String? ipAddress;
  final int? port;

  PrinterDevice({
    required this.id,
    required this.name,
    required this.printerModel,
    this.ipAddress,
    this.port,
  });

  factory PrinterDevice.fromJson(Map<String, dynamic> json) {
    return PrinterDevice(
      id: json['id'] as String,
      name: json['name'] as String,
      printerModel: json['printerModel'] as String,
      ipAddress: json['ipAddress'] as String?,
      port: json['port'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'printerModel': printerModel,
      'ipAddress': ipAddress,
      'port': port,
    };
  }

  PrinterDevice copyWith({
    String? id,
    String? name,
    String? printerModel,
    String? ipAddress,
    int? port,
  }) {
    return PrinterDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      printerModel: printerModel ?? this.printerModel,
      ipAddress: ipAddress ?? this.ipAddress,
      port: port ?? this.port,
    );
  }
}
