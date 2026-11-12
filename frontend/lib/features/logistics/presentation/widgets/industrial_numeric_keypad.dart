import 'package:flutter/material.dart';

/// Reusable Industrial Numeric Keypad with collapsible handle bar.
class IndustrialNumericKeypad extends StatelessWidget {
  final ValueChanged<String> onDigitPressed;
  final VoidCallback onClear;
  final VoidCallback onBackspace;
  final bool isExpanded;
  final VoidCallback onToggleExpanded;
  final String showLabel;
  final String hideLabel;

  const IndustrialNumericKeypad({
    super.key,
    required this.onDigitPressed,
    required this.onClear,
    required this.onBackspace,
    required this.isExpanded,
    required this.onToggleExpanded,
    this.showLabel = 'Show Keypad (0-9)',
    this.hideLabel = 'Hide Keypad',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Widget buildKey(String label, {VoidCallback? onTap, IconData? icon, Color? color}) {
      return Expanded(
        child: Container(
          height: 48,
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: color ?? (isDark ? const Color(0xFF2A2E39) : Colors.grey.shade200),
              foregroundColor: isDark ? Colors.white : Colors.black87,
              elevation: 0,
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: isDark ? Colors.white12 : Colors.black.withOpacity(0.08),
                ),
              ),
            ),
            onPressed: onTap,
            child: icon != null
                ? Icon(
                    icon,
                    size: 24,
                    color: color != null ? Colors.white : (isDark ? Colors.white : Colors.black87),
                  )
                : Text(
                    label,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Collapsible Handle / Toggle Bar
        InkWell(
          onTap: onToggleExpanded,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                  size: 18,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
                const SizedBox(width: 4),
                Text(
                  isExpanded ? hideLabel : showLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                  size: 18,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ],
            ),
          ),
        ),

        // Large Industrial Numeric Keypad (Collapsible)
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: isExpanded
              ? Container(
                  margin: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          buildKey('1', onTap: () => onDigitPressed('1')),
                          buildKey('2', onTap: () => onDigitPressed('2')),
                          buildKey('3', onTap: () => onDigitPressed('3')),
                        ],
                      ),
                      Row(
                        children: [
                          buildKey('4', onTap: () => onDigitPressed('4')),
                          buildKey('5', onTap: () => onDigitPressed('5')),
                          buildKey('6', onTap: () => onDigitPressed('6')),
                        ],
                      ),
                      Row(
                        children: [
                          buildKey('7', onTap: () => onDigitPressed('7')),
                          buildKey('8', onTap: () => onDigitPressed('8')),
                          buildKey('9', onTap: () => onDigitPressed('9')),
                        ],
                      ),
                      Row(
                        children: [
                          buildKey('C', onTap: onClear, color: Colors.red.shade800),
                          buildKey('0', onTap: () => onDigitPressed('0')),
                          buildKey('', icon: Icons.backspace_outlined, onTap: onBackspace),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                )
              : const SizedBox(height: 4),
        ),
      ],
    );
  }
}

