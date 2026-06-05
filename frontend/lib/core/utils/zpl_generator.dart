import 'package:intl/intl.dart';

class ZplGenerator {
  /// Generates a premium ZPL label for a 100mm x 100mm (4x4 inch) label.
  /// Assumes 203 DPI (8 dots/mm). 100mm = 800 dots.
  static String generateItemLabel({
    required String soNumber,
    required String customerName,
    String? customerCode,
    required String productCode,
    required String description,
    required double weight,
    required String unit,
    required String qrData,
    String? lotNumber,
    String? productionDate,
    String? expiryDate,
    String? auditId,
    String? salesman,
    double? eaQuantity,
  }) {
    final now = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    DateTime parsedProdDate;
    if (productionDate != null) {
      try {
        parsedProdDate = DateFormat('dd/MM/yyyy').parse(productionDate);
      } catch (_) {
        parsedProdDate = DateTime.now();
      }
    } else {
      parsedProdDate = DateTime.now();
    }

    final prodDate = DateFormat('dd/MM/yyyy').format(parsedProdDate);
    final expDate =
        expiryDate ??
        DateFormat(
          'dd/MM/yyyy',
        ).format(parsedProdDate.add(const Duration(days: 5)));

    String quantityZpl;
    if (unit.toUpperCase() == 'EA' || unit.toUpperCase() == 'PCS') {
      quantityZpl =
          "^FO40,490^A0N,70,70^FD${weight.toStringAsFixed(3)} KG^FS\n"
          "^FO40,570^A0N,70,70^FD${(eaQuantity ?? 0).toStringAsFixed(3)} $unit^FS";
    } else {
      quantityZpl =
          "^FO40,490^A0N,70,70^FD${weight.toStringAsFixed(3)} $unit^FS";
    }

    return """
^XA
^CI28
^PW780
^LL780

-- Top Section: Code & Description --

^FO400,40^A0N,30,30^FB360,2,R^FDINNODIS POULTRY LTD^FS
^FO40,40^A0N,40,40^FD$productCode^FS
^FO40,80^A0N,30,30^FB700,2,L^FD$description^FS


-- Customer & SO --
^FO40,140^A0N,35,35^FD${customerCode ?? "N/A"}^FS
^FO40,175^A0N,35,35^FB700,1,L^FD$customerName^FS
^FO40,210^A0N,35,35^FDIPLSO Number: $soNumber^FS

-- Middle Divider --
^FO40,240^GB700,3,3^FS

-- Batch/Date Info --
^FO40,270^A0N,30,30^FDLot Number: ${lotNumber ?? "N/A"}^FS
^FO460,270^A0N,25,25^FDSM: ${salesman ?? ""}^FS
^FO40,315^A0N,30,30^FDProduction Date: $prodDate^FS
^FO40,360^A0N,30,30^FDExpiry Date: $expDate^FS

-- QR Code (Moved up 2cm from 480 to 320) --
^FO460,360^BQN,2,6^FDQA,$qrData^FS

-- Large Quantity --
^FO40,440^A0N,40,40^FDQuantity:^FS
$quantityZpl

-- Footer / Audit --
^FO40,750^A0N,18,18^FDPrinted at: $now^FS

^XZ
""";
  }

