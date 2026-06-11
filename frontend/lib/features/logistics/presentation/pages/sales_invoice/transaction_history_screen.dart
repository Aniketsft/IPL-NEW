import 'package:flutter/material.dart';
import '../../../../../core/widgets/industrial_module_layout.dart';

class TransactionHistoryScreen extends StatelessWidget {
  final String transactionType;

  const TransactionHistoryScreen({
    super.key,
    required this.transactionType,
  });

  @override
  Widget build(BuildContext context) {
    return IndustrialModuleLayout(
      title: '$transactionType History',
      body: const Center(
        child: Text('History screen blank for now'),
      ),
    );
  }
}
