import 'package:flutter/material.dart';
import 'package:enterprise_auth_mobile/core/widgets/industrial_module_layout.dart';

class PrinterSettingsScreen extends StatelessWidget {
  const PrinterSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const IndustrialModuleLayout(
      title: 'PRINTER SETTINGS',
      body: Center(
        child: Text(
          'Label Printer Configuration',
          style: TextStyle(
            color: Colors.white24,
            fontSize: 16,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}