  static String generateCrateLabel({
    required String soNumber,
    required String customerName,
    String? customerCode,
    required String deliveryDate,
    required List<Map<String, String>> items,
    required String unit,
    required String qrData,
    String? auditId,
  }) {
    double total = items.fold(
      0.0,
      (val, item) => val + (double.tryParse(item['weight'] ?? '0') ?? 0.0),
    );
    final now = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    int totalItems = items.length;
    bool separateQrPage = totalItems > 10;
    int itemsPerPage = separateQrPage ? 20 : 10;

    int productPages = (totalItems / itemsPerPage).ceil();
    if (productPages == 0) productPages = 1;

    // Dynamic Spacing based on Delivery Date
    bool hasDelivery = deliveryDate != "N/A" && deliveryDate.isNotEmpty;
    int afterDividerY = hasDelivery ? 280 : 230;
    int itemsStartY = hasDelivery ? 320 : 270;

    // Dynamic QR sizing
    int qrMag = 6;
    int qrX = 380; // Moved 1cm (80 dots) left for Crate Label
    if (qrData.length > 500)
      qrMag = 3;
    else if (qrData.length > 300)
      qrMag = 4;
    else if (qrData.length > 150)
      qrMag = 5;

    int centerQrX = 280;
    if (qrMag == 5) centerQrX = 300;
    if (qrMag == 4) centerQrX = 320;
    if (qrMag == 3) centerQrX = 335;

    int centerQrY = hasDelivery ? 320 : 270;

    String finalZpl = "";

    for (int page = 0; page < productPages; page++) {
      int startIdx = page * itemsPerPage;
      int endIdx = startIdx + itemsPerPage;
      if (endIdx > totalItems) endIdx = totalItems;

      String itemLines = "";
      int yLeft = itemsStartY;
      int yRight = itemsStartY;

      for (var i = startIdx; i < endIdx; i++) {
        bool isLeft = (i - startIdx) < 10; // First 10 items on left

        int y = isLeft ? yLeft : yRight;
        int xCode = isLeft ? 40 : 420;
        int xWeight = isLeft ? 240 : 620;

        itemLines += "^FO$xCode,$y^A0N,25,25^FD${items[i]['itemCode']}^FS\n";
        String displayUnit = (unit == 'EA' || unit == 'PCS') ? 'KG' : unit;
        String weightStr = "${items[i]['weight']} $displayUnit";
        if (items[i]['eaQuantity'] != null &&
            double.tryParse(items[i]['eaQuantity']!) != null &&
            double.parse(items[i]['eaQuantity']!) > 0) {
          weightStr =
              "${double.parse(items[i]['eaQuantity']!).toStringAsFixed(3)}EA  $weightStr";
        }
        itemLines += "^FO$xWeight,$y^A0N,25,25^FD$weightStr^FS\n";

        if (isLeft)
          yLeft += 30;
        else
          yRight += 30;
      }

      String pageTitle = separateQrPage
          ? "CRATE(${page + 1}/$productPages)"
          : "CRATE";

      String headers =
          "^FO40,$afterDividerY^A0N,25,25^FDPRODUCT^FS\n^FO240,$afterDividerY^A0N,25,25^FDWEIGHT^FS";
      if (separateQrPage && (endIdx - startIdx) > 10) {
        headers +=
            "\n^FO420,$afterDividerY^A0N,25,25^FDPRODUCT^FS\n^FO620,$afterDividerY^A0N,25,25^FDWEIGHT^FS";
      }

      String qrBlock = separateQrPage
          ? ""
          : "^FO$qrX,$itemsStartY^BQN,2,$qrMag^FDQA,$qrData^FS";
      String deliveryBlock = hasDelivery
          ? "^FO40,230^A0N,30,30^FDDELIVERY: $deliveryDate^FS"
          : "";
      String customerCodeBlock = customerCode ?? "N/A";

      finalZpl +=
          """
^XA
^CI28
^PW780
^LL780

-- Top Section: Code & Description --

^FO400,40^A0N,30,30^FB360,2,R^FDINNODIS POULTRY LTD^FS
^FO40,40^A0N,40,40^FD$pageTitle^FS

-- Customer & SO --
^FO40,90^A0N,35,35^FD$customerCodeBlock^FS
^FO40,125^A0N,35,35^FB700,1,L^FD$customerName^FS
^FO40,160^A0N,35,35^FDIPLSO Number: $soNumber^FS

-- Middle Divider --
^FO40,200^GB700,3,3^FS

-- Delivery Date Info --
$deliveryBlock

-- Header --
$headers

-- QR Code --
$qrBlock

-- Items List --
$itemLines
-- Large Quantity --
^FO40,620^A0N,30,30^FDTOTAL WEIGHT:^FS
^FO40,650^A0N,50,50^FD${total.toStringAsFixed(3)} $unit^FS

-- Footer / Audit --
^FO40,750^A0N,18,18^FDPrinted at: $now^FS

^XZ
""";
    }

    if (separateQrPage) {
      String deliveryBlock = hasDelivery
          ? "^FO40,230^A0N,30,30^FDDELIVERY: $deliveryDate^FS"
          : "";
      String customerCodeBlock = customerCode ?? "N/A";

      finalZpl +=
          """
^XA
^CI28
^PW780
^LL780

-- Top Section: Code & Description --

^FO400,40^A0N,30,30^FB360,2,R^FDINNODIS POULTRY LTD^FS
^FO40,40^A0N,40,40^FDCRATE QR LABEL^FS

-- Customer & SO --
^FO40,90^A0N,35,35^FD$customerCodeBlock^FS
^FO40,125^A0N,35,35^FB700,1,L^FD$customerName^FS
^FO40,160^A0N,35,35^FDIPLSO Number: $soNumber^FS

-- Middle Divider --
^FO40,200^GB700,3,3^FS

-- Delivery Date Info --
$deliveryBlock

-- QR Code Prominent --
^FO$centerQrX,$centerQrY^BQN,2,$qrMag^FDQA,$qrData^FS

-- Footer / Audit --
^FO40,750^A0N,18,18^FDPrinted at: $now^FS

^XZ
""";
    }

    return finalZpl;
  }

