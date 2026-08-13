import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../../../../core/widgets/industrial_module_layout.dart';

class PdfPreviewScreen extends StatelessWidget {
  final String title;
  final Uint8List pdfBytes;

  const PdfPreviewScreen({
    super.key,
    required this.title,
    required this.pdfBytes,
  });

  @override
  Widget build(BuildContext context) {
    return IndustrialModuleLayout(
      title: title,
      body: PdfPreview(
        build: (format) => pdfBytes,
        canChangeOrientation: false,
        canChangePageFormat: false,
        allowPrinting: true,
        allowSharing: false,
        canDebug: false,
        pdfFileName: '${title.replaceAll(' ', '_')}.pdf',
      ),
    );
  }
}
