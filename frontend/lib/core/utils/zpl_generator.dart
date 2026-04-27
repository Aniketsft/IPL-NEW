import 'package:intl/intl.dart';

class ZplGenerator {
  /// Generates a premium ZPL label for a 100mm x 100mm (4x4 inch) label.
  /// Assumes 203 DPI (8 dots/mm). 100mm = 800 dots.
  static String generateItemLabel({
    required String soNumber,
    required String customerName,
    required String productCode,
    required double weight,
    required String unit,
    required String qrData,
    String? auditId,
  }) {
    final now = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    
    // ^XA: Start Label
    // ^CI28: Unicode encoding
    // ^PW800: Print Width 800 dots (100mm)
    // ^LL800: Label Length 800 dots (100mm)
    
    return """
^XA
^CI28
^PW780
^LL780

-- Header Section (Compact) --
^FO40,40^GB700,50,4^FS
^FO60,52^A0N,28,28^FB660,1,C^FDITEM IDENTIFICATION^FS

-- Product Code (Large) --
^FO40,110^A0N,45,45^FDITEM:^FS
^FO180,105^A0N,70,70^FD$productCode^FS

-- Divider --
^FO40,190^GB700,3,3^FS

-- Customer & SO Section (Safe Wrapping) --
^FO40,210^A0N,24,24^FDCUSTOMER:^FS
^FO40,240^A0N,28,28^FB700,2,L^FD${customerName.toUpperCase()}^FS

^FO40,305^A0N,24,24^FDSALES ORDER:^FS
^FO190,305^A0N,28,28^FD$soNumber^FS

-- Divider --
^FO40,350^GB700,3,3^FS

-- Split Footer (Weight Left / QR Right) --
^FO40,400^A0N,35,35^FDWEIGHT:^FS
^FO40,440^A0N,90,90^FD${weight.toStringAsFixed(2)} $unit^FS

-- QR Code (Bottom Right, 3cm x 3cm) --
^FO500,430^BQN,2,9^FDQA,$qrData^FS

-- Metadata (Stacked below weight) --
^FO40,650^GB700,3,3^FS
^FO40,670^A0N,20,20^FDTRACKING: ${auditId ?? "INTERNAL"}^FS
^FO40,700^A0N,18,18^FDPRINTED: $now^FS
^FO40,730^A0N,18,18^FDINDUSTRIAL QUALITY VERIFIED^FS

^XZ
""";
  }

  static String generateCrateLabel({
    required String soNumber,
    required String customerName,
    required String deliveryDate,
    required List<Map<String, String>> items,
    required String unit,
    required String qrData,
    String? auditId,
  }) {
    double total = items.fold(0.0, (val, item) => val + (double.tryParse(item['weight'] ?? '0') ?? 0.0));
    final now = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    String itemLines = "";
    int y = 420;
    for (var i = 0; i < items.length && i < 8; i++) {
      itemLines += "^FO50,$y^A0N,25,25^FD${items[i]['itemCode']}^FS";
      itemLines += "^FO600,$y^A0N,25,25^FD${items[i]['weight']} $unit^FS";
      y += 35;
    }

    return """
^XA
^CI28
^PW780
^LL780

^FO50,40^GB700,80,80^FS
^FO100,60^A0N,45,45^FR^FB612,1,C^FDCRATE SUMMARY LABEL^FS

^FO50,150^A0N,30,30^FDCUSTOMER:^FS
^FO220,150^A0N,40,40^FD${customerName.toUpperCase()}^FS

^FO50,210^A0N,30,30^FDSALES ORDER:^FS
^FO280,210^A0N,35,35^FD$soNumber^FS

^FO50,260^A0N,30,30^FDDELIVERY:^FS
^FO220,260^A0N,35,35^FD$deliveryDate^FS

^FO50,320^GB700,60,4^FS
^FO70,335^A0N,30,30^FDPRODUCT^FS
^FO600,335^A0N,30,30^FDWEIGHT^FS

$itemLines

^FO50,700^GB700,3,3^FS
^FO50,720^A0N,30,30^FDTOTAL WEIGHT:^FS
^FO300,715^A0N,60,60^FD${total.toStringAsFixed(2)} $unit^FS

^FO30,500^BQN,2,9^FDQA,$qrData^FS

^XZ
""";
  }

  static String generateEodLabel({
    required String workOrder,
    required String dateStr,
    required List<dynamic> items,
  }) {
    final now = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    double totalWeight = items.fold(0.0, (sum, item) => sum + (item.manufactured ?? 0.0));

    String itemLines = "";
    int y = 350;
    // Show top 8 items on the label summary
    for (var i = 0; i < items.length && i < 8; i++) {
      final item = items[i];
      itemLines += "^FO50,$y^A0N,22,22^FD${item.itemCode}^FS";
      itemLines += "^FO200,$y^A0N,22,22^FD${item.manufactured.toStringAsFixed(2)}^FS";
      itemLines += "^FO350,$y^A0N,22,22^FD${item.location}^FS";
      itemLines += "^FO500,$y^A0N,22,22^FD${item.lotNumber}^FS";
      y += 30;
    }

    return """
^XA
^CI28
^PW800
^LL800

^FO50,40^GB700,70,70^FS
^FO100,60^A0N,40,40^FR^FB612,1,C^FDEOD PRODUCTION SUMMARY^FS

^FO50,140^A0N,30,30^FDWORK ORDER:^FS
^FO280,140^A0N,35,35^FD$workOrder^FS

^FO50,190^A0N,30,30^FDPROD DATE:^FS
^FO250,190^A0N,35,35^FD$dateStr^FS

^FO50,250^GB700,3,3^FS
^FO50,270^A0N,30,30^FDTOTAL PRODUCTION:^FS
^FO350,265^A0N,50,50^FD${totalWeight.toStringAsFixed(3)} KG^FS
^FO50,315^GB700,3,3^FS

^FO50,325^A0N,20,20^FDCODE^FS
^FO200,325^A0N,20,20^FDQTY^FS
^FO350,325^A0N,20,20^FDLOC^FS
^FO500,325^A0N,20,20^FDLOT^FS

$itemLines

^FO50,680^GB700,3,3^FS
^FO50,700^A0N,20,20^FDPrinted at: $now^FS
^FO50,730^A0N,20,20^FDIndustrial Tracking System - EOD Module^FS

^FO50,770^GB700,25,25^FS
^FO100,775^A0N,18,18^FR^FB612,1,C^FDVERIFIED BY PRODUCTION SUPERVISOR^FS

^XZ
""";
  }
}
