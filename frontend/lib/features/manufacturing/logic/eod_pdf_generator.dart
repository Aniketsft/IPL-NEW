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
    final fppItems = items.where((i) => i.isFpp).toList();
    final cutsItems = items.where((i) => !i.isFpp).toList();
    
    final pdf = pw.Document();
    final dateStr = DateFormat('EEE, d MMM yyyy').format(productionDate);
    final printTime = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) => [
          _buildHeader(dateStr, printTime),
          pw.SizedBox(height: 20),
          
          if (cutsItems.isNotEmpty) ...[
            pw.Text('Cuts / Buks', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.amber)),
            pw.SizedBox(height: 10),
            _buildTable(cutsItems),
            pw.SizedBox(height: 20),
          ],
          
          if (fppItems.isNotEmpty) ...[
            pw.Text('FPP Products', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.amber)),
            pw.SizedBox(height: 10),
            _buildTable(fppItems),
            pw.SizedBox(height: 20),
          ],
          
          _buildFooter(items),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name:
          'EOD_Report_${workOrder}_${DateFormat('yyyyMMdd').format(productionDate)}.pdf',
    );
  }

  static pw.Widget _buildHeader(String date, String time) {
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
                color: PdfColors.amber,
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
                  'Printed on: $time',
                  style: const pw.TextStyle(fontSize: 8),
                ),
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
                  pw.Text('Production Date: $date', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildTable(List<ProductionTrackingItem> items) {
    final headers = [
      'WO',
      'Code',
      'Description',
      'Processed',
      'Unprocessed',
      'Total',
      'Unit',
      'Location',
      'Lot',
    ];

    // Group items by itemCode for the PDF to find products spanning multiple WOs
    final Map<String, List<ProductionTrackingItem>> groupedByCode = {};
    for (final item in items) {
      groupedByCode.putIfAbsent(item.itemCode, () => []).add(item);
    }

    final List<List<dynamic>> tableData = [];

    final sortedCodes = groupedByCode.keys.toList()..sort();
    for (final code in sortedCodes) {
      final productItems = groupedByCode[code]!;
      
      // Group by WorkOrder for this specific product
      final Map<String, List<ProductionTrackingItem>> groupedByWO = {};
      for (final item in productItems) {
        final woStr = item.workOrderNumber.isNotEmpty ? item.workOrderNumber : 'PENDING';
        groupedByWO.putIfAbsent(woStr, () => []).add(item);
      }

      final sortedWOs = groupedByWO.keys.toList()..sort();
      for (final wo in sortedWOs) {
        final woItems = groupedByWO[wo]!;
        final first = woItems.first;
        final totalQty = woItems.fold<double>(0, (sum, i) => sum + i.manufactured);
        final totalEa = woItems.fold<double>(0, (sum, i) => sum + i.eaQuantity);
        
        final processedQty = woItems.fold<double>(0, (sum, i) => sum + i.processedQuantity);
        final processedEa = woItems.fold<double>(0, (sum, i) => sum + i.processedEaQuantity);
        
        final unprocessedQty = woItems.fold<double>(0, (sum, i) => sum + i.unprocessedQuantity);
        final unprocessedEa = woItems.fold<double>(0, (sum, i) => sum + i.unprocessedEaQuantity);
        
        final lot = first.lotNumber;
        final location = first.location;
        final isEA = first.unit.toUpperCase() == 'EA' || first.unit.toUpperCase() == 'PCS';

        String totalStr = totalQty.toStringAsFixed(2);
        String procStr = processedQty.toStringAsFixed(2);
        String unprocStr = unprocessedQty.toStringAsFixed(2);
        
        if (isEA) {
          totalStr = '${totalQty.toStringAsFixed(2)} / ${totalEa.toStringAsFixed(2)} EA';
          procStr = '${processedQty.toStringAsFixed(2)} / ${processedEa.toStringAsFixed(2)} EA';
          unprocStr = '${unprocessedQty.toStringAsFixed(2)} / ${unprocessedEa.toStringAsFixed(2)} EA';
        }

        tableData.add([
          wo,
          first.itemCode,
          first.description,
          procStr,
          unprocStr,
          totalStr,
          first.unit,
          location,
          lot,
        ]);
      }

      // If this product spans multiple WOs, add a Subtotal row
      if (sortedWOs.length > 1) {
        final first = productItems.first;
        final totalQty = productItems.fold<double>(0, (sum, i) => sum + i.manufactured);
        final totalEa = productItems.fold<double>(0, (sum, i) => sum + i.eaQuantity);
        
        final processedQty = productItems.fold<double>(0, (sum, i) => sum + i.processedQuantity);
        final processedEa = productItems.fold<double>(0, (sum, i) => sum + i.processedEaQuantity);
        
        final unprocessedQty = productItems.fold<double>(0, (sum, i) => sum + i.unprocessedQuantity);
        final unprocessedEa = productItems.fold<double>(0, (sum, i) => sum + i.unprocessedEaQuantity);
        
        final isEA = first.unit.toUpperCase() == 'EA' || first.unit.toUpperCase() == 'PCS';

        String totalStr = totalQty.toStringAsFixed(2);
        String procStr = processedQty.toStringAsFixed(2);
        String unprocStr = unprocessedQty.toStringAsFixed(2);
        
        if (isEA) {
          totalStr = '${totalQty.toStringAsFixed(2)} / ${totalEa.toStringAsFixed(2)} EA';
          procStr = '${processedQty.toStringAsFixed(2)} / ${processedEa.toStringAsFixed(2)} EA';
          unprocStr = '${unprocessedQty.toStringAsFixed(2)} / ${unprocessedEa.toStringAsFixed(2)} EA';
        }

        tableData.add([
          'TOTAL',
          first.itemCode,
          'Total for ${first.itemCode}',
          procStr,
          unprocStr,
          totalStr,
          first.unit,
          'MULTIPLE',
          'MULTIPLE',
        ]);
      }
    }

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: tableData,
      border: pw.TableBorder.all(color: PdfColors.grey300),
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
        fontSize: 8, // Decreased font size for headers
      ),
      headerAlignments: {
        0: pw.Alignment.center,
        1: pw.Alignment.center,
        2: pw.Alignment.center,
        3: pw.Alignment.center,
        4: pw.Alignment.center,
        5: pw.Alignment.center,
        6: pw.Alignment.center,
        7: pw.Alignment.center,
        8: pw.Alignment.center,
      },
      headerDecoration: const pw.BoxDecoration(color: PdfColors.amber),
      cellHeight: 20,
      cellStyle: const pw.TextStyle(fontSize: 8),
      columnWidths: {
        0: const pw.FixedColumnWidth(60),
        1: const pw.FixedColumnWidth(40),
        2: const pw.FlexColumnWidth(2),
        3: const pw.FixedColumnWidth(65),
        4: const pw.FixedColumnWidth(65),
        5: const pw.FixedColumnWidth(65),
        6: const pw.FixedColumnWidth(30),
        7: const pw.FixedColumnWidth(50),
        8: const pw.FixedColumnWidth(60),
      },
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerLeft,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
        5: pw.Alignment.centerRight,
        6: pw.Alignment.center,
        7: pw.Alignment.centerLeft,
        8: pw.Alignment.centerLeft,
      },
    );
  }

  static pw.Widget _buildFooter(List<ProductionTrackingItem> items) {
    final totalQty = items.fold(0.0, (sum, item) => sum + item.manufactured);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.Text(
              'Total Production: ',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              '${totalQty.toStringAsFixed(2)} KG',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Divider(),
        pw.SizedBox(height: 30),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [_buildSigLine('Production Manager')],
        ),
      ],
    );
  }

  static pw.Widget _buildSigLine(String title) {
    return pw.Column(
      children: [
        pw.Container(
          width: 150,
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide()),
          ),
        ),
        pw.Text(title, style: const pw.TextStyle(fontSize: 10)),
      ],
    );
  }
}
