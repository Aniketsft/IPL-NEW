import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../ui/screens/end_of_day_screen.dart';
import 'package:enterprise_auth_mobile/core/secure_storage_service.dart';

class EodPdfGenerator {
  static Future<void> generateAndPrint({
    required String workOrder,
    required DateTime productionDate,
    required List<ProductionTrackingItem> items,
    bool isSummary = false,
  }) async {
    final fppItems = items.where((i) => i.isFpp).toList();
    final cutsItems = items.where((i) => !i.isFpp).toList();

    final pdf = pw.Document();
    final dateStr = DateFormat('EEE, d MMM yyyy').format(productionDate);
    final printTime = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    final username = await SecureStorageService().getUsername() ?? 'Unknown';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) => [
          _buildHeader(dateStr, printTime, username, isSummary: isSummary),
          pw.SizedBox(height: 20),

          // ── CUTS / BULK SECTION ──
          if (cutsItems.isNotEmpty) ...[
            _buildSectionHeader('✂  CUTS / BULK'),
            pw.SizedBox(height: 10),
            if (isSummary)
              _buildTable(cutsItems)
            else
              ..._buildWOSubSections(cutsItems),
            _buildSectionTotals(cutsItems),
            pw.SizedBox(height: 24),
          ],

          // ── FPP SECTION ──
          if (fppItems.isNotEmpty) ...[
            _buildSectionHeader('🐔  FPP PRODUCTS'),
            pw.SizedBox(height: 10),
            if (isSummary)
              _buildTable(fppItems)
            else
              ..._buildWOSubSections(fppItems),
            _buildSectionTotals(fppItems),
            pw.SizedBox(height: 24),
          ],
        ],
        footer: (pw.Context context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(color: PdfColors.grey, fontSize: 9),
          ),
        ),
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'EOD_${isSummary ? 'Summary' : 'Detailed'}_${workOrder}_${DateFormat('yyyyMMdd').format(productionDate)}.pdf',
    );
  }

  // ──────────────────────────────────────────
  // Section header (amber bar)
  // ──────────────────────────────────────────
  static pw.Widget _buildSectionHeader(String title) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: const pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.black, width: 1.5),
        ),
      ),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 13,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.black,
        ),
      ),
    );
  }

  // ──────────────────────────────────────────
  // Work-order sub-sections for one section
  // ──────────────────────────────────────────
  static List<pw.Widget> _buildWOSubSections(List<ProductionTrackingItem> items) {
    // Group by Work Order
    final Map<String, List<ProductionTrackingItem>> byWO = {};
    for (final item in items) {
      final key = item.workOrderNumber.isNotEmpty ? item.workOrderNumber : 'PENDING';
      byWO.putIfAbsent(key, () => []).add(item);
    }

    final sortedWOs = byWO.keys.toList()..sort();
    final widgets = <pw.Widget>[];

    for (final wo in sortedWOs) {
      final woItems = byWO[wo]!;
      widgets.add(_buildWOHeader(wo));
      widgets.add(pw.SizedBox(height: 4));
      widgets.add(_buildTable(woItems));
      widgets.add(pw.SizedBox(height: 12));
    }

    return widgets;
  }

  // ──────────────────────────────────────────
  // Work-order sub-header
  // ──────────────────────────────────────────
  static pw.Widget _buildWOHeader(String wo) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey200,
        border: const pw.Border(
          left: pw.BorderSide(color: PdfColors.black, width: 3),
        ),
      ),
      child: pw.Text(
        'Work Order: $wo',
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
      ),
    );
  }

  // ──────────────────────────────────────────
  // Section totals row
  // ──────────────────────────────────────────
  static pw.Widget _buildSectionTotals(List<ProductionTrackingItem> items) {
    final totalKg = items.fold(0.0, (s, i) => s + i.manufactured);
    final processedKg = items.fold(0.0, (s, i) => s + i.processedQuantity);
    final unprocessedKg = items.fold(0.0, (s, i) => s + i.unprocessedQuantity);

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: const pw.BoxDecoration(color: PdfColors.grey100),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          _totCell('X3:', processedKg),
          pw.SizedBox(width: 24),
          _totCell('HIPO:', unprocessedKg),
          pw.SizedBox(width: 24),
          _totCell('Section Total:', totalKg, bold: true),
        ],
      ),
    );
  }

  static pw.Widget _totCell(String label, double value, {bool bold = false}) {
    return pw.Row(
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 8, color: PdfColors.black)),
        pw.SizedBox(width: 4),
        pw.Text(
          '${value.toStringAsFixed(2)} KG',
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────
  // Table for a single WO
  // ──────────────────────────────────────────
  static pw.Widget _buildTable(List<ProductionTrackingItem> items) {
    const headers = [
      'Code',
      'Description',
      'X3',
      'Hipo',
      'Total',
      'Unit',
      'Location',
      'Lot',
    ];

    // Group by itemCode + lotNumber for accurate per-lot summary
    final Map<String, List<ProductionTrackingItem>> byCode = {};
    for (final item in items) {
      final key = '${item.itemCode}__${item.lotNumber}';
      byCode.putIfAbsent(key, () => []).add(item);
    }

    final List<List<dynamic>> tableData = [];
    final sortedCodes = byCode.keys.toList()..sort();

    for (final code in sortedCodes) {
      final codeItems = byCode[code]!;
      final first = codeItems.first;
      final isEA = first.unit.toUpperCase() == 'EA' || first.unit.toUpperCase() == 'PCS';

      final totalQty = codeItems.fold(0.0, (s, i) => s + i.manufactured);
      final totalEa = codeItems.fold(0.0, (s, i) => s + i.eaQuantity);
      final processedQty = codeItems.fold(0.0, (s, i) => s + i.processedQuantity);
      final processedEa = codeItems.fold(0.0, (s, i) => s + i.processedEaQuantity);
      final unprocessedQty = codeItems.fold(0.0, (s, i) => s + i.unprocessedQuantity);
      final unprocessedEa = codeItems.fold(0.0, (s, i) => s + i.unprocessedEaQuantity);

      final totalStr = isEA
          ? '${totalQty.toStringAsFixed(2)} / ${totalEa.toStringAsFixed(2)} EA'
          : totalQty.toStringAsFixed(2);
      final procStr = isEA
          ? '${processedQty.toStringAsFixed(2)} / ${processedEa.toStringAsFixed(2)} EA'
          : processedQty.toStringAsFixed(2);
      final unprocStr = isEA
          ? '${unprocessedQty.toStringAsFixed(2)} / ${unprocessedEa.toStringAsFixed(2)} EA'
          : unprocessedQty.toStringAsFixed(2);

      tableData.add([
        first.itemCode,
        first.description,
        procStr,
        unprocStr,
        totalStr,
        first.unit,
        first.location,
        first.lotNumber,
      ]);
    }

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: tableData,
      border: pw.TableBorder.all(color: PdfColors.grey300),
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.black,
        fontSize: 8,
      ),
      headerDecoration: const pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.black, width: 1),
        ),
      ),
      cellHeight: 20,
      cellStyle: const pw.TextStyle(fontSize: 8),
      columnWidths: {
        0: const pw.FixedColumnWidth(45),
        1: const pw.FlexColumnWidth(2),
        2: const pw.FixedColumnWidth(65),
        3: const pw.FixedColumnWidth(65),
        4: const pw.FixedColumnWidth(65),
        5: const pw.FixedColumnWidth(28),
        6: const pw.FixedColumnWidth(50),
        7: const pw.FixedColumnWidth(58),
      },
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
        5: pw.Alignment.center,
        6: pw.Alignment.centerLeft,
        7: pw.Alignment.centerLeft,
      },
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey50),
    );
  }

  // ──────────────────────────────────────────
  // Page header
  // ──────────────────────────────────────────
  static pw.Widget _buildHeader(String date, String time, String username, {bool isSummary = false}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'INNODIS POULTRY LTD',
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'END OF DAY PRODUCTION REPORT',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  isSummary ? 'Summary Report' : 'Detailed Report',
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.black,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'Printed on: $time',
                  style: const pw.TextStyle(fontSize: 8),
                ),
                pw.Text(
                  'Printed by: $username',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ],
            ),
          ],
        ),
        pw.Divider(thickness: 1.5, color: PdfColors.black),
        pw.SizedBox(height: 8),
        pw.Text(
          'Production Date: $date',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
  }

}
