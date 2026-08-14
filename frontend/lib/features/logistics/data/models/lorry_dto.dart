class LorryDto {
  final int lanNum;      // LANNUM_0 — the value that goes to the DB/SOAP
  final String lanMes;   // LANMES_0 — the label the user sees

  LorryDto({required this.lanNum, required this.lanMes});

  factory LorryDto.fromJson(Map<String, dynamic> json) => LorryDto(
    lanNum: json['lanNum'] as int,
    lanMes: json['lanMes'] as String,
  );
}
