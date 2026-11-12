import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../../../../core/widgets/industrial_module_layout.dart';
import '../../../../../core/services/printer_service.dart';

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
      extraActions: [
        IconButton(
          icon: const Icon(Icons.print_rounded),
          tooltip: 'Print via Bluetooth Printer',
          onPressed: () async {
            try {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Sending to Bluetooth printer...'),
                  duration: Duration(seconds: 1),
                ),
              );
              await PrinterService.instance.printPdfViaBluetooth(
                pdfBytes: pdfBytes,
                documentName: '${title.replaceAll(' ', '_')}.pdf',
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Document printed successfully on Sewoo LK-P43II'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Print failed: $e'), backgroundColor: Colors.red),
                );
              }
            }
          },
        ),
      ],
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
