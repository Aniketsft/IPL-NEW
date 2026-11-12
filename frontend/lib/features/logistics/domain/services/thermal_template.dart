import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Logged-in session details printed on the thermal documents
/// (SALESMAN / STORE fields). Kept in sync by `AuthBloc.onChange`.
class ThermalSession {
  static String username = '';
  static String siteCode = '';
}

/// Static company details printed in the document headers.
///
/// VAT / BRN are intentionally configurable: set them once at start-up
/// (e.g. `ThermalCompany.vatNo = '...'`) so the printed documents carry the
/// legally registered numbers.
class ThermalCompany {
  static String name = 'INNODIS LTD';
  static String vatNo = '';
  static String brn = '';
  static const String division = 'FROZEN FOODS';
  static const List<String> addressLines = [
    'MFD, Zone 5,Mer Rouge,',
    'Port - Louis, Mauritius',
    'Customer Service: 2065880',
    'Fax: (230) 466 1787',
  ];
}

/// Fixed-width (68 column) text document renderer targeting the
/// 4.5" (104 mm / 832 dot) Sewoo LK-P43II roll.
///
/// The MS templates are laid out on a 68 character grid, so every document is
/// composed as monospaced lines and rendered with Courier, which guarantees
/// that columns line up exactly like the templates.
class ThermalDoc {
  static const int cols = 68;

  /// 104 mm printable roll width in PDF points (832 dots @ 203 DPI).
  static const double pageWidth = 104 * PdfPageFormat.mm;
  static const double _margin = 3;
  static const double _fontSize = 7.0;
  static const double _charWidth = _fontSize * 0.6; // Courier advance width

  static final NumberFormat _money = NumberFormat('#,##0.00', 'en_US');

  final List<_ThermalLine> _lines = [];

  // ── Formatting helpers ──────────────────────────────────────────────────

  static String money(num v) => _money.format(v);

  static String qty(double v) =>
      v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);

  static String clean(String? text) {
    if (text == null || text.isEmpty) return '';
    var t = text
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('…', '...')
        .replaceAll('•', '-')
        .replaceAll('·', '-')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[ÉÈÊË]'), 'E')
        .replaceAll(RegExp(r'[àâäáã]'), 'a')
        .replaceAll(RegExp(r'[ÀÂÄÁÃ]'), 'A')
        .replaceAll(RegExp(r'[îïí]'), 'i')
        .replaceAll(RegExp(r'[ôöóõ]'), 'o')
        .replaceAll(RegExp(r'[ùûüú]'), 'u')
        .replaceAll('ç', 'c')
        .replaceAll('\t', ' ');
    return t.replaceAll(RegExp(r'[^\x20-\x7E]'), '');
  }

  /// Left-aligns [s] in [w] columns (truncates when longer).
  static String l(String s, int w) {
    final c = clean(s);
    return c.length >= w ? c.substring(0, w) : c.padRight(w);
  }

  /// Right-aligns [s] in [w] columns (keeps the tail when longer).
  static String r(String s, int w) {
    final c = clean(s);
    return c.length >= w ? c.substring(c.length - w) : c.padLeft(w);
  }

  static String centered(String s) {
    final c = clean(s);
    if (c.length >= cols) return c.substring(0, cols);
    return (' ' * ((cols - c.length) ~/ 2)) + c;
  }

  static List<String> wrap(String s, int width) {
    final c = clean(s).trim();
    if (c.isEmpty) return [''];
    final out = <String>[];
    var current = '';
    for (final word in c.split(RegExp(r'\s+'))) {
      var w = word;
      while (w.length > width) {
        if (current.isNotEmpty) {
          out.add(current);
          current = '';
        }
        out.add(w.substring(0, width));
        w = w.substring(width);
      }
      if (current.isEmpty) {
        current = w;
      } else if (current.length + 1 + w.length <= width) {
        current = '$current $w';
      } else {
        out.add(current);
        current = w;
      }
    }
    if (current.isNotEmpty) out.add(current);
    return out;
  }

  // ── Content builders ────────────────────────────────────────────────────

  void line(String s, {bool bold = false}) {
    final c = clean(s);
    _lines.add(_ThermalLine(c.length > cols ? c.substring(0, cols) : c, bold));
  }

  void blank([int n = 1]) {
    for (var i = 0; i < n; i++) {
      _lines.add(const _ThermalLine('', false));
    }
  }

  void center(String s, {bool bold = false}) => line(centered(s), bold: bold);

  void rule([String ch = '-']) => line(' ${ch * (cols - 2)}');

  /// Wrapped paragraph with a hanging [indent].
  void paragraph(String s, {int indent = 1, bool bold = false}) {
    for (final w in wrap(s, cols - indent)) {
      line('${' ' * indent}$w', bold: bold);
    }
  }

  /// ` Label               :value` metadata row used by every template.
  void meta(String label, String value, {int labelWidth = 20, bool bold = false}) {
    final prefix = ' ${l(label, labelWidth)}:';
    final wrapped = wrap(value, cols - prefix.length);
    line('$prefix${wrapped.first}', bold: bold);
    for (final extra in wrapped.skip(1)) {
      line('${' ' * prefix.length}$extra', bold: bold);
    }
  }

  /// Right hand block row: label at fixed indent, value right aligned.
  void total(String label, String value,
      {int indent = 17, int labelWidth = 21, bool bold = false}) {
    line(
      '${' ' * indent}${l(label, labelWidth)}${r(value, cols - indent - labelWidth)}',
      bold: bold,
    );
  }

  /// Label on the left, amount right aligned at the margin.
  void amountRow(String label, String value, {bool bold = false}) {
    line(' ${l(label, cols - 2 - value.length - 1)} ${clean(value)}', bold: bold);
  }

  /// Standard company header shared by invoice / credit note / receipt docs.
  void companyHeader({bool withAddress = true}) {
    center(ThermalCompany.name, bold: true);
    blank();
    line('    Vat Registratrion No      : ${ThermalCompany.vatNo}');
    line('    Business Registration No. : ${ThermalCompany.brn}');
    blank();
    if (withAddress) {
      center(ThermalCompany.division, bold: true);
      for (final a in ThermalCompany.addressLines) {
        center(a);
      }
      blank();
    }
  }

  static String printStamp([DateTime? dt]) =>
      DateFormat('dd/MM/yyyy HH:mm:ss').format(dt ?? DateTime.now());

  // ── Rendering ───────────────────────────────────────────────────────────

  /// Exposes the 68-column lines for direct ESC/POS text printing.
  List<({String text, bool bold})> toPrintLines() =>
      _lines.map((l) => (text: l.text, bold: l.bold)).toList();

  Future<Uint8List> build() async {
    final regular = pw.Font.courier();
    final bold = pw.Font.courierBold();
    final pdf = pw.Document();

    final regularStyle = pw.TextStyle(font: regular, fontSize: _fontSize, height: 1.0);
    final boldStyle = pw.TextStyle(font: bold, fontSize: _fontSize, height: 1.0);

    pdf.addPage(
      pw.Page(
        pageTheme: pw.PageTheme(
          pageFormat: const PdfPageFormat(
            pageWidth,
            double.infinity,
            marginLeft: _margin,
            marginRight: _margin,
            marginTop: 6,
            marginBottom: 14,
          ),
          buildBackground: (_) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Container(color: PdfColors.white),
          ),
        ),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: _lines.map((ln) {
              final trimmed = ln.text.trimLeft();
              final lead = ln.text.length - trimmed.length;
              final style = ln.bold ? boldStyle : regularStyle;
              if (trimmed.isEmpty) {
                return pw.SizedBox(height: _fontSize * 1.25);
              }
              return pw.Padding(
                padding: pw.EdgeInsets.only(left: lead * _charWidth),
                child: pw.Text(trimmed, style: style, softWrap: false),
              );
            }).toList(),
          );
        },
      ),
    );

    return pdf.save();
  }
}

