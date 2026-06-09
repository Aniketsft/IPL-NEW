import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../../data/local/local_database_helper.dart';

class SyncHistoryScreen extends StatefulWidget {
  const SyncHistoryScreen({super.key});

  @override
  State<SyncHistoryScreen> createState() => _SyncHistoryScreenState();
}

class _SyncHistoryScreenState extends State<SyncHistoryScreen> {
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final history = await LocalDatabaseHelper.instance.getSyncHistory();
      setState(() {
        _history = history;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading history: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Sync Audit Trail'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        actions: [
          IconButton(
            onPressed: _loadHistory,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: orange))
          : _history.isEmpty
          ? _buildEmptyState(isDark)
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _history.length,
              itemBuilder: (context, index) {
                final item = _history[index];
                return _buildHistoryCard(item, theme, orange);
              },
            ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded, size: 64, color: isDark ? Colors.grey[700] : Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No sync history found',
            style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> item, ThemeData theme, Color orange) {
    final isDark = theme.brightness == Brightness.dark;
    final timestamp = DateTime.parse(
      item[LocalDatabaseHelper.colSyncTimestamp],
    );
    final status = item[LocalDatabaseHelper.colSyncStatus];
    final message = item[LocalDatabaseHelper.colSyncMessage] ?? '';
    final countsJson = item[LocalDatabaseHelper.colSyncCounts];
    final isSuccess = status == 'Success';

    Map<String, dynamic> counts = {};
    if (countsJson != null) {
      try {
        counts = jsonDecode(countsJson);
      } catch (_) {}
    }

    final statusColor = isSuccess ? Colors.green : Colors.red;

    return Card(
      color: theme.cardColor,
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isDark ? 0 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: statusColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: ExpansionTile(
        collapsedIconColor: isDark ? Colors.white38 : Colors.black38,
        iconColor: orange,
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.1),
          child: Icon(
            isSuccess ? Icons.check_circle_outline : Icons.error_outline,
            color: statusColor,
          ),
        ),
        title: Text(
          DateFormat('MMM dd, yyyy - hh:mm a').format(timestamp),
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          isSuccess ? 'Payload processed successfully' : 'Sync failed',
          style: TextStyle(
            color: isSuccess ? (isDark ? Colors.green[300] : Colors.green[700]) : (isDark ? Colors.red[300] : Colors.red[700]),
            fontSize: 13,
          ),
        ),
        childrenPadding: const EdgeInsets.all(16),
        expandedAlignment: Alignment.topLeft,
        children: [
          if (!isSuccess)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Error: $message',
                style: const TextStyle(color: Colors.redAccent, fontSize: 14),
              ),
            ),
          if (counts.isNotEmpty) ...[
            Text(
              'Records Synchronized:',
              style: TextStyle(
                color: isDark ? Colors.grey : Colors.black54,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            _buildCountGrid(counts, isDark, orange),
          ],
          if (isSuccess && message.contains('ms'))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Performance: ${message.split('completed in ').last}',
                style: TextStyle(
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCountGrid(Map<String, dynamic> counts, bool isDark, Color orange) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: counts.entries.map((e) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                e.key.toUpperCase(),
                style: TextStyle(
                  color: orange,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                e.value.toString(),
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
