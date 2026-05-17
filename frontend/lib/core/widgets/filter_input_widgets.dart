import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:intl/intl.dart';

class FilterStateScope extends InheritedWidget {
  final VoidCallback onStateChanged;

  const FilterStateScope({
    super.key,
    required this.onStateChanged,
    required super.child,
  });

  static FilterStateScope? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<FilterStateScope>();
  }

  @override
  bool updateShouldNotify(FilterStateScope oldWidget) => true;
}

class FilterPickerTile extends StatelessWidget {
  final String label;
  final String? value;
  final VoidCallback onTap;
  final IconData icon;

  const FilterPickerTile({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.icon = Icons.person_outline,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    return Expanded(
      child: InkWell(
        onTap: () async {
          await Future.sync(() => onTap());
          if (context.mounted) {
            FilterStateScope.of(context)?.onStateChanged();
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: TextStyle(
                      color: isDark ? Colors.white38 : Colors.black38,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(icon, color: orange, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          value ?? 'All',
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FilterStatusToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const FilterStatusToggle({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black87,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          Switch(
            value: value,
            onChanged: (val) {
              onChanged(val);
              FilterStateScope.of(context)?.onStateChanged();
            },
            activeThumbColor: orange,
            activeTrackColor: orange.withValues(alpha: 0.3),
            inactiveThumbColor: isDark ? Colors.white24 : Colors.black26,
            inactiveTrackColor: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1),
          ),
        ],
      ),
    );
  }
}

class FilterSearchInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  const FilterSearchInput({
    super.key,
    required this.controller,
    this.hint = 'Search...',
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    return TextField(
      controller: controller,
      onChanged: (val) {
        onChanged?.call(val);
        FilterStateScope.of(context)?.onStateChanged();
      },
      style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.black38, fontSize: 15),
        prefixIcon: Icon(Icons.search_rounded, color: orange, size: 20),
        filled: true,
        fillColor: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
        hoverColor: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: orange, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      ),
    );
  }
}

class FilterDatePicker extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  const FilterDatePicker({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    return Expanded(
      child: InkWell(
        onTap: () async {
          await Future.sync(() => onTap());
          if (context.mounted) {
            FilterStateScope.of(context)?.onStateChanged();
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: isDark ? Colors.white38 : Colors.black38,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.calendar_today_rounded, size: 14, color: orange),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      value == null
                          ? 'Select Date'
                          : DateFormat('dd MMM yyyy').format(value!),
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FilterDateInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;

  const FilterDateInput({
    super.key,
    required this.controller,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    return TextField(
      controller: controller,
      readOnly: true,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
      decoration: InputDecoration(
        hintText: label,
        hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.black38, fontSize: 14),
        prefixIcon: Icon(Icons.calendar_month_rounded, color: orange, size: 20),
        filled: true,
        fillColor: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: orange, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      ),
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: isDark 
                  ? ColorScheme.dark(
                      primary: orange,
                      onPrimary: Colors.black,
                      surface: theme.cardColor,
                      onSurface: isDark ? Colors.white : Colors.black87,
                    )
                  : ColorScheme.light(
                      primary: orange,
                      onPrimary: Colors.white,
                      surface: Colors.white,
                      onSurface: Colors.black87,
                    ), dialogTheme: DialogThemeData(backgroundColor: theme.scaffoldBackgroundColor),
              ),
              child: child!,
            );
          },
        );
        if (date != null && context.mounted) {
          controller.text = DateFormat('yyyy-MM-dd').format(date);
          FilterStateScope.of(context)?.onStateChanged();
        }
      },
    );
  }
}

class FilterSegmentedToggle extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const FilterSegmentedToggle({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              color: isDark ? Colors.white38 : Colors.black38,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Container(
          height: 46,
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1)),
          ),
          child: Row(
            children: options.map((option) {
              final isSelected = value == option;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    onChanged(option);
                    FilterStateScope.of(context)?.onStateChanged();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    alignment: Alignment.center,
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isSelected ? orange : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: isSelected
                          ? [BoxShadow(color: orange.withValues(alpha: 0.3), blurRadius: 8, spreadRadius: 1)]
                          : [],
                    ),
                    child: Text(
                      option,
                      style: TextStyle(
                        color: isSelected ? (isDark ? Colors.white : Colors.black) : (isDark ? Colors.white60 : Colors.black45),
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class FilterDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String?>? onChanged;

  const FilterDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              color: isDark ? Colors.white38 : Colors.black38,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: theme.cardColor,
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: isDark ? Colors.white38 : Colors.black38),
              style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
              items: options.map((String option) {
                return DropdownMenuItem<String>(
                  value: option,
                  child: Text(option),
                );
              }).toList(),
              onChanged: (val) {
                onChanged?.call(val);
                FilterStateScope.of(context)?.onStateChanged();
              },
            ),
          ),
        ),
      ],
    );
  }
}
