import 'package:flutter/material.dart';
import '../../../../core/widgets/industrial_module_layout.dart';

class InvoiceScreen extends StatelessWidget {
  const InvoiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const IndustrialModuleLayout(
      title: 'INVOICE PROCESSING',
      body: Center(
        child: Text('Invoice Module Placeholder'),
      ),
    );
  }
}

class CreditNoteScreen extends StatelessWidget {
  const CreditNoteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const IndustrialModuleLayout(
      title: 'CREDIT NOTE',
      body: Center(
        child: Text('Credit Note Module Placeholder'),
      ),
    );
  }
}

class CustomerReturnScreen extends StatelessWidget {
  const CustomerReturnScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const IndustrialModuleLayout(
      title: 'CUSTOMER RETURN',
      body: Center(
        child: Text('Customer Return Module Placeholder'),
      ),
    );
  }
}