class _ThermalLine {
  final String text;
  final bool bold;
  const _ThermalLine(this.text, this.bold);
}

/// Shared fallback readers for loosely typed customer maps.
String thermalFirst(Map<String, dynamic> map, List<String> keys, [String fallback = '']) {
  for (final k in keys) {
    final v = map[k];
    if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
  }
  return fallback;
}

/// Adds the standard 68-col item header used by the invoice / credit note.
void thermalItemHeader(ThermalDoc d) {
  d.rule();
  d.line(' ${ThermalDoc.l('Description', 19)}${ThermalDoc.r('Qty', 10)}'
      '${ThermalDoc.r('U.Price', 9)}${ThermalDoc.r('Discount', 9)}'
      '${ThermalDoc.r('Vat', 8)}${ThermalDoc.r('Total(Rs)', 12)}');
  d.rule();
}

/// Prints one item row: `ProdCode:` line, then description + figures line.
void thermalItemRow(
  ThermalDoc d, {
  required String code,
  required String description,
  required double qty,
  required String uom,
  required double unitPrice,
  required double discount,
  required double vat,
  required double total,
}) {
  d.line(' ProdCode: ${ThermalDoc.clean(code)}');
  final descLines = ThermalDoc.wrap(description, 19);
  final qtyText = '${ThermalDoc.qty(qty)}(${ThermalDoc.clean(uom)})';
  d.line(' ${ThermalDoc.l(descLines.first, 19)}${ThermalDoc.r(qtyText, 10)}'
      '${ThermalDoc.r(ThermalDoc.money(unitPrice), 9)}'
      '${ThermalDoc.r(ThermalDoc.money(discount), 9)}'
      '${ThermalDoc.r(ThermalDoc.money(vat), 8)}'
      '${ThermalDoc.r(ThermalDoc.money(total), 12)}');
  for (final extra in descLines.skip(1)) {
    d.line(' $extra');
  }
}

/// Legal terms block printed on invoices and credit notes.
void thermalTerms(ThermalDoc d) {
  d.line(' Goods delivered and accepted cannot be returned.');
  d.line(' For Credit Sales:');
  d.line(' Invoices should be settled according to terms of credit.');
  d.line(' Interest of 1% above commercial bank rate will be claimed on all');
  d.line(' overdue accounts.');
  d.line(' In case of recovery through an attorney the commission due to');
  d.line(' the attorney will be payable by the customer.');
}
