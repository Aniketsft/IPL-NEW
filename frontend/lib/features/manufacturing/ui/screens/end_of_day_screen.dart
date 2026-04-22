import 'package:flutter/material.dart';
import '../../../../core/widgets/industrial_module_layout.dart';

class EndOfDayScreen extends StatelessWidget {
  const EndOfDayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const IndustrialModuleLayout(
      title: 'END OF DAY',
      body: Center(
        child: Text(
          'Module content removed.',
          style: TextStyle(color: Colors.grey),
        ),
      ),
    );
  }
}
