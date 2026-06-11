import 'package:flutter/material.dart';

class SearchPickerSheet extends StatefulWidget {
  final String title;
  final List<Map<String, String>> items;
  final Function(String?) onSelected;

  const SearchPickerSheet({
    super.key,
    required this.title,
    required this.items,
    required this.onSelected,
  });

  static void show({
    required BuildContext context,
    required String title,
    required List<Map<String, String>> items,
    required Function(String?) onSelected,
  }) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SearchPickerSheet(
        title: title,
        items: items,
        onSelected: onSelected,
      ),
    );
  }

  @override
  State<SearchPickerSheet> createState() => _SearchPickerSheetState();
}

class _SearchPickerSheetState extends State<SearchPickerSheet> {
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
        return code.contains(query.toLowerCase()) ||
            name.contains(query.toLowerCase());
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

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
              prefixIcon: Icon(Icons.search, color: isDark ? Colors.grey : Colors.grey[600]),
              filled: true,
              fillColor: theme.cardColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: _filteredItems.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return ListTile(
                    title: Text(
                      'All',
                      style: TextStyle(color: orange),
                    ),
                    onTap: () {
                      widget.onSelected(null);
                      Navigator.pop(context);
                    },
                  );
                }
                final item = _filteredItems[index - 1];
                return ListTile(
                  title: Text(
                    item['code'] ?? '',
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    item['name'] ?? '',
                    style: TextStyle(color: isDark ? Colors.grey : Colors.black45, fontSize: 12),
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
