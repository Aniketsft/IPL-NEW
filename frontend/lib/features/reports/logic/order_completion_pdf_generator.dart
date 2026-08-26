import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:enterprise_auth_mobile/core/secure_storage_service.dart';

class OrderCompletionPdfGenerator {
  static Future<void> generateAndPrint({
    required DateTime targetDate,
    required List<Map<String, dynamic>> orderDetails,
    bool isSummary = false,
  }) async {
    final pdf = pw.Document();
    final dateStr = DateFormat('EEE, d MMM yyyy').format(targetDate);
    final printTime = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    final username = await SecureStorageService().getUsername() ?? 'Unknown';

    // Group the details by SO Number (for detailed mode)
    final Map<String, List<Map<String, dynamic>>> groupedBySO = {};
    for (final detail in orderDetails) {
      final so = detail['soNumber'] as String? ?? 'UNKNOWN';
      groupedBySO.putIfAbsent(so, () => []).add(detail);
    }
    final sortedSOs = groupedBySO.keys.toList()..sort();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          final List<pw.Widget> elements = [
            _buildHeader(dateStr, printTime, username, isSummary: isSummary),
            pw.SizedBox(height: 20),
          ];

          if (isSummary) {
            // ── SUMMARY: single table grouped by product ──
            if (orderDetails.isEmpty) {
              elements.add(
                pw.Center(
                  child: pw.Text('No sales orders found for this date.',
                      style: pw.TextStyle(fontSize: 14)),
                ),
              );
            } else {
              elements.add(_buildSummaryTable(orderDetails));
            }
          } else {
            // ── DETAILED: per-SO breakdown ──
            if (sortedSOs.isEmpty) {
              elements.add(
                pw.Center(
                  child: pw.Text('No sales orders found for this date.',
                      style: pw.TextStyle(fontSize: 14)),
                ),
              );
            } else {
              for (final so in sortedSOs) {
                final items = groupedBySO[so]!;
                final first = items.first;

                elements.add(_buildSOHeader(so, first));
                elements.add(pw.SizedBox(height: 10));
                elements.add(_buildDetailTable(items));
                elements.add(pw.SizedBox(height: 25));
              }
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
      name:
          'Order_Completion_${isSummary ? 'Summary' : 'Detailed'}_${DateFormat('yyyyMMdd').format(targetDate)}.pdf',
    );
  }

  // ──────────────────────────────────────────
  // Page header
  // ──────────────────────────────────────────
  static pw.Widget _buildHeader(String date, String time, String username,
      {bool isSummary = false}) {
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
                  'ORDER COMPLETION REPORT',
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
        pw.SizedBox(height: 10),
        pw.Text(
          'Delivery Date: $date',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────
  // SO sub-header (detailed mode only)
  // ──────────────────────────────────────────
  static pw.Widget _buildSOHeader(
      String soNumber, Map<String, dynamic> firstItem) {
    final customer =
        firstItem['customerName'] as String? ?? 'Unknown Customer';
    final status = firstItem['headerStatusLabel'] as String? ?? 'OPEN';

    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey200,
        border: const pw.Border(
          left: pw.BorderSide(color: PdfColors.black, width: 3),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('SO: $soNumber',
              style:
                  pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
          pw.Text('Customer: $customer',
              style:
                  pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
          pw.Text(
            'Status: $status',
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 12,
              color: status.toUpperCase() == 'CLOSED'
                  ? PdfColors.black
                  : PdfColors.grey700,
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────
  // Detailed table (per SO, all columns)
  // ──────────────────────────────────────────
  static pw.Widget _buildDetailTable(List<Map<String, dynamic>> items) {
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

      final rawLocation = item['location'] as String?;
      String location = 'N/A';
      if (rawLocation != null && rawLocation.trim().isNotEmpty && rawLocation.toUpperCase() != 'NULL') {
        location = rawLocation;
      }

      String expiry = 'N/A';
      final expiryDateStr = item['expiryDate'] as String?;
      if (expiryDateStr != null && expiryDateStr.isNotEmpty) {
        final parsed = DateTime.tryParse(expiryDateStr);
        if (parsed != null) {
          expiry = DateFormat('dd MMM yyyy').format(parsed);
        }
      }

      final orderedQty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
      final scannedQty = (item['reconciledProduced'] as num?)?.toDouble() ?? 0.0;
      final unit = item['unit'] as String? ?? '';

      final headerStatus = item['headerStatusLabel'] as String? ?? '';
      final isClosed = headerStatus.toUpperCase() == 'CLOSED';
      final isPreparedNum = item['is_prepared'];
      final isPreparedLine =
          isPreparedNum == 1 || isPreparedNum == '1' || isPreparedNum == true;
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
        color: PdfColors.black,
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
      headerDecoration: const pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 1)),
      ),
      cellHeight: 20,
      cellStyle: const pw.TextStyle(fontSize: 7),
      columnWidths: {
        0: const pw.FixedColumnWidth(40),
        1: const pw.FlexColumnWidth(3),
        2: const pw.FixedColumnWidth(45),
        3: const pw.FixedColumnWidth(40),
        4: const pw.FixedColumnWidth(45),
        5: const pw.FixedColumnWidth(55),
        6: const pw.FixedColumnWidth(55),
        7: const pw.FixedColumnWidth(40),
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
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey50),
    );
  }

  // ──────────────────────────────────────────
  // Summary table (grouped by product)
  // ──────────────────────────────────────────
  static pw.Widget _buildSummaryTable(List<Map<String, dynamic>> items) {
    // Group by itemCode and aggregate quantities
    final Map<String, Map<String, dynamic>> byProduct = {};

    for (final item in items) {
      final code = item['itemCode'] as String? ?? '';
      final desc = item['description'] as String? ?? '';
      final unit = item['unit'] as String? ?? '';
      final orderedQty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
      final scannedQty = (item['reconciledProduced'] as num?)?.toDouble() ?? 0.0;

      if (!byProduct.containsKey(code)) {
        byProduct[code] = {
          'code': code,
          'desc': desc,
          'unit': unit,
          'orderedQty': 0.0,
          'scannedQty': 0.0,
        };
      }
      byProduct[code]!['orderedQty'] =
          (byProduct[code]!['orderedQty'] as double) + orderedQty;
      byProduct[code]!['scannedQty'] =
          (byProduct[code]!['scannedQty'] as double) + scannedQty;
    }

    final sortedCodes = byProduct.keys.toList()..sort();
    final List<List<dynamic>> tableData = sortedCodes.map((code) {
      final p = byProduct[code]!;
      final unit = p['unit'] as String;
      final ordered = (p['orderedQty'] as double).toStringAsFixed(2);
      final scanned = (p['scannedQty'] as double).toStringAsFixed(2);
      return [
        code,
        p['desc'],
        '$ordered $unit',
        '$scanned $unit',
      ];
    }).toList();

    return pw.TableHelper.fromTextArray(
      headers: ['Code', 'Description', 'Ordered Qty', 'Scanned Qty'],
      data: tableData,
      border: pw.TableBorder.all(color: PdfColors.grey300),
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.black,
        fontSize: 8,
      ),
      headerAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
      },
      headerDecoration: const pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 1)),
      ),
      cellHeight: 20,
      cellStyle: const pw.TextStyle(fontSize: 8),
      columnWidths: {
        0: const pw.FixedColumnWidth(55),
        1: const pw.FlexColumnWidth(3),
        2: const pw.FixedColumnWidth(80),
        3: const pw.FixedColumnWidth(80),
      },
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
      },
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey50),
    );
  }
}
