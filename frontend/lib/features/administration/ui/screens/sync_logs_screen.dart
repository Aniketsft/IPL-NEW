import 'package:flutter/material.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../../../core/config/api_config.dart';
import '../../../../core/widgets/industrial_module_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../../core/secure_storage_service.dart';

class SyncLog {
  final String deviceId;
  final String lastSyncedBy;
  final DateTime lastSyncTime;
  final String actionType;

  SyncLog({
    required this.deviceId,
    required this.lastSyncedBy,
    required this.lastSyncTime,
    required this.actionType,
  });

  factory SyncLog.fromJson(Map<String, dynamic> json) {
    final String timeStr = json['lastSyncTime'];
    final String safeTimeStr = timeStr.endsWith('Z') ? timeStr : '${timeStr}Z';
    return SyncLog(
      deviceId: json['deviceId'] ?? '',
      lastSyncedBy: json['lastSyncedBy'] ?? '',
      lastSyncTime: DateTime.parse(safeTimeStr).toLocal(),
      actionType: json['actionType'] ?? '',
    );
  }
}

class SyncLogsScreen extends StatefulWidget {
  const SyncLogsScreen({super.key});

  @override
  State<SyncLogsScreen> createState() => _SyncLogsScreenState();
}

class _SyncLogsScreenState extends State<SyncLogsScreen> {
  List<SyncLog> _logs = [];
  bool _isLoading = true;
  String _error = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fetchLogs();
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _fetchLogs();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchLogs() async {
    try {
      final secureStorage = SecureStorageService();
      final token = await secureStorage.getToken();
      
      final url = Uri.parse('${ApiConfig.baseUrl}Sync/devices/latest');

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _logs = data.map((e) => SyncLog.fromJson(e)).toList();
            _isLoading = false;
            _error = '';
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = 'Failed to fetch logs: ${response.statusCode}';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Connection error: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final teal = theme.primaryColor;

    return IndustrialModuleLayout(
      title: 'Device Sync Logs',
      body: _isLoading && _logs.isEmpty
          ? Center(child: CircularProgressIndicator(color: teal))
          : _error.isNotEmpty && _logs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, color: Colors.red, size: 48),
                      const SizedBox(height: 16),
                      Text(_error, style: TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          setState(() => _isLoading = true);
                          _fetchLogs();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchLogs,
                  color: teal,
                  child: _logs.isEmpty
                      ? ListView(
                          children: [
                            SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                            const Center(
                              child: Text(
                                'No sync logs found.',
                                style: TextStyle(color: Colors.grey, fontSize: 16),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _logs.length,
                          itemBuilder: (context, index) {
                      final log = _logs[index];
                      final bool isPush = log.actionType.contains('PUSH');
                      final Color statusColor = isPush ? Colors.blue : teal;
                      final IconData statusIcon = isPush ? Icons.upload : Icons.download;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: isDark ? 2 : 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isDark ? Colors.white12 : Colors.black12,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(statusIcon, color: statusColor, size: 24),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      log.deviceId,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Action: ${isPush ? 'PUSH (Sent Data)' : 'PULL (Refresh)'}',
                                      style: TextStyle(
                                        color: statusColor,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.white12 : Colors.black.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.person, size: 14, color: Colors.grey),
                                        const SizedBox(width: 4),
                                        Text(
                                          log.lastSyncedBy,
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    timeago.format(log.lastSyncTime),
                                    style: TextStyle(
                                      color: teal,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${log.lastSyncTime.hour.toString().padLeft(2, '0')}:${log.lastSyncTime.minute.toString().padLeft(2, '0')}',
                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
