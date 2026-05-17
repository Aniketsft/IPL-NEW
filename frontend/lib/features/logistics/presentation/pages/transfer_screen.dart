import 'package:flutter/material.dart';
import 'package:enterprise_auth_mobile/core/widgets/industrial_module_layout.dart';

class TransferScreen extends StatefulWidget {
  const TransferScreen({super.key});

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  final _productController = TextEditingController();
  final _quantityController = TextEditingController();
  String _sourceLocation = 'Warehouse A-1';
  String _destLocation = 'Production Line 4';

  final List<String> _locations = [
    'Warehouse A-1',
    'Warehouse A-2',
    'Production Line 4',
    'Cold Storage',
    'Sector B-4',
  ];

  @override
  void dispose() {
    _productController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    return IndustrialModuleLayout(
      title: 'INTERNAL TRANSFER',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLocationSelection(theme, orange),
            const SizedBox(height: 24),
            _buildProductScanSection(theme, orange),
            const SizedBox(height: 32),
            _buildTransferSummary(theme),
            const SizedBox(height: 32),
            _buildActionButton(theme, orange),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationSelection(ThemeData theme, Color orange) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
        boxShadow: isDark ? null : [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildDropdown(
            'Source Location',
            _sourceLocation,
            (val) => setState(() => _sourceLocation = val!),
            theme,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Icon(
              Icons.arrow_downward,
              color: orange,
              size: 20,
            ),
          ),
          _buildDropdown(
            'Destination Location',
            _destLocation,
            (val) => setState(() => _destLocation = val!),
            theme,
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown(
    String label,
    String value,
    ValueChanged<String?> onChanged,
    ThemeData theme,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 11),
        ),
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            dropdownColor: theme.cardColor,
            elevation: 8,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            items: _locations
                .map(
                  (e) => DropdownMenuItem(
                    value: e,
                    child: Text(e, style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                  ),
                )
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildProductScanSection(ThemeData theme, Color orange) {
    final isDark = theme.brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SCAN PRODUCT',
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 12),
        _buildTextField(
          'Search or Scan SKU',
          Icons.qr_code_scanner,
          _productController,
          theme,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                'Quantity',
                Icons.numbers,
                _quantityController,
                theme,
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: isDark ? 0 : 2,
              ),
              child: const Text('ADD', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTextField(
    String hint,
    IconData icon,
    TextEditingController controller,
    ThemeData theme,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: TextField(
        controller: controller,
        style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 14),
          prefixIcon: Icon(icon, color: isDark ? Colors.white38 : Colors.black38, size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
        ),
      ),
    );
  }

  Widget _buildTransferSummary(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: Column(
        children: [
          Text('Items to Transfer: 0', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
          const SizedBox(height: 8),
          Text(
            'TOTAL QUANTITY: 0.00',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(ThemeData theme, Color orange) {
    final isDark = theme.brightness == Brightness.dark;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {},
        style: ElevatedButton.styleFrom(
          backgroundColor: isDark ? theme.colorScheme.surfaceContainerHighest : theme.colorScheme.surfaceContainerLow,
          foregroundColor: isDark ? Colors.white : Colors.black87,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.08)),
          ),
        ),
        child: const Text(
          'SUBMIT TRANSFER',
          style: TextStyle(letterSpacing: 1.2, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
