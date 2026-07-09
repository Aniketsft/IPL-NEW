import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../ui/screens/end_of_day_screen.dart';

class EodPdfGenerator {
  static Future<void> generateAndPrint({
    required String workOrder,
    required DateTime productionDate,
    required List<ProductionTrackingItem> items,
  }) async {
    final filteredItems = items;
    final pdf = pw.Document();
    final dateStr = DateFormat('EEE, d MMM yyyy').format(productionDate);
    final printTime = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) => [
          _buildHeader(workOrder, dateStr, printTime),
          pw.SizedBox(height: 20),
          _buildTable(filteredItems, productionDate),
          pw.SizedBox(height: 20),
          _buildFooter(filteredItems),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'EOD_Report_${workOrder}_${DateFormat('yyyyMMdd').format(productionDate)}.pdf',
    );
  }

  static pw.Widget _buildHeader(String wo, String date, String time) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'INNODIS LTD',
              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.amber),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('END OF DAY PRODUCTION REPORT', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Text('Printed on: $time', style: const pw.TextStyle(fontSize: 8)),
              ],
            ),
          ],
        ),
        pw.Divider(thickness: 2, color: PdfColors.amber),
        pw.SizedBox(height: 10),
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Work Order: $wo', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text('Production Date: $date'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildTable(List<ProductionTrackingItem> items, DateTime productionDate) {
    final headers = ['Code', 'Description', 'Quantity', 'Unit', 'Location', 'Lot', 'Expiry'];
    
    // Group items by itemCode for the PDF
    final Map<String, List<ProductionTrackingItem>> grouped = {};
    for (final item in items) {
      grouped.putIfAbsent(item.itemCode, () => []).add(item);
    }
    
    final sortedKeys = grouped.keys.toList()..sort();
    final tableData = sortedKeys.map((code) {
      final productItems = grouped[code]!;
      final first = productItems.first;
      final totalQty = productItems.fold<double>(0, (sum, i) => sum + i.manufactured);
      final totalEa = productItems.fold<double>(0, (sum, i) => sum + i.eaQuantity);
      final lot = first.lotNumber;
      final location = first.location;
      final isEA = first.unit.toUpperCase() == 'EA' || first.unit.toUpperCase() == 'PCS';

      String qtyStr = totalQty.toStringAsFixed(2);
      if (isEA) {
        qtyStr = '${totalQty.toStringAsFixed(2)} KG / ${totalEa.toStringAsFixed(2)} EA';
      }

      return [
        code,
        first.description,
        qtyStr,
        first.unit,
        location,
        lot,
        first.expiryDate != null ? DateFormat('dd/MM/yy').format(first.expiryDate!) : 'N/A',
      ];
    }).toList();

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: tableData,
      border: pw.TableBorder.all(color: PdfColors.grey300),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.amber),
      cellHeight: 25,
      columnWidths: {
        0: const pw.FixedColumnWidth(50),
        1: const pw.FlexColumnWidth(2),
        2: const pw.FixedColumnWidth(120),
        3: const pw.FixedColumnWidth(40),
        4: const pw.FixedColumnWidth(50),
        5: const pw.FixedColumnWidth(70),
        6: const pw.FixedColumnWidth(60),
      },
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.center,
        4: pw.Alignment.center,
        5: pw.Alignment.centerLeft,
        6: pw.Alignment.center,
      },
    );
  }

  static pw.Widget _buildFooter(List<ProductionTrackingItem> items) {
    final totalQty = items.fold(0.0, (sum, item) => sum + item.manufactured);
    
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Divider(),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.Text('Total Production: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text(totalQty.toStringAsFixed(2), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
            pw.SizedBox(width: 50),
          ],
        ),
        pw.SizedBox(height: 40),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            _buildSigLine('Production Manager'),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildSigLine(String title) {
    return pw.Column(
      children: [
        pw.Container(width: 150, decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide()))),
        pw.Text(title, style: const pw.TextStyle(fontSize: 10)),
      ],
    );
  }
}
