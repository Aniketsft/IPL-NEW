import 'package:flutter/material.dart';
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
          _buildFilters(),
          _buildStatusToggle(),
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

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2C2C2E), width: 1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  'Search GRN or PO',
                  Icons.search,
                  _searchController,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTextField(
                  'Date',
                  Icons.calendar_today,
                  _dateController,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildSupplierDropdown(),
        ],
      ),
    );
  }

  Widget _buildSupplierDropdown() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF2C2C2E)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedSupplier,
          isExpanded: true,
          hint: const Text(
            'Select Supplier...',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
          dropdownColor: const Color(0xFF1E1E1E),
          items: [
            const DropdownMenuItem<String>(
              value: null,
              child: Text(
                'All Suppliers',
                style: TextStyle(color: Colors.white),
              ),
            ),
            ..._suppliers.map(
              (s) => DropdownMenuItem(
                value: s,
                child: Text(s, style: const TextStyle(color: Colors.white)),
              ),
            ),
          ],
          onChanged: (val) => setState(() => _selectedSupplier = val),
        ),
      ),
    );
  }

  Widget _buildStatusToggle() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _showVerified ? 'VERIFIED RECEIPTS' : 'PENDING RECEIPTS',
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          Switch(
            value: _showVerified,
            onChanged: (val) => setState(() => _showVerified = val),
            activeColor: const Color(0xFFFF9800),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    String hint,
    IconData icon,
    TextEditingController controller,
  ) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF2C2C2E)),
      ),
      child: TextField(
        controller: controller,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
          prefixIcon: Icon(icon, color: Colors.white38, size: 18),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}
