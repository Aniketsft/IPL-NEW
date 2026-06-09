import 'package:enterprise_auth_mobile/core/services/printer_service.dart' show PrintMode;

class PrinterDevice {
  final String id;
  final String name;
  final String printerModel;
  final String? ipAddress;
  final int? port;
  final PrintMode mode;

  PrinterDevice({
    required this.id,
    required this.name,
    required this.printerModel,
    this.ipAddress,
    this.port,
    required this.mode,
  });

  factory PrinterDevice.fromJson(Map<String, dynamic> json) {
    return PrinterDevice(
      id: json['id'] as String,
      name: json['name'] as String,
      printerModel: json['printerModel'] as String,
      ipAddress: json['ipAddress'] as String?,
      port: json['port'] as int?,
      mode: PrintMode.values.firstWhere(
        (e) => e.name == json['mode'],
        orElse: () => PrintMode.directIp,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'printerModel': printerModel,
      'ipAddress': ipAddress,
      'port': port,
      'mode': mode.name,
    };
  }

  PrinterDevice copyWith({
    String? id,
    String? name,
    String? printerModel,
    String? ipAddress,
    int? port,
    PrintMode? mode,
  }) {
    return PrinterDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      printerModel: printerModel ?? this.printerModel,
      ipAddress: ipAddress ?? this.ipAddress,
      port: port ?? this.port,
      mode: mode ?? this.mode,
    );
  }
}
