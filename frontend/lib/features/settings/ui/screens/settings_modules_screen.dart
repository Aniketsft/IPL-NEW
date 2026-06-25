import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:enterprise_auth_mobile/core/widgets/industrial_module_layout.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/delivery_repository.dart';
import 'package:enterprise_auth_mobile/features/settings/data/models/app_settings.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_state.dart';

class SettingsModulesScreen extends StatefulWidget {
  const SettingsModulesScreen({super.key});

  @override
  State<SettingsModulesScreen> createState() => _SettingsModulesScreenState();
}

class _SettingsModulesScreenState extends State<SettingsModulesScreen> {
  bool _isLoading = true;
  AppSettings? _settings;
  
  // Local controllers for immediate UI feedback
  final TextEditingController _toleranceController = TextEditingController();
  
  List<Map<String, String>> _customersList = [];
  List<Map<String, String>> _salesRepsList = [];
  
  String? _selectedCustomer;
  String? _selectedSalesman;
  String? _selectedSchema;

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
        
        _toleranceController.text = (_settings?.tolerancePercentage ?? 0.0).toString();
        _selectedCustomer = _settings?.excessDefaultCustomer;
        _selectedSalesman = _settings?.excessDefaultSalesman;
        _selectedSchema = _settings?.selectedSchema;
        
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  bool get _canUpdate {
    final authState = context.read<AuthBloc>().state;
    if (authState is Authenticated) {
      return authState.permissions.contains('settings.general.update') ||
             authState.permissions.contains('settings.general.create');
    }
    return false;
  }

  Future<void> _saveSettings() async {
    if (_settings == null) return;
    
    final updated = _settings!.copyWith(
      dailyLotNumber: _settings!.dailyLotNumber,
      lastLotDate: _settings!.lastLotDate,
      excessDefaultCustomer: _selectedCustomer,
      excessDefaultSalesman: _selectedSalesman,
      tolerancePercentage: double.tryParse(_toleranceController.text) ?? 0.0,
      selectedSchema: _selectedSchema,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    return IndustrialModuleLayout(
      title: 'LOGISTICS | SETTINGS',
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: orange))
          : Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  child: Column(
                    children: [
                      // 1. EXCESS DEFAULT MODULE
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
                              _canUpdate ? (val) => setState(() => _selectedCustomer = val) : (val) {},
                            ),
                            const SizedBox(height: 16),
                            _buildLabel('Default Salesman'),
                            _buildSearchPicker(
                              'Salesman',
                              _selectedSalesman,
                              _salesRepsList,
                              _canUpdate ? (val) => setState(() => _selectedSalesman = val) : (val) {},
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
                          enabled: _canUpdate,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          icon: Icons.tune,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 4. SAGE X3 SCHEMA
                      _buildModuleCard(
                        title: 'SAGE X3 SCHEMA',
                        icon: Icons.schema,
                        accentColor: Colors.purpleAccent,
                        child: Theme(
                          data: theme.copyWith(
                            canvasColor: isDark ? theme.cardColor : Colors.white,
                          ),
                          child: DropdownButtonFormField<String>(
                            value: _selectedSchema ?? 'INLDRYRUN',
                            dropdownColor: isDark ? theme.cardColor : Colors.white,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontSize: 14,
                            ),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: isDark ? Colors.black.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.05),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'INLDRYRUN',
                                child: Text('SC (INLDRYRUN)'),
                              ),
                              DropdownMenuItem(
                                value: 'INLPROD',
                                child: Text('X3 (INLPROD)'),
                              ),
                            ],
                            onChanged: _canUpdate ? (value) {
                              if (value != null) {
                                setState(() {
                                  _selectedSchema = value;
                                });
                              }
                            } : null,
                          ),
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
                      color: theme.cardColor,
                      border: Border(top: BorderSide(color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05))),
                      boxShadow: isDark ? null : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _canUpdate ? _saveSettings : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: orange,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: isDark ? Colors.white12 : Colors.black12,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isLocked ? accentColor.withValues(alpha: 0.3) : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05))),
        boxShadow: isDark ? null : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
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
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87, 
                  fontWeight: FontWeight.bold, 
                  fontSize: 13, 
                  letterSpacing: 1.2,
                ),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      style: TextStyle(color: enabled ? (isDark ? Colors.white : Colors.black87) : (isDark ? Colors.white38 : Colors.black26)),
      decoration: InputDecoration(
        filled: true,
        fillColor: isDark ? Colors.black.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.05),
        hintText: hint,
        hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.black26),
        prefixIcon: Icon(icon, color: isDark ? Colors.white24 : Colors.black26, size: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: isDark ? BorderSide.none : BorderSide(color: Colors.black.withValues(alpha: 0.05))),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _buildLabel(String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text, 
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildSearchPicker(
    String label,
    String? value,
    List<Map<String, String>> items,
    Function(String?) onSelected,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
          color: isDark ? Colors.black.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: isDark ? null : Border.all(color: Colors.black.withValues(alpha: 0.05)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                displayName ?? 'Select $label...',
                style: TextStyle(color: displayName == null ? (isDark ? Colors.white24 : Colors.black26) : (isDark ? Colors.white : Colors.black87), fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.arrow_drop_down, color: isDark ? Colors.white38 : Colors.black38, size: 20),
          ],
        ),
      ),
    );
  }

  void _showSearchSheet(String title, List<Map<String, String>> items, Function(String?) onSelected) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.scaffoldBackgroundColor,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40, 
            height: 4, 
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12, 
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Select ${widget.title}', 
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87, 
              fontSize: 18, 
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            onChanged: _filter,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: 'Search...',
              hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.black26),
              prefixIcon: Icon(Icons.search, color: isDark ? Colors.white38 : Colors.black38),
              filled: true,
              fillColor: theme.cardColor,
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
                  title: Text(
                    item['name'] ?? '', 
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
                  ),
                  subtitle: Text(
                    item['code'] ?? '', 
                    style: TextStyle(color: isDark ? Colors.white38 : Colors.black45, fontSize: 12),
                  ),
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
