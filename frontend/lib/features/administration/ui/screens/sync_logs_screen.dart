import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import '../../../../core/config/api_config.dart';
import '../../../../core/widgets/industrial_module_layout.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../../core/secure_storage_service.dart';

class SyncLog {
  final String deviceId;
  final String lastSyncedBy;
  final DateTime lastSyncTime;
  final String actionType;
  final String site;

  SyncLog({
    required this.deviceId,
    required this.lastSyncedBy,
    required this.lastSyncTime,
    required this.actionType,
    this.site = '',
  });

  factory SyncLog.fromJson(Map<String, dynamic> json) {
    final dynamic timeVal = json['lastSyncTime'];
    DateTime parsedTime = DateTime.now();
    if (timeVal != null) {
      final String timeStr = timeVal.toString();
      final String safeTimeStr = timeStr.endsWith('Z') ? timeStr : '${timeStr}Z';
      parsedTime = DateTime.tryParse(safeTimeStr)?.toLocal() ?? DateTime.now();
    }
    return SyncLog(
      deviceId: json['deviceId']?.toString() ?? '',
      lastSyncedBy: json['lastSyncedBy']?.toString() ?? '',
      lastSyncTime: parsedTime,
      actionType: json['actionType']?.toString() ?? '',
      site: json['site']?.toString() ?? '',
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

  String _userClaimedSite = 'ALL';
  String _selectedFilterSite = 'ALL';
  final List<String> _commonSites = ['ALL', 'IPL', 'INL', 'PFO', 'MCO', 'TBO', 'DIS'];

  @override
  void initState() {
    super.initState();
    _initUserSiteAndFetch();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      _fetchLogs(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _initUserSiteAndFetch() async {
    try {
      final secureStorage = SecureStorageService();
      final token = await secureStorage.getToken();
      if (token != null && token.isNotEmpty) {
        final parts = token.split('.');
        if (parts.length == 3) {
          final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
          if (payload is Map<String, dynamic>) {
            final siteCode = payload['SiteCode']?.toString() ?? 'ALL';
            if (mounted) {
              setState(() {
                _userClaimedSite = siteCode;
                _selectedFilterSite = siteCode != 'ALL' ? siteCode : 'ALL';
              });
            }
          }
        }
      }
    } catch (_) {}

    await _fetchLogs();
  }

  Future<void> _fetchLogs({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = '';
      });
    }

    try {
      final secureStorage = SecureStorageService();
      final token = await secureStorage.getToken();

      // Enforce site filter: site-restricted users ALWAYS query their claimed site
      final querySite = _userClaimedSite != 'ALL' 
          ? _userClaimedSite 
          : (_selectedFilterSite != 'ALL' ? _selectedFilterSite : null);

      final queryParam = querySite != null ? '?site=$querySite' : '';
      final url = Uri.parse('${ApiConfig.baseUrl}Sync/devices/latest$queryParam');

      // Use IOClient with SSL bypass for dev environments
      final httpClient = HttpClient()
        ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
      final client = IOClient(httpClient);

      final response = await client.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

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

  String _formatActionType(String action) {
    switch (action.toUpperCase()) {
      case 'SYNC_PULL':
        return 'PULL (Data Refresh)';
      case 'SYNC_PUSH':
        return 'PUSH (Production Scans)';
      case 'SYNC_SALES_INVOICE':
        return 'SALES (Invoice Sync)';
      case 'SYNC_SALES_CREDIT_NOTE':
        return 'SALES (Credit Note)';
      case 'SYNC_SALES_CATALOG':
        return 'SALES (Catalog Sync)';
      default:
        return action.replaceAll('_', ' ');
    }
  }

  Color _getActionColor(String action, Color defaultTeal) {
    final act = action.toUpperCase();
    if (act.contains('PUSH') || act.contains('INVOICE')) {
      return Colors.blue;
    }
    if (act.contains('CREDIT')) {
      return Colors.amber.shade700;
    }
    return defaultTeal;
  }

  IconData _getActionIcon(String action) {
    final act = action.toUpperCase();
    if (act.contains('PUSH') || act.contains('INVOICE')) {
      return Icons.upload_rounded;
    }
    if (act.contains('CREDIT')) {
      return Icons.assignment_return_rounded;
    }
    return Icons.download_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final teal = theme.primaryColor;

    return IndustrialModuleLayout(
      title: 'Device Sync Logs',
      body: Column(
        children: [
          // Site Filter Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03),
            child: Row(
              children: [
                Icon(Icons.location_on_outlined, size: 18, color: teal),
                const SizedBox(width: 8),
                Text(
                  _userClaimedSite != 'ALL'
                      ? 'Site Locked: $_userClaimedSite'
                      : 'Filter by Site:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const SizedBox(width: 12),
                if (_userClaimedSite == 'ALL')
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _commonSites.map((site) {
                          final isSelected = _selectedFilterSite == site;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(site, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                              selected: isSelected,
                              selectedColor: teal.withOpacity(0.2),
                              side: BorderSide(color: isSelected ? teal : (isDark ? Colors.white12 : Colors.black12)),
                              onSelected: (selected) {
                                if (selected && _selectedFilterSite != site) {
                                  setState(() => _selectedFilterSite = site);
                                  _fetchLogs();
                                }
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: teal.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: teal),
                    ),
                    child: Text(
                      _userClaimedSite,
                      style: TextStyle(color: teal, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  tooltip: 'Refresh Logs',
                  onPressed: () => _fetchLogs(),
                ),
              ],
            ),
          ),

          // Main Body
          Expanded(
            child: _isLoading && _logs.isEmpty
                ? Center(child: CircularProgressIndicator(color: teal))
                : _error.isNotEmpty && _logs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red, size: 48),
                            const SizedBox(height: 16),
                            Text(_error, style: const TextStyle(color: Colors.red)),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () => _fetchLogs(),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => _fetchLogs(),
                        color: teal,
                        child: _logs.isEmpty
                            ? ListView(
                                children: [
                                  SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                                  Center(
                                    child: Column(
                                      children: [
                                        Icon(Icons.sync_disabled_rounded, size: 48, color: Colors.grey.withOpacity(0.5)),
                                        const SizedBox(height: 12),
                                        Text(
                                          'No sync logs found for site: ${_userClaimedSite != 'ALL' ? _userClaimedSite : _selectedFilterSite}',
                                          style: const TextStyle(color: Colors.grey, fontSize: 15),
                                        ),
                                        const SizedBox(height: 8),
                                        const Text(
                                          'Logs will appear automatically whenever a device syncs.',
                                          style: TextStyle(color: Colors.grey, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: _logs.length,
                                itemBuilder: (context, index) {
                                  final log = _logs[index];
                                  final Color statusColor = _getActionColor(log.actionType, teal);
                                  final IconData statusIcon = _getActionIcon(log.actionType);

                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    elevation: isDark ? 2 : 3,
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
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 8),
                                                Wrap(
                                                  crossAxisAlignment: WrapCrossAlignment.center,
                                                  spacing: 8,
                                                  children: [
                                                    if (log.site.isNotEmpty)
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: teal.withOpacity(0.15),
                                                          borderRadius: BorderRadius.circular(4),
                                                          border: Border.all(color: teal.withOpacity(0.4)),
                                                        ),
                                                        child: Text(
                                                          log.site,
                                                          style: TextStyle(
                                                            color: teal,
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                        ),
                                                      ),
                                                    Text(
                                                      _formatActionType(log.actionType),
                                                      style: TextStyle(
                                                        color: statusColor,
                                                        fontWeight: FontWeight.w600,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                  ],
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
                                              const SizedBox(height: 10),
                                              Text(
                                                timeago.format(log.lastSyncTime),
                                                style: TextStyle(
                                                  color: teal,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${log.lastSyncTime.hour.toString().padLeft(2, '0')}:${log.lastSyncTime.minute.toString().padLeft(2, '0')}',
                                                style: const TextStyle(fontSize: 11, color: Colors.grey),
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
          ),
        ],
      ),
    );
  }
}
