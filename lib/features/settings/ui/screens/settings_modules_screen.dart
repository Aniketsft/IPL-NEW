import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:enterprise_auth_mobile/core/theme_cubit.dart';
import 'package:enterprise_auth_mobile/core/widgets/industrial_module_layout.dart';

import 'package:enterprise_auth_mobile/features/settings/data/models/app_settings.dart';
import 'package:enterprise_auth_mobile/features/settings/data/repositories/settings_repository_mock.dart';
import '../../../../features/administration/ui/screens/user_management_screen.dart';

class SettingsModulesScreen extends StatefulWidget {
  const SettingsModulesScreen({super.key});

  @override
  State<SettingsModulesScreen> createState() => _SettingsModulesScreenState();
}

class _SettingsModulesScreenState extends State<SettingsModulesScreen> {
  final _repository = SettingsRepositoryMock();
  bool _isLoading = true;

  AppSettings? _settings;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _repository.getSettingsConfig();
    setState(() {
      _settings = settings;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    if (_settings == null) return;

    // Show a saving indicator (Optional)
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Saving Configuration...')));

    await _repository.updateSettings(_settings!);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings Saved Successfully 🌱')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final cardColor = const Color(0xFF252528);
    final fieldColor = const Color(0xFF38383B);
    final sectionTitleColor = Colors.white;
    final labelColor = Colors.white70;

    return IndustrialModuleLayout(
      title: 'Settings',
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF9800)),
            )
          : Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionCard(
                        color: cardColor,
                        title: 'Company & Site',
                        titleColor: sectionTitleColor,
                        children: [
                          _buildLabel('Company', labelColor),
                          _buildDropdown(
                            value: _settings!.selectedCompanyId,
                            items: _settings!.availableCompanies
                                .map((c) => c.id)
                                .toList(),
                            displayBuilder: (id) => _settings!
                                .availableCompanies
                                .firstWhere((c) => c.id == id)
                                .name,
                            bgColor: fieldColor,
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _settings = _settings!.copyWith(
                                    selectedCompanyId: val,
                                  );
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 16),
                          _buildLabel('Site', labelColor),
                          _buildDropdown(
                            value: _settings!.selectedSiteId,
                            items: _settings!.availableSites
                                .map((s) => s.id)
                                .toList(),
                            displayBuilder: (id) => _settings!.availableSites
                                .firstWhere((s) => s.id == id)
                                .name,
                            bgColor: fieldColor,
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _settings = _settings!.copyWith(
                                    selectedSiteId: val,
                                  );
                                });
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildSectionCard(
                        color: cardColor,
                        title: 'Application',
                        titleColor: sectionTitleColor,
                        children: [
                          _buildLabel('Quantity Decimal Places', labelColor),
                          _buildDropdown(
                            value: _settings!.selectedQuantityDecimals
                                .toString(),
                            items: _settings!.decimalOptions
                                .map((e) => e.toString())
                                .toList(),
                            displayBuilder: (val) => val,
                            bgColor: fieldColor,
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _settings = _settings!.copyWith(
                                    selectedQuantityDecimals: int.parse(val),
                                  );
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Set the number of decimal places for displaying all quantities (e.g., weights, amounts).',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildSectionCard(
                        color: cardColor,
                        title: 'Administration',
                        titleColor: sectionTitleColor,
                        children: [
                          InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const UserManagementScreen(),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8.0,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.admin_panel_settings_outlined,
                                    color: Color(0xFFFF9800),
                                    size: 28,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: const [
                                        Text(
                                          'User Management',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          'Create users and set module permissions.',
                                          style: TextStyle(
                                            color: Colors.white54,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
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
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      border: Border(
                        top: BorderSide(color: Colors.white.withOpacity(0.1)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _saveSettings,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF9800),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              elevation: 0,
                            ),
                            child: const Text(
                              'Save Settings',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDark ? Colors.white : Colors.black87,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: IconButton(
                            onPressed: () =>
                                context.read<ThemeCubit>().toggleTheme(),
                            icon: Icon(
                              isDark
                                  ? Icons.light_mode_outlined
                                  : Icons.dark_mode_outlined,
                              color: isDark ? Colors.black87 : Colors.white,
                            ),
                            padding: const EdgeInsets.all(12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSectionCard({
    required Color color,
    required String title,
    required Color titleColor,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: titleColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.white.withOpacity(0.1), height: 1),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildLabel(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String value,
    required List<String> items,
    required String Function(String) displayBuilder,
    required Color bgColor,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: const Color(
            0xFF1E1E1E,
          ), // Darker dropdown menu background
          icon: const Icon(
            Icons.chevron_right_rounded,
            color: Colors.white54,
            size: 20,
          ),
          style: const TextStyle(color: Colors.white, fontSize: 14),
          onChanged: onChanged,
          items: items.map<DropdownMenuItem<String>>((String item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(displayBuilder(item)),
            );
          }).toList(),
        ),
      ),
    );
  }
}
