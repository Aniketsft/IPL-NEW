import 'package:flutter/material.dart';
import 'package:enterprise_auth_mobile/core/widgets/industrial_module_layout.dart';

class OtherModulesScreen extends StatelessWidget {
  const OtherModulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return IndustrialModuleLayout(
      title: 'OTHER MODULES',
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'MISCELLANEOUS OPERATIONS',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.bold,
                fontSize: 13,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 24),
            _buildModuleTile(
              Icons.assignment_turned_in_outlined,
              'Quality Assurance',
              'Internal audits & inspections',
            ),
            _buildModuleTile(
              Icons.engineering_outlined,
              'Maintenance',
              'Equipment & facility upkeep',
            ),
            _buildModuleTile(
              Icons.history_outlined,
              'Operation Logs',
              'View system-wide activity history',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModuleTile(IconData icon, String title, String subtitle) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2C2C2E)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFF9800).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: const Color(0xFFFF9800), size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white10),
        ],
      ),
    );
  }
}
