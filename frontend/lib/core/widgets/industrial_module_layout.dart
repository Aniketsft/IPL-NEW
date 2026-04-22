import 'package:flutter/material.dart';

class IndustrialModuleLayout extends StatelessWidget {
  final String title;
  final Widget body;
  final Widget? floatingActionButton;
  final List<Widget>? extraActions;
  final bool showLogout;
  final bool showPlantName;

  const IndustrialModuleLayout({
    super.key,
    required this.title,
    required this.body,
    this.floatingActionButton,
    this.extraActions,
    this.showLogout = false,
    this.showPlantName = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: isDark ? Colors.white70 : Colors.black87),
        title: Text(
          title,
          style: TextStyle(
            color: theme.primaryColor,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          if (extraActions != null) ...extraActions!,
          IconButton(
            icon: Icon(Icons.home_rounded, color: theme.primaryColor, size: 24),
            tooltip: 'Back to Home',
            onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
          ),
          if (showPlantName || showLogout)
            Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showPlantName)
                    Text(
                      'Main Plant',
                      style: TextStyle(
                        color: isDark ? Colors.blueGrey : Colors.grey[600],
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  if (showPlantName && showLogout) const SizedBox(width: 8),
                  if (showLogout)
                    InkWell(
                      onTap: () {
                        // Logout action could go here
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Icon(
                          Icons.exit_to_app_rounded,
                          color: isDark ? Colors.white60 : Colors.black54,
                          size: 22,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: body,
      floatingActionButton: floatingActionButton,
    );
  }
}
