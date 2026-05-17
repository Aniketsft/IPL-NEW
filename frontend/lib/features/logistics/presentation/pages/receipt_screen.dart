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

  @override
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

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
                        builder: (context, child) => Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: ColorScheme.fromSeed(
                              seedColor: orange,
                              primary: orange,
                              onPrimary: Colors.white,
                              surface: theme.cardColor,
                              onSurface: isDark ? Colors.white : Colors.black87,
                              brightness: theme.brightness,
                            ),
                          ),
                          child: child!,
                        ),
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
                        backgroundColor: theme.scaffoldBackgroundColor,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        builder: (context) => Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: ListView(
                            shrinkWrap: true,
                            children: [
                              ListTile(
                                title: Text('All Suppliers', style: TextStyle(color: orange, fontWeight: FontWeight.bold)),
                                onTap: () => Navigator.pop(context, null),
                              ),
                              ..._suppliers.map((s) => ListTile(
                                title: Text(s, style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                                onTap: () => Navigator.pop(context, s),
                              )),
                            ],
                          ),
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
            child: Center(
              child: Text(
                'Receipt backend is under construction (Sales Orders removed).',
                style: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
              ),
            ),
          ),
        ],
      ),
    );
  }

}
