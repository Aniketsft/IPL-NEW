import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class OrderCompletionPdfGenerator {
  static Future<void> generateAndPrint({
    required DateTime targetDate,
    required List<Map<String, dynamic>> orderDetails,
  }) async {
    final pdf = pw.Document();
    final dateStr = DateFormat('EEE, d MMM yyyy').format(targetDate);
    final printTime = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    // Group the details by SO Number
    final Map<String, List<Map<String, dynamic>>> groupedBySO = {};
    for (final detail in orderDetails) {
      final so = detail['soNumber'] as String? ?? 'UNKNOWN';
      groupedBySO.putIfAbsent(so, () => []).add(detail);
    }

    final sortedSOs = groupedBySO.keys.toList()..sort();

    // Calculate how many SOs per page approximately, but MultiPage handles it better.
    // We will build a list of widgets that MultiPage will layout across pages.
    
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          final List<pw.Widget> elements = [
            _buildHeader(dateStr, printTime),
            pw.SizedBox(height: 20),
          ];

          if (sortedSOs.isEmpty) {
            elements.add(
              pw.Center(
                child: pw.Text('No sales orders found for this date.', style: pw.TextStyle(fontSize: 14)),
              ),
            );
          } else {
            for (final so in sortedSOs) {
              final items = groupedBySO[so]!;
              final first = items.first;
              
              elements.add(_buildSOHeader(so, first));
              elements.add(pw.SizedBox(height: 10));
              elements.add(_buildTable(items));
              elements.add(pw.SizedBox(height: 25)); // Spacing between orders
            }
          }
          
          return elements;
        },
        footer: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(top: 10.0),
            child: pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Order_Completion_Report_${DateFormat('yyyyMMdd').format(targetDate)}.pdf',
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
                  'ORDER COMPLETION REPORT',
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
                  pw.Text('Delivery Date: $date', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildSOHeader(String soNumber, Map<String, dynamic> firstItem) {
    final customer = firstItem['customerName'] as String? ?? 'Unknown Customer';
    final status = firstItem['headerStatusLabel'] as String? ?? 'OPEN';
    
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey200,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('SO: $soNumber', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
          pw.Text('Customer: $customer', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
          pw.Text('Status: $status', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: status.toUpperCase() == 'CLOSED' ? PdfColors.green700 : PdfColors.amber700)),
        ],
      ),
    );
  }

  static pw.Widget _buildTable(List<Map<String, dynamic>> items) {
    final headers = [
      'Code',
      'Description',
      'Lot',
      'Expiry',
      'Location',
      'Order Qty',
      'Scanned Qty',
      'Prepared?',
    ];

    final List<List<dynamic>> tableData = [];

    for (final item in items) {
      final code = item['itemCode'] as String? ?? '';
      final desc = item['description'] as String? ?? '';
      final lot = item['lot'] as String? ?? 'N/A';
      
      final detLocation = item['location'] as String?;
      final scanLocation = item['scanLocation'] as String?;
      String location = 'N/A';
      if (detLocation != null && detLocation.trim().isNotEmpty && detLocation.toUpperCase() != 'NULL') {
        location = detLocation;
      } else if (scanLocation != null && scanLocation.trim().isNotEmpty && scanLocation.toUpperCase() != 'NULL') {
        location = scanLocation;
      }

      String expiry = 'N/A';
      final scanTimestamp = item['scanTimestamp'] as String?;
      final createdAt = item['createdAt'] as String?;
      final timeStr = (scanTimestamp != null && scanTimestamp.isNotEmpty) ? scanTimestamp : createdAt;
      
      if (timeStr != null && timeStr.isNotEmpty) {
        final parsed = DateTime.tryParse(timeStr);
        if (parsed != null) {
          expiry = DateFormat('dd MMM yyyy').format(parsed.add(const Duration(days: 5)));
        }
      }
      
      final orderedQty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
      final scannedQty = (item['reconciledProduced'] as num?)?.toDouble() ?? 0.0;
      final unit = item['unit'] as String? ?? '';
      
      final headerStatus = item['headerStatusLabel'] as String? ?? '';
      final isClosed = headerStatus.toUpperCase() == 'CLOSED';
      
      final isPreparedNum = item['is_prepared'];
      final isPreparedLine = isPreparedNum == 1 || isPreparedNum == '1' || isPreparedNum == true;
      
      final isPrepared = isClosed || isPreparedLine;

      tableData.add([
        code,
        desc,
        lot,
        expiry,
        location,
        '${orderedQty.toStringAsFixed(2)} $unit',
        '${scannedQty.toStringAsFixed(2)} $unit',
        isPrepared ? 'YES' : 'NO',
      ]);
    }

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: tableData,
      border: pw.TableBorder.all(color: PdfColors.grey300),
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
        fontSize: 7,
      ),
      headerAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerLeft,
        3: pw.Alignment.centerLeft,
        4: pw.Alignment.centerLeft,
        5: pw.Alignment.centerRight,
        6: pw.Alignment.centerRight,
        7: pw.Alignment.center,
      },
      headerDecoration: const pw.BoxDecoration(color: PdfColors.amber),
      cellHeight: 20,
      cellStyle: const pw.TextStyle(fontSize: 7),
      columnWidths: {
        0: const pw.FixedColumnWidth(40), // Code
        1: const pw.FlexColumnWidth(3), // Description
        2: const pw.FixedColumnWidth(45), // Lot
        3: const pw.FixedColumnWidth(40), // Expiry
        4: const pw.FixedColumnWidth(45), // Location
        5: const pw.FixedColumnWidth(55), // Order Qty
        6: const pw.FixedColumnWidth(55), // Scanned Qty
        7: const pw.FixedColumnWidth(40), // Prepared?
      },
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerLeft,
        3: pw.Alignment.centerLeft,
        4: pw.Alignment.centerLeft,
        5: pw.Alignment.centerRight,
        6: pw.Alignment.centerRight,
        7: pw.Alignment.center,
      },
    );
  }
}
