import 'package:enterprise_auth_mobile/core/widgets/filter_input_widgets.dart';
import 'dart:async';
import 'package:flutter/material.dart';

class StandardFilter extends StatefulWidget {
  final TextEditingController searchController;
  final String searchHint;
  final Widget? child;
  final Widget Function(BuildContext context, StateSetter setModalState)?
      filterBuilder;
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
    this.filterBuilder,
    this.onApply,
    this.onReset,
    this.onSearchChanged,
    this.title = 'FILTERS',
    this.hasActiveFilters = false,
  });

  @override
  State<StandardFilter> createState() => _StandardFilterState();
}

class _StandardFilterState extends State<StandardFilter> {
  Timer? _debounceTimer;
  final ValueNotifier<int> _rebuildNotifier = ValueNotifier(0);

  @override
  void didUpdateWidget(covariant StandardFilter oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When the parent screen rebuilds, it might have new filter state variables.
    // We force the modal to rebuild its filters to pick up these fresh values.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _rebuildNotifier.value++;
      }
    });
  }

  @override
  void dispose() {
    _rebuildNotifier.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _handleStateChanged(StateSetter setModalState) {
    // 1. Immediately increment counter to force a "Hard Refresh" of the filter UI
    _rebuildNotifier.value++;

    // 2. Refresh modal scope
    setModalState(() {});

    // 3. Debounce background data update
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted && widget.onApply != null) {
        widget.onApply!();
      }
    });
  }

  void _showFilterModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) => StatefulBuilder(
        builder: (context, setModalState) {
          return FilterStateScope(
            onStateChanged: () => _handleStateChanged(setModalState),
            child: ValueListenableBuilder<int>(
              valueListenable: _rebuildNotifier,
              builder: (context, rebuildValue, _) {
                return _FilterModal(
                  key: ValueKey('filter_modal_$rebuildValue'),
                  title: widget.title,
                  onApply: () {
                    // Explicitly apply before closing
                    if (widget.onApply != null) widget.onApply!();
                    Navigator.pop(context);
                  },
                  onReset: widget.onReset ?? () {},
                  child: widget.filterBuilder?.call(context, setModalState) ??
                      widget.child ??
                      const SizedBox.shrink(),
                );
              },
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          // Premium Search Bar
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1)),
              ),
              child: TextField(
                controller: widget.searchController,
                onChanged: widget.onSearchChanged,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  hintStyle:
                      TextStyle(color: isDark ? Colors.white24 : Colors.black38, fontSize: 14),
                  prefixIcon:
                      Icon(Icons.search_rounded, color: orange, size: 20),
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
                    color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1)),
                  ),
                  child: Icon(Icons.tune_rounded,
                      color: isDark ? Colors.white70 : Colors.black54, size: 22),
                ),
              ),
              if (widget.hasActiveFilters)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    height: 12,
                    width: 12,
                    decoration: BoxDecoration(
                      color: orange,
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: theme.scaffoldBackgroundColor, width: 2),
                      boxShadow: [
                        BoxShadow(
                            color: orange.withValues(alpha: 0.5),
                            blurRadius: 4,
                            spreadRadius: 1),
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
    super.key,
    required this.title,
    required this.child,
    required this.onApply,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.1), blurRadius: 20, spreadRadius: 5),
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
                    color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1),
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
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.close, color: isDark ? Colors.white54 : Colors.black45),
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
                  color: theme.cardColor,
                  border: Border(top: BorderSide(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05))),
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
                          foregroundColor: isDark ? Colors.white70 : Colors.black54,
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
