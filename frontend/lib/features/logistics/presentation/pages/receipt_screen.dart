import 'package:flutter/material.dart';
import 'package:enterprise_auth_mobile/core/widgets/standard_filter.dart';
import 'package:enterprise_auth_mobile/core/widgets/filter_input_widgets.dart';
import 'package:enterprise_auth_mobile/core/widgets/industrial_module_layout.dart';

class ReceiptScreen extends StatefulWidget {
  const ReceiptScreen({super.key});

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  final _searchController = TextEditingController();
  final _dateController = TextEditingController();
  String? _selectedSupplier;
  bool _showVerified = false;

  final List<String> _suppliers = [
    'Global Components Ltd',
    'TechParts Inc',
    'Precision Systems',
  ];

  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IndustrialModuleLayout(
      title: 'GOODS RECEIPT',
      body: Column(
        children: [
          StandardFilter(
            searchController: _searchController,
            searchHint: 'Search GRN or PO',
            onApply: () => setState(() {}),
            onReset: () {
              setState(() {
                _searchController.clear();
                _dateController.clear();
                _selectedSupplier = null;
                _showVerified = false;
              });
            },
            filterBuilder: (context, setModalState) {
              return Column(
                children: [
                  FilterDatePicker(
                    label: 'Date',
                    value: _dateController.text.isNotEmpty ? DateTime.tryParse(_dateController.text) : null,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2101),
                      );
                      if (picked != null) {
                        setState(() => _dateController.text = picked.toString().split(' ')[0]);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  FilterPickerTile(
                    label: 'Supplier',
                    value: _selectedSupplier,
                    onTap: () async {
                      final result = await showModalBottomSheet<String>(
                        context: context,
                        backgroundColor: const Color(0xFF1E1E1E),
                        builder: (context) => ListView(
                          shrinkWrap: true,
                          children: [
                            ListTile(
                              title: const Text('All Suppliers', style: TextStyle(color: Colors.orange)),
                              onTap: () => Navigator.pop(context, null),
                            ),
                            ..._suppliers.map((s) => ListTile(
                              title: Text(s, style: const TextStyle(color: Colors.white)),
                              onTap: () => Navigator.pop(context, s),
                            )),
                          ],
                        ),
                      );
                      setState(() => _selectedSupplier = result);
                    },
                  ),
                  const SizedBox(height: 16),
                  FilterSegmentedToggle(
                    label: 'Status',
                    value: _showVerified ? 'verified' : 'pending',
                    options: const ['pending', 'verified'],
                    onChanged: (val) => setState(() => _showVerified = val == 'verified'),
                  ),
                ],
              );
            },
          ),
          Expanded(
            child: const Center(
              child: Text(
                'Receipt backend is under construction (Sales Orders removed).',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          ),
        ],
      ),
    );
  }

}
