import 'package:flutter/material.dart';
import 'package:enterprise_auth_mobile/core/widgets/industrial_module_layout.dart';

class PickingScreen extends StatelessWidget {
  const PickingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const IndustrialModuleLayout(
      title: 'PICKING LIST',
      body: Center(
        child: Text(
          'Module content removed.',
          style: TextStyle(color: Colors.grey),
        ),
      ),
    );
  }
}
