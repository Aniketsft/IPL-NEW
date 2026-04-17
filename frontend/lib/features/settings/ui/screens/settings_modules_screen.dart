import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:enterprise_auth_mobile/core/widgets/industrial_module_layout.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/delivery_repository.dart';
import 'package:enterprise_auth_mobile/features/settings/data/models/app_settings.dart';

class SettingsModulesScreen extends StatefulWidget {
  const SettingsModulesScreen({super.key});

  @override
  State<SettingsModulesScreen> createState() => _SettingsModulesScreenState();
}

class _SettingsModulesScreenState extends State<SettingsModulesScreen> {
  bool _isLoading = true;
  AppSettings? _settings;
  
  // Local controllers for immediate UI feedback
  final TextEditingController _lotController = TextEditingController();
  final TextEditingController _toleranceController = TextEditingController();
  
  List<Map<String, String>> _customersList = [];
  List<Map<String, String>> _salesRepsList = [];
  
  String? _selectedCustomer;
  String? _selectedSalesman;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final repository = context.read<DeliveryRepository>();
      
      // Load Lookups for the searchable pickers
      final customers = await repository.getCustomers();
      final reps = await repository.getSalesReps();
      
      // Load current settings from local storage/sync cache
      final settings = await repository.getAppSettings();
      
      setState(() {
        _customersList = customers.map((c) => {'code': c.code, 'name': c.name}).toList();
        _salesRepsList = reps.map((r) => {'code': r.code, 'name': r.name}).toList();
        _settings = settings;
        
        _lotController.text = _settings?.dailyLotNumber ?? '';
        _toleranceController.text = (_settings?.tolerancePercentage ?? 0.0).toString();
        _selectedCustomer = _settings?.excessDefaultCustomer;
        _selectedSalesman = _settings?.excessDefaultSalesman;
        
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  bool get _isLotLocked {
    if (_settings?.lastLotDate == null || _settings!.dailyLotNumber == null) return false;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return _settings!.lastLotDate == today;
  }

  Future<void> _saveSettings() async {
    if (_settings == null) return;
    
    final updated = _settings!.copyWith(
      dailyLotNumber: _lotController.text,
      lastLotDate: _isLotLocked ? _settings!.lastLotDate : DateFormat('yyyy-MM-dd').format(DateTime.now()),
      excessDefaultCustomer: _selectedCustomer,
      excessDefaultSalesman: _selectedSalesman,
      tolerancePercentage: double.tryParse(_toleranceController.text) ?? 0.0,
    );

    setState(() => _isLoading = true);
    try {
      final repository = context.read<DeliveryRepository>();
      await repository.updateAppSettings(updated);
      
      // Senior Developer Decision: Save locally first. Sync happens in background or next cycle.
      // This prevents UI block/lag and ensures immediate persistence on device.
      
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings saved locally. They will be synchronized with the server automatically.'),
            backgroundColor: Color(0xFF4CAF50),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF9800);
    const darkCard = Color(0xFF1E1E1E);
    const darkBorder = Color(0xFF2C2C2E);

    return IndustrialModuleLayout(
      title: 'LOGISTICS | SETTINGS',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: orange))
          : Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  child: Column(
                    children: [
                      // 1. LOT NUMBER MODULE
                      _buildModuleCard(
                        title: 'DAILY LOT NUMBER',
                        icon: Icons.tag,
                        accentColor: orange,
                        isLocked: _isLotLocked,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Only one lot number can be created per day and will default in production tracking.',
                              style: TextStyle(color: Colors.white38, fontSize: 11),
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: _lotController,
                              hint: 'Enter Lot Number...',
                              enabled: !_isLotLocked,
                              icon: Icons.edit_note,
                            ),
                            if (_isLotLocked) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.lock, color: orange, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    'LOCKED FOR TODAY: ${_settings?.lastLotDate}',
                                    style: const TextStyle(color: orange, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 2. EXCESS DEFAULT MODULE
                      _buildModuleCard(
                        title: 'EXCESS DEFAULTS',
                        icon: Icons.person_outline,
                        accentColor: Colors.blueAccent,
                        child: Column(
                          children: [
                            _buildLabel('Default Customer'),
                            _buildSearchPicker(
                              'Customer',
                              _selectedCustomer,
                              _customersList,
                              (val) => setState(() => _selectedCustomer = val),
                            ),
                            const SizedBox(height: 16),
                            _buildLabel('Default Salesman'),
                            _buildSearchPicker(
                              'Salesman',
                              _selectedSalesman,
                              _salesRepsList,
                              (val) => setState(() => _selectedSalesman = val),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 3. TOLERANCE MODULE
                      _buildModuleCard(
                        title: 'TOLERANCE PERCENTAGE',
                        icon: Icons.percent,
                        accentColor: Colors.greenAccent,
                        child: _buildTextField(
                          controller: _toleranceController,
                          hint: 'Enter %...',
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          icon: Icons.tune,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Bottom Bar
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: darkCard,
                      border: Border(top: BorderSide(color: darkBorder)),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saveSettings,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('SAVE & SYNC SETTINGS', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildModuleCard({
    required String title,
    required IconData icon,
    required Color accentColor,
    required Widget child,
    bool isLocked = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isLocked ? accentColor.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accentColor, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.2),
              ),
              const Spacer(),
              if (isLocked) const Icon(Icons.verified, color: Colors.greenAccent, size: 16),
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool enabled = true,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      style: TextStyle(color: enabled ? Colors.white : Colors.white38),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.2),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24),
        prefixIcon: Icon(icon, color: Colors.white24, size: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ),
    );
  }

  Widget _buildSearchPicker(
    String label,
    String? value,
    List<Map<String, String>> items,
    Function(String?) onSelected,
  ) {
    String? displayName;
    if (value != null && items.isNotEmpty) {
      try {
        displayName = items.firstWhere((it) => it['code'] == value)['name'];
      } catch (_) {
        displayName = value;
      }
    }

    return InkWell(
      onTap: () => _showSearchSheet(label, items, onSelected),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                displayName ?? 'Select $label...',
                style: TextStyle(color: displayName == null ? Colors.white24 : Colors.white, fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: Colors.white38, size: 20),
          ],
        ),
      ),
    );
  }

  void _showSearchSheet(String title, List<Map<String, String>> items, Function(String?) onSelected) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => _SearchPickerSheet(title: title, items: items, onSelected: onSelected),
    );
  }
}

class _SearchPickerSheet extends StatefulWidget {
  final String title;
  final List<Map<String, String>> items;
  final Function(String?) onSelected;

  const _SearchPickerSheet({required this.title, required this.items, required this.onSelected});

  @override
  State<_SearchPickerSheet> createState() => _SearchPickerSheetState();
}

class _SearchPickerSheetState extends State<_SearchPickerSheet> {
  late List<Map<String, String>> _filteredItems;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.items;
  }

  void _filter(String query) {
    setState(() {
      _filteredItems = widget.items.where((it) {
        final code = (it['code'] ?? '').toLowerCase();
        final name = (it['name'] ?? '').toLowerCase();
        return code.contains(query.toLowerCase()) || name.contains(query.toLowerCase());
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Text('Select ${widget.title}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            onChanged: _filter,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search...',
              hintStyle: const TextStyle(color: Colors.white24),
              prefixIcon: const Icon(Icons.search, color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF1E1E1E),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: _filteredItems.length,
              itemBuilder: (context, index) {
                final item = _filteredItems[index];
                return ListTile(
                  title: Text(item['name'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: Text(item['code'] ?? '', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  onTap: () {
                    widget.onSelected(item['code']);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
