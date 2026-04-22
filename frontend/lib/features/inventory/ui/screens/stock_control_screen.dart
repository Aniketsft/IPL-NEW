import 'package:flutter/material.dart';
import '../../../../core/widgets/industrial_module_layout.dart';

class StockControlScreen extends StatelessWidget {
  const StockControlScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const IndustrialModuleLayout(
      title: 'STOCK CONTROL',
      body: Center(
        child: Text(
          'Module content removed.',
          style: TextStyle(color: Colors.grey),
        ),
      ),
    );
  }
}
