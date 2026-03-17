import 'package:enterprise_auth_mobile/core/widgets/filter_input_widgets.dart';
import 'dart:ui';
import 'package:flutter/material.dart';

class StandardFilter extends StatelessWidget {
  final TextEditingController searchController;
  final String searchHint;
  final Widget? child;
  final VoidCallback? onApply;
  final VoidCallback? onReset;
  final ValueChanged<String>? onSearchChanged;
  final String title;
  final bool hasActiveFilters;

  const StandardFilter({
    super.key,
    required this.searchController,
    this.searchHint = 'Search...',
    this.child,
    this.onApply,
    this.onReset,
    this.onSearchChanged,
    this.title = 'FILTERS',
    this.hasActiveFilters = false,
  });

  void _showFilterModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return FilterStateScope(
            onStateChanged: () => setState(() {}),
            child: _FilterModal(
              title: title,
              onApply: onApply ?? () {},
              onReset: onReset ?? () {},
              child: child ?? const SizedBox.shrink(),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF9800);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          // Premium Search Bar
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: TextField(
                controller: searchController,
                onChanged: onSearchChanged,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: searchHint,
                  hintStyle: const TextStyle(color: Colors.white24, fontSize: 14),
                  prefixIcon: const Icon(Icons.search_rounded, color: orange, size: 20),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Filter Button with Badge
          Stack(
            clipBehavior: Clip.none,
            children: [
              InkWell(
                onTap: () => _showFilterModal(context),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: const Icon(Icons.tune_rounded, color: Colors.white70, size: 22),
                ),
              ),
              if (hasActiveFilters)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    height: 12,
                    width: 12,
                    decoration: BoxDecoration(
                      color: orange,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF121212), width: 2),
                      boxShadow: [
                        BoxShadow(color: orange.withOpacity(0.5), blurRadius: 4, spreadRadius: 1),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterModal extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback onApply;
  final VoidCallback onReset;

  const _FilterModal({
    required this.title,
    required this.child,
    required this.onApply,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF9800);
    const dark100 = Color(0xFF1E1E1E);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: dark100,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, spreadRadius: 5),
            ],
          ),
          child: Column(
            children: [
              // Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              // Content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: child,
                ),
              ),
              // Footer
              Container(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                decoration: BoxDecoration(
                  color: dark100,
                  border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          onReset();
                          Navigator.pop(context);
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Reset All'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () {
                          onApply();
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Apply Filters',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
