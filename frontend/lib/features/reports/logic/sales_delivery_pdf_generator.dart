import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class SalesDeliveryPdfGenerator {
  static Future<void> generateAndPrint({
    required DateTime targetDate,
    required List<Map<String, dynamic>> orderDetails,
  }) async {
    final pdf = pw.Document();
    final dateStr = DateFormat('EEE, d MMM yyyy').format(targetDate);
    final printTime = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    // Group the details by Lorry Number, then by SO Number
    final Map<String, Map<String, List<Map<String, dynamic>>>> groupedByLorry = {};
    for (final detail in orderDetails) {
      final lorry = detail['lorryNumber']?.toString() ?? detail['lorryShortCode']?.toString() ?? 'UNASSIGNED';
      final so = detail['soNumber']?.toString() ?? 'UNKNOWN';
      
      groupedByLorry.putIfAbsent(lorry, () => {});
      groupedByLorry[lorry]!.putIfAbsent(so, () => []).add(detail);
    }

    final sortedLorries = groupedByLorry.keys.toList()..sort();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          final List<pw.Widget> elements = [
            _buildHeader(dateStr, printTime),
            pw.SizedBox(height: 20),
          ];

          if (sortedLorries.isEmpty) {
            elements.add(
              pw.Center(
                child: pw.Text('No sales delivery records found for this date.', style: pw.TextStyle(fontSize: 14)),
              ),
            );
          } else {
            for (final lorry in sortedLorries) {
              elements.add(_buildLorryHeader(lorry));
              elements.add(pw.SizedBox(height: 10));

              final sosMap = groupedByLorry[lorry]!;
              final sortedSOs = sosMap.keys.toList()..sort();

              for (final so in sortedSOs) {
                final items = sosMap[so]!;
                final first = items.first;
                
                elements.add(_buildSOHeader(so, first));
                elements.add(pw.SizedBox(height: 5));
                elements.add(_buildTable(items));
                elements.add(pw.SizedBox(height: 15));
              }
              elements.add(pw.SizedBox(height: 20));
            }
          }
          
          return elements;
        },
        footer: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(top: 10),
            child: pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: pw.TextStyle(color: PdfColors.grey, fontSize: 10),
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Sales_Delivery_Report_$dateStr.pdf',
    );
  }

  static pw.Widget _buildHeader(String dateStr, String printTime) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Sales Delivery Report',
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.amber,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Delivery Date: $dateStr',
              style: pw.TextStyle(
                fontSize: 14,
                color: PdfColors.grey700,
              ),
            ),
          ],
        ),
        pw.Text(
          'Printed: $printTime',
          style: pw.TextStyle(
            fontSize: 10,
            color: PdfColors.grey600,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildLorryHeader(String lorry) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: const pw.BoxDecoration(
        color: PdfColors.grey300,
      ),
      child: pw.Row(
        children: [
          pw.Text(
            'Lorry: $lorry',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSOHeader(String soNumber, Map<String, dynamic> firstItem) {
    final salesman = firstItem['salesman']?.toString() ?? 'N/A';
    final customerName = firstItem['customerName']?.toString() ?? 'N/A';
    final customerCode = firstItem['customerCode']?.toString() ?? 'N/A';

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        border: pw.Border(left: pw.BorderSide(color: PdfColors.amber, width: 3)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Order: $soNumber',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            'Salesman: $salesman',
            style: pw.TextStyle(fontSize: 10),
          ),
          pw.Text(
            'Customer: $customerName ($customerCode)',
            style: pw.TextStyle(fontSize: 10),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildTable(List<Map<String, dynamic>> items) {
    final headers = [
      'Item Code',
      'Description',
      'Lot Number',
      'Expiry Date',
      'Location',
      'Ordered Qty',
      'Produced Qty',
      'Delivered Qty',
    ];

    final data = items.map((item) {
      final code = item['itemCode']?.toString() ?? '';
      final desc = item['description']?.toString() ?? '';
      final lot = item['lotNumber']?.toString() ?? '';
      
      String expiry = '';
      if (item['expiryDate'] != null) {
        try {
          final dt = DateTime.parse(item['expiryDate'].toString());
          expiry = DateFormat('dd MMM yyyy').format(dt);
        } catch (_) {}
      }

      final loc = item['location']?.toString() ?? '';
      final ordQty = (item['orderedQty'] as num?)?.toStringAsFixed(2) ?? '0.00';
      final prodQty = (item['producedQty'] as num?)?.toStringAsFixed(2) ?? '0.00';
      final delQty = (item['deliveredQty'] as num?)?.toStringAsFixed(2) ?? '0.00';

      return [code, desc, lot, expiry, loc, ordQty, prodQty, delQty];
    }).toList();

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      headerStyle: pw.TextStyle(
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      ),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.amber),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: {
        5: pw.Alignment.centerRight,
        6: pw.Alignment.centerRight,
        7: pw.Alignment.centerRight,
      },
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(4),
        2: const pw.FlexColumnWidth(2),
        3: const pw.FlexColumnWidth(2),
        4: const pw.FlexColumnWidth(2),
        5: const pw.FlexColumnWidth(2),
        6: const pw.FlexColumnWidth(2),
        7: const pw.FlexColumnWidth(2),
      },
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey50),
    );
  }
}
