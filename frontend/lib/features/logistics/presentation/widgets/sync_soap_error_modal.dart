import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/repositories/sales_invoice_sync_repository.dart';
import '../pages/sync_history_screen.dart';

class SyncSoapErrorModal extends StatelessWidget {
  final List<SyncEntityReport> failedReports;
  final List<SyncEntityReport> allReports;
  final int? successCount;
  final int? failureCount;
  final String? title;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  const SyncSoapErrorModal({
    super.key,
    this.failedReports = const [],
    this.allReports = const [],
    this.successCount,
    this.failureCount,
    this.title,
    this.onRetry,
    this.onDismiss,
  });

  static Future<void> show(
    BuildContext context, {
    List<SyncEntityReport>? failedReports,
    List<SyncEntityReport>? allReports,
    int? successCount,
    int? failureCount,
    String? title,
    VoidCallback? onRetry,
    VoidCallback? onDismiss,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => SyncSoapErrorModal(
        failedReports: failedReports ?? const [],
        allReports: allReports ?? const [],
        successCount: successCount,
        failureCount: failureCount,
        title: title,
        onRetry: onRetry,
        onDismiss: onDismiss,
      ),
    );
  }

  static Future<void> showResults(
    BuildContext context, {
    required SyncBatchResult batchResult,
    VoidCallback? onRetry,
    VoidCallback? onDismiss,
  }) {
    final uploadItems = batchResult.uploadReports.isNotEmpty
        ? batchResult.uploadReports
        : batchResult.reports;
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => SyncSoapErrorModal(
        allReports: uploadItems,
        failedReports: batchResult.failedReports,
        successCount: batchResult.successes.length,
        failureCount: batchResult.failures.length,
        title: batchResult.hasFailures ? 'Sage X3 Sync Rejection' : 'Sage X3 Sync Results',
        onRetry: onRetry,
        onDismiss: onDismiss,
      ),
    );
  }

  String _cleanSoapMessage(String? rawMsg) {
    if (rawMsg == null || rawMsg.trim().isEmpty) {
      return "No detailed message returned from server.";
    }

    String cleaned = rawMsg.trim();

    final colonIdx = cleaned.indexOf(': ');
    if (colonIdx > 0 && colonIdx < 30 && !cleaned.substring(0, colonIdx).contains(' ')) {
      cleaned = cleaned.substring(colonIdx + 2).trim();
    }

    if (cleaned.startsWith('Sage X3: ')) {
      cleaned = cleaned.replaceFirst('Sage X3: ', '');
    }

    return cleaned;
  }

  void _copyAllDiagnostics(BuildContext context, List<SyncEntityReport> displayItems) {
    final buffer = StringBuffer();
    buffer.writeln('=== SAGE X3 SYNC RESPONSES ===');
    buffer.writeln('Timestamp: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Total Items: ${displayItems.length}');
    buffer.writeln('--------------------------------');

    for (int i = 0; i < displayItems.length; i++) {
      final r = displayItems[i];
      final isSuccess = r.status == SyncStatus.success || r.status == SyncStatus.cached304;
      buffer.writeln('[${i + 1}] ${r.entityName} - ${isSuccess ? "SUCCESS" : "FAILED"}');
      if (r.documentId != null) {
        buffer.writeln('Document ID: ${r.documentId}');
      }
      if (r.errorCode != null) {
        buffer.writeln('Error Code: ${r.errorCode}');
      }
      if (r.messages.isNotEmpty) {
        buffer.writeln('Messages:');
        for (final m in r.messages) {
          buffer.writeln('  • $m');
        }
      } else if (r.userMessage != null) {
        buffer.writeln('Message: ${r.userMessage}');
      }
      if (r.technicalDetails != null && r.technicalDetails!.isNotEmpty) {
        buffer.writeln('Technical Details: ${r.technicalDetails}');
      }
      buffer.writeln('--------------------------------');
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Diagnostic details copied to clipboard'),
          ],
        ),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
      ),
    );
  }

  Widget _statusChip(String label, String count, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '$label: $count',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryOrange = theme.primaryColor;

    final displayItems = allReports.isNotEmpty
        ? allReports
        : failedReports;

    final computedSuccess = successCount ??
        displayItems.where((r) => r.status == SyncStatus.success || r.status == SyncStatus.cached304).length;
    final computedFailures = failureCount ??
        displayItems.where((r) => r.status == SyncStatus.failed).length;

    final bool hasErrors = computedFailures > 0;
    final modalTitle = title ?? (hasErrors ? 'Sage X3 Sync Rejection' : 'Sage X3 Sync Complete');

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1E1E24) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isDark ? Colors.white12 : Colors.black12,
          width: 1,
        ),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Header with Icon & Chips
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (hasErrors ? Colors.redAccent : Colors.green).withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      hasErrors ? Icons.sync_problem_rounded : Icons.check_circle_rounded,
                      color: hasErrors ? Colors.redAccent : Colors.green,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          modalTitle,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.3,
                            color: isDark ? Colors.white : const Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$computedSuccess imported • $computedFailures rejected',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, size: 20, color: isDark ? Colors.white54 : Colors.black45),
                    onPressed: () {
                      Navigator.of(context).pop();
                      onDismiss?.call();
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Status Summary Badges
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _statusChip('SUCCESS', computedSuccess.toString(), Colors.green, isDark),
                  _statusChip('FAILED', computedFailures.toString(), Colors.redAccent, isDark),
                ],
              ),

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // 2. Scrollable List of Sync Documents & SOAP Responses
              Flexible(
                child: displayItems.isEmpty
                    ? Center(
                        child: Text(
                          'No document sync records reported.',
                          style: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: displayItems.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final report = displayItems[index];
                          final isItemSuccess = report.status == SyncStatus.success || report.status == SyncStatus.cached304;
                          final cleanMsg = _cleanSoapMessage(report.userMessage);
                          final bool isStockIssue = cleanMsg.toLowerCase().contains('stock') ||
                              cleanMsg.toLowerCase().contains('quantity');

                          final List<String> messageList = report.messages.isNotEmpty
                              ? report.messages
                              : (report.userMessage != null ? [cleanMsg] : []);

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF282830) : const Color(0xFFF9FAFB),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark ? Colors.white10 : Colors.black.withOpacity(0.08),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Item Header
                                Row(
                                  children: [
                                    Icon(
                                      isItemSuccess ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                                      size: 16,
                                      color: isItemSuccess ? Colors.green : Colors.redAccent,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        report.entityName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13.5,
                                          color: isDark ? Colors.white : Colors.black87,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                      decoration: BoxDecoration(
                                        color: isItemSuccess
                                            ? Colors.green.withOpacity(0.12)
                                            : ((isStockIssue ? Colors.orange : Colors.redAccent).withOpacity(0.12)),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        isItemSuccess
                                            ? 'Imported'
                                            : (isStockIssue ? 'Stock Issue' : (report.errorCode ?? 'Rejected')),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: isItemSuccess
                                              ? Colors.green
                                              : (isStockIssue ? Colors.orange : Colors.redAccent),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),

                                // SOAP Response Container
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: (isDark ? Colors.black26 : Colors.white),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border(
                                      left: BorderSide(
                                        color: isItemSuccess
                                            ? Colors.green
                                            : (isStockIssue ? Colors.orange : Colors.redAccent),
                                        width: 3.5,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Sage X3 Response:',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? Colors.white54 : Colors.black45,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      if (messageList.isNotEmpty)
                                        ...messageList.map((m) => Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 2),
                                              child: Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text('• ',
                                                      style: TextStyle(
                                                          color: isDark ? Colors.white54 : Colors.black54,
                                                          fontSize: 11)),
                                                  Expanded(
                                                    child: SelectableText(
                                                      m,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        height: 1.35,
                                                        color: isDark ? const Color(0xFFE0E0E0) : const Color(0xFF1F2937),
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ))
                                      else
                                        SelectableText(
                                          isItemSuccess ? 'Imported successfully into Sage X3' : cleanMsg,
                                          style: TextStyle(
                                            fontSize: 12,
                                            height: 1.35,
                                            color: isDark ? const Color(0xFFE0E0E0) : const Color(0xFF1F2937),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),

                                // Technical details if available
                                if (!isItemSuccess &&
                                    report.technicalDetails != null &&
                                    report.technicalDetails!.trim().isNotEmpty &&
                                    report.technicalDetails != report.userMessage) ...[
                                  const SizedBox(height: 6),
                                  Theme(
                                    data: theme.copyWith(dividerColor: Colors.transparent),
                                    child: ExpansionTile(
                                      tilePadding: EdgeInsets.zero,
                                      childrenPadding: const EdgeInsets.only(top: 4, bottom: 4),
                                      dense: true,
                                      title: Text(
                                        'Technical Details',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark ? Colors.white54 : Colors.black45,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      children: [
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: isDark ? Colors.black38 : const Color(0xFFF3F4F6),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: SelectableText(
                                            report.technicalDetails!,
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontFamily: 'monospace',
                                              color: isDark ? Colors.white70 : Colors.black87,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),

              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 14),

              // 3. Actions Row
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 10,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          side: BorderSide(
                            color: isDark ? Colors.white24 : Colors.black12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () => _copyAllDiagnostics(context, displayItems),
                        icon: const Icon(Icons.copy_rounded, size: 14),
                        label: const Text(
                          'Copy Details',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          side: BorderSide(
                            color: isDark ? Colors.white24 : Colors.black12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const SyncHistoryScreen(initialIndex: 1)),
                          );
                        },
                        icon: const Icon(Icons.history_rounded, size: 14),
                        label: const Text(
                          'Audit Trail',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    alignment: WrapAlignment.end,
                    children: [
                      TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        onPressed: () {
                          Navigator.of(context).pop();
                          onDismiss?.call();
                        },
                        child: Text(
                          'Dismiss',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isDark ? Colors.white70 : Colors.black54,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (hasErrors && onRetry != null)
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryOrange,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 38),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                          onPressed: () {
                            Navigator.of(context).pop();
                            onRetry?.call();
                          },
                          icon: const Icon(Icons.refresh_rounded, size: 15),
                          label: const Text(
                            'Retry Sync',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
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