  static String generateEodLabel({
    required String workOrder,
    required String dateStr,
    required List<dynamic> items,
  }) {
    final now = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    double totalWeight = items.fold(
      0.0,
      (sum, item) => sum + (item.manufactured ?? 0.0),
    );

    String itemLines = "";
    int y = 350;
    // Show top 8 items on the label summary
    for (var i = 0; i < items.length && i < 8; i++) {
      final item = items[i];
      itemLines += "^FO50,$y^A0N,22,22^FD${item.itemCode}^FS";
      itemLines +=
          "^FO200,$y^A0N,22,22^FD${item.manufactured.toStringAsFixed(2)}^FS";
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

  static String generatePaletteLabel({
    required int soCount,
    required String customerName,
    required String deliveryDate,
    required double totalWeight,
    required String unit,
    required String qrData,
    required Map<String, Map<String, dynamic>> manifest,
    String? auditId,
  }) {
    final now = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    String itemLines = "";
    int y = 360;

    int lineCount = 0;
    for (var entry in manifest.entries) {
      if (lineCount >= 8) break;
      final so = entry.key;
      final data = entry.value;
      final items = List<Map<String, String>>.from(data['items'] ?? []);

      itemLines += "^FO40,$y^A0N,20,20^FDSO: $so^FS";
      y += 25;
      lineCount++;

      for (var item in items) {
        if (lineCount >= 8) break;
        String prod = item['itemCode'] ?? 'N/A';
        String wgt = '${item['weight'] ?? '0.00'} $unit';
        itemLines += "^FO60,$y^A0N,20,20^FD$prod^FS";
        itemLines += "^FO300,$y^A0N,20,20^FD$wgt^FS";
        y += 25;
        lineCount++;
      }
    }

    return """
^XA
^CI28
^PW780
^LL780

-- Top Section: Code & Description --

^FO400,40^A0N,30,30^FB360,2,R^FDINNODIS POULTRY LTD^FS
^FO40,40^A0N,40,40^FDPALETTE MASTER LABEL^FS

-- Customer & SO --
^FO40,140^A0N,35,35^FB700,1,L^FDCUST: $customerName^FS
^FO40,185^A0N,35,35^FDTOTAL SOs: $soCount^FS

-- Middle Divider --
^FO40,240^GB700,3,3^FS

-- Delivery Date Info --
^FO40,270^A0N,30,30^FDDELIVERY: $deliveryDate^FS

-- Header --
^FO40,320^A0N,25,25^FDEXPLODED MANIFEST^FS

-- QR Code --
^FO460,360^BQN,2,6^FDQA,$qrData^FS

-- Items List --
$itemLines

-- Large Quantity --
^FO40,620^A0N,30,30^FDTOTAL WEIGHT:^FS
^FO40,650^A0N,50,50^FD${totalWeight.toStringAsFixed(3)} $unit^FS

-- Footer / Audit --
^FO40,700^GB700,3,3^FS
^FO40,720^A0N,25,25^FDLabel ID: ${auditId ?? "INTERNAL"}^FS
^FO40,750^A0N,18,18^FDPrinted at: $now^FS

^XZ
""";
  }
}
