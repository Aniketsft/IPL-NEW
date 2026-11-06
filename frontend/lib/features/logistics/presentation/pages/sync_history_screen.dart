import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../../data/local/local_database_helper.dart';
import '../../data/repositories/sales_invoice_sync_repository.dart';

class SyncHistoryScreen extends StatefulWidget {
  final int initialIndex;

  const SyncHistoryScreen({super.key, this.initialIndex = 0});

  @override
  State<SyncHistoryScreen> createState() => _SyncHistoryScreenState();
}

class _SyncHistoryScreenState extends State<SyncHistoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;

  List<Map<String, dynamic>> _backendResponses = [];
  bool _isLoadingBackend = false;
  String? _backendError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialIndex.clamp(0, 1),
    );
    _tabController.addListener(() {
      if (_tabController.index == 1 && _backendResponses.isEmpty && !_isLoadingBackend) {
        _loadBackendResponses();
      }
    });

    _loadHistory();
    if (widget.initialIndex == 1) {
      _loadBackendResponses();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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

  Future<void> _loadBackendResponses() async {
    setState(() {
      _isLoadingBackend = true;
      _backendError = null;
    });
    try {
      final syncRepo = context.read<SalesInvoiceSyncRepository>();
      final responses = await syncRepo.getLatestBackendSyncResponses(limit: 50);
      if (mounted) {
        setState(() {
          _backendResponses = responses;
          _isLoadingBackend = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _backendError = e.toString();
          _isLoadingBackend = false;
        });
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
            onPressed: () {
              if (_tabController.index == 0) {
                _loadHistory();
              } else {
                _loadBackendResponses();
              }
            },
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: orange,
          labelColor: orange,
          unselectedLabelColor: isDark ? Colors.white60 : Colors.black54,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(
              icon: Icon(Icons.phone_android_rounded, size: 20),
              text: 'Local Log',
            ),
            Tab(
              icon: Icon(Icons.cloud_sync_rounded, size: 20),
              text: 'Sage X3 Responses',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLocalHistoryTab(theme, isDark, orange),
          _buildBackendResponsesTab(theme, isDark, orange),
        ],
      ),
    );
  }

  Widget _buildLocalHistoryTab(ThemeData theme, bool isDark, Color orange) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: orange));
    }
    if (_history.isEmpty) {
      return _buildEmptyState(isDark);
    }
    return RefreshIndicator(
      onRefresh: _loadHistory,
      color: orange,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _history.length,
        itemBuilder: (context, index) {
          final item = _history[index];
          return _buildHistoryCard(item, theme, orange);
        },
      ),
    );
  }

  Widget _buildBackendResponsesTab(ThemeData theme, bool isDark, Color orange) {
    if (_isLoadingBackend) {
      return Center(child: CircularProgressIndicator(color: orange));
    }
    if (_backendError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 64, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text(
                'Failed to load Sage X3 responses',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _backendError!,
                textAlign: TextAlign.center,
                style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 13),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadBackendResponses,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_backendResponses.isEmpty) {
      return _buildEmptyBackendState(isDark);
    }
    return RefreshIndicator(
      onRefresh: _loadBackendResponses,
      color: orange,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _backendResponses.length,
        itemBuilder: (context, index) {
          final item = _backendResponses[index];
          return _buildBackendCard(item, theme, orange);
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

  Widget _buildEmptyBackendState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_done_outlined, size: 64, color: isDark ? Colors.grey[700] : Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'No Sage X3 audit responses found',
              style: TextStyle(
                color: isDark ? Colors.grey[300] : Colors.grey[800],
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Responses from Sage X3 SOAP web services (invoices, credit notes, payments) will appear here after sync operations.',
              textAlign: TextAlign.center,
              style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 13),
            ),
          ],
        ),
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

  String _formatActionName(String? action) {
    if (action == null || action.isEmpty) return 'Sage X3 Operation';
    if (action.contains('SalesInvoicePayment') || action.contains('Payment')) return 'Payment Sync';
    if (action.contains('CreditNote')) return 'Credit Note Sync';
    if (action.contains('SalesInvoice') || action.contains('Invoice')) return 'Sales Invoice Sync';
    if (action.contains('Receipt')) return 'Receipt Sync';
    return action.replaceAll('Import', '').replaceAll('Sync', '').trim() + ' Sync';
  }

  Widget _buildBackendCard(Map<String, dynamic> item, ThemeData theme, Color orange) {
    final isDark = theme.brightness == Brightness.dark;
    final isSuccess = item['isSuccess'] == true;
    final actionName = item['actionName'] as String?;
    final identifier = item['identifier'] as String?;
    final docId = item['documentId'] as String?;
    final errorMsg = item['errorMessage'] as String?;
    final triggeredBy = item['triggeredBy'] as String?;
    final deviceId = item['deviceId'] as String?;
    final rawCreatedAt = item['createdAt'];
    DateTime timestamp;
    if (rawCreatedAt is String) {
      timestamp = DateTime.tryParse(rawCreatedAt) ?? DateTime.now();
    } else {
      timestamp = DateTime.now();
    }

    final rawMessages = item['messages'];
    List<String> messages = [];
    if (rawMessages is List) {
      messages = rawMessages.map((e) => e.toString()).toList();
    }

    final statusColor = isSuccess ? Colors.green : Colors.redAccent;

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
            isSuccess ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
            color: statusColor,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                _formatActionName(actionName),
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 14.5,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 0.8),
              ),
              child: Text(
                isSuccess ? 'SUCCESS' : 'FAILED',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            DateFormat('MMM dd, yyyy - hh:mm a').format(timestamp.toLocal()),
            style: TextStyle(
              color: isDark ? Colors.white60 : Colors.black54,
              fontSize: 12,
            ),
          ),
        ),
        childrenPadding: const EdgeInsets.all(16),
        expandedAlignment: Alignment.topLeft,
        children: [
          // Metadata badges
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (identifier != null && identifier.isNotEmpty)
                _buildInfoBadge('Identifier', identifier, isDark),
              if (docId != null && docId.isNotEmpty)
                _buildInfoBadge('Sage X3 Doc', docId, isDark, highlightColor: Colors.green),
              if (triggeredBy != null && triggeredBy.isNotEmpty)
                _buildInfoBadge('User', triggeredBy, isDark),
              if (deviceId != null && deviceId.isNotEmpty)
                _buildInfoBadge('Device', deviceId, isDark),
            ],
          ),
          const SizedBox(height: 12),

          // Messages
          if (messages.isNotEmpty) ...[
            Text(
              'Sage X3 Response Messages:',
              style: TextStyle(
                color: isDark ? Colors.grey[300] : Colors.grey[700],
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? Colors.black26 : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: messages.map((msg) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• ', style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
                        Expanded(
                          child: SelectableText(
                            msg,
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
          ],

          if (errorMsg != null && errorMsg.isNotEmpty && !messages.contains(errorMsg)) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.2)),
              ),
              child: SelectableText(
                'Error: $errorMsg',
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Copy Button
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                final diag = StringBuffer();
                diag.writeln('Action: $actionName');
                diag.writeln('Status: ${isSuccess ? "SUCCESS" : "FAILED"}');
                if (identifier != null) diag.writeln('Identifier: $identifier');
                if (docId != null) diag.writeln('Sage X3 Doc: $docId');
                if (triggeredBy != null) diag.writeln('Triggered By: $triggeredBy');
                diag.writeln('Timestamp: $timestamp');
                if (messages.isNotEmpty) {
                  diag.writeln('Messages:');
                  for (final m in messages) diag.writeln('  - $m');
                }
                if (errorMsg != null) diag.writeln('Error: $errorMsg');

                Clipboard.setData(ClipboardData(text: diag.toString()));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Details copied to clipboard'), duration: Duration(seconds: 2)),
                );
              },
              icon: const Icon(Icons.copy_rounded, size: 14),
              label: const Text('Copy Details', style: TextStyle(fontSize: 11)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBadge(String label, String value, bool isDark, {Color? highlightColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: highlightColor != null
            ? highlightColor.withValues(alpha: 0.12)
            : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04)),
        borderRadius: BorderRadius.circular(6),
        border: highlightColor != null
            ? Border.all(color: highlightColor.withValues(alpha: 0.3), width: 0.8)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: highlightColor ?? (isDark ? Colors.white : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}

