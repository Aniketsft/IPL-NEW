import 'package:flutter/material.dart';
import '../pages/sync_history_screen.dart';

class SyncStatusHeader extends StatelessWidget {
  final String lastSync;

  const SyncStatusHeader({super.key, required this.lastSync});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SyncHistoryScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: Colors.orange.withOpacity(0.1),
        child: Row(
          children: [
            const Icon(Icons.sync_rounded, size: 16, color: Colors.orange),
            const SizedBox(width: 8),
            Text(
              'Offline Mode - Last Synced: $lastSync',
              style: const TextStyle(
                color: Colors.orange,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            const Icon(Icons.history_rounded, size: 16, color: Colors.orange),
          ],
        ),
      ),
    );
  }
}
