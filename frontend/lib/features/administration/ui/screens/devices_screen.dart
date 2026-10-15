import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/secure_storage_service.dart';
import '../../../../core/services/device_info_service.dart';
import '../../../../core/widgets/industrial_module_layout.dart';
import '../../../logistics/data/local/local_database_helper.dart';

class DeviceItem {
  final String deviceId;
  final String? macAddress;
  final String deviceName;
  final String siteCode;
  final String? warehouseCode;
  final String locationCode;
  final String? assignedUserName;
  final bool isActive;
  final DateTime? updatedAt;
  final String? updatedBy;

  DeviceItem({
    required this.deviceId,
    this.macAddress,
    required this.deviceName,
    required this.siteCode,
    this.warehouseCode,
    required this.locationCode,
    this.assignedUserName,
    this.isActive = true,
    this.updatedAt,
    this.updatedBy,
  });

  factory DeviceItem.fromJson(Map<String, dynamic> json) {
    return DeviceItem(
      deviceId: json['deviceId'] ?? '',
      macAddress: json['macAddress'],
      deviceName: json['deviceName'] ?? json['deviceId'] ?? '',
      siteCode: json['siteCode'] ?? '',
      warehouseCode: json['warehouseCode'],
      locationCode: json['locationCode'] ?? '',
      assignedUserName: json['assignedUserName'],
      isActive: json['isActive'] == null ? true : (json['isActive'] is bool ? json['isActive'] : json['isActive'] == 1),
      updatedAt: json['updatedAt'] != null ? DateTime.tryParse(json['updatedAt'].toString()) : null,
      updatedBy: json['updatedBy'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'deviceId': deviceId,
      'macAddress': macAddress,
      'deviceName': deviceName,
      'siteCode': siteCode,
      'warehouseCode': warehouseCode,
      'locationCode': locationCode,
      'assignedUserName': assignedUserName,
      'isActive': isActive ? 1 : 0,
      'updatedAt': updatedAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
      'updatedBy': updatedBy ?? 'LOCAL',
    };
  }
}

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final _storage = SecureStorageService();
  final _db = LocalDatabaseHelper.instance;

  List<DeviceItem> _devices = [];
  List<DeviceItem> _filteredDevices = [];
  List<Map<String, dynamic>> _availableLocations = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _userSiteCode = 'IPL';
  String _currentDeviceId = '';
  String _currentDeviceMac = '';
  String? _currentDeviceLocation;

  @override
  void initState() {
    super.initState();
    _currentDeviceId = DeviceInfoService.instance.deviceId;
    _currentDeviceMac = DeviceInfoService.instance.macAddress;
    _currentDeviceLocation = DeviceInfoService.instance.assignedLocation;
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final site = await _storage.getSiteCode() ?? 'IPL';
    if (mounted) setState(() => _userSiteCode = site);

    // 1. Load locations from local SQLite table (offline-ready)
    final locs = await _db.getLocations(siteCode: site);
    if (mounted) setState(() => _availableLocations = locs);

    // 2. Load cached devices from SQLite first
    await _loadFromLocalDb();

    // 3. Try to sync online with backend
    await _fetchDevicesOnline();
  }

  Future<void> _loadFromLocalDb() async {
    try {
      final rows = await _db.getDeviceLocationsBySite(_userSiteCode);
      if (rows.isNotEmpty && mounted) {
        final list = rows.map((r) => DeviceItem.fromJson(r)).toList();
        setState(() {
          _devices = list;
          _applyFilter();
          _isLoading = false;
        });
        _syncCurrentDeviceState(list);
      }
    } catch (e) {
      debugPrint('Error loading devices from local DB: $e');
    }
  }

  void _syncCurrentDeviceState(List<DeviceItem> list) {
    final match = list.firstWhere(
      (d) => d.deviceId == _currentDeviceId || (d.macAddress != null && d.macAddress!.isNotEmpty && d.macAddress == _currentDeviceMac),
      orElse: () => DeviceItem(deviceId: '', deviceName: '', siteCode: '', locationCode: ''),
    );
    if (match.deviceId.isNotEmpty) {
      DeviceInfoService.instance.setAssignedLocation(
        siteCode: match.siteCode,
        warehouseCode: match.warehouseCode,
        locationCode: match.locationCode,
      );
      if (mounted) {
        setState(() {
          _currentDeviceLocation = match.locationCode;
          if (match.macAddress != null && match.macAddress!.isNotEmpty) {
            _currentDeviceMac = match.macAddress!;
          }
        });
      }
    }
  }

  Future<void> _fetchDevicesOnline() async {
    try {
      final token = await _storage.getToken();
      final url = Uri.parse('${ApiConfig.baseUrl}Devices?site=$_userSiteCode');

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
          'X-Device-Id': _currentDeviceId,
        },
      ).timeout(const Duration(seconds: 7));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final onlineList = data.map((e) => DeviceItem.fromJson(e)).toList();

        // Replicate to SQLite
        await _db.saveDeviceLocationsBatch(onlineList.map((d) => d.toMap()).toList());

        if (mounted) {
          setState(() {
            _devices = onlineList;
            _applyFilter();
            _isLoading = false;
          });
          _syncCurrentDeviceState(onlineList);
        }
      } else {
        if (_devices.isEmpty && mounted) {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      debugPrint('Device online fetch failed (offline fallback active): $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilter() {
    if (_searchQuery.trim().isEmpty) {
      _filteredDevices = List.from(_devices);
    } else {
      final q = _searchQuery.trim().toLowerCase();
      _filteredDevices = _devices.where((d) {
        return d.deviceName.toLowerCase().contains(q) ||
            d.deviceId.toLowerCase().contains(q) ||
            (d.macAddress?.toLowerCase().contains(q) ?? false) ||
            d.locationCode.toLowerCase().contains(q);
      }).toList();
    }
  }

  void _openAssignDialog([DeviceItem? existing]) {
    final deviceIdCtrl = TextEditingController(text: existing?.deviceId ?? _currentDeviceId);
    final deviceNameCtrl = TextEditingController(text: existing?.deviceName ?? (existing == null ? _currentDeviceId : ''));
    final macCtrl = TextEditingController(text: existing?.macAddress ?? (existing == null ? _currentDeviceMac : ''));
    final locationCtrl = TextEditingController(text: existing?.locationCode ?? _currentDeviceLocation ?? '');
    String? selectedWarehouse = existing?.warehouseCode;

    // Deduplicate locations safely by code to prevent Dropdown crash
    final Map<String, Map<String, dynamic>> uniqueLocations = {};
    for (final loc in _availableLocations) {
      final code = loc['location']?.toString().trim() ?? '';
      if (code.isNotEmpty && !uniqueLocations.containsKey(code)) {
        uniqueLocations[code] = loc;
      }
    }
    final locList = uniqueLocations.values.toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (modalContext, setModalState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final primary = Theme.of(context).primaryColor;

          return Container(
            padding: EdgeInsets.only(
              top: 20,
              left: 20,
              right: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.devices_other_rounded, color: primary),
                          const SizedBox(width: 8),
                          Text(
                            existing == null ? 'Assign Device Location' : 'Edit Device Location',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: deviceIdCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Device Identifier (Hardware UID)',
                      prefixIcon: Icon(Icons.perm_device_information),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: deviceNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Device Name / Alias (e.g. Van 04 Scanner)',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: macCtrl,
                          decoration: const InputDecoration(
                            labelText: 'MAC Address / Barcode',
                            hintText: 'e.g. 00:1A:2B:3C:4D:5E',
                            prefixIcon: Icon(Icons.wifi),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () async {
                          final scanned = await _scanBarcode(context);
                          if (scanned != null && scanned.isNotEmpty) {
                            setModalState(() {
                              macCtrl.text = scanned.trim();
                            });
                          }
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 22),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('ASSIGN WAREHOUSE LOCATION', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 8),

                  TextField(
                    controller: locationCtrl,
                    decoration: InputDecoration(
                      labelText: 'Location Code *',
                      hintText: 'e.g. REC, ST01, QUAI...',
                      prefixIcon: const Icon(Icons.location_on_outlined),
                      suffixIcon: locList.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.arrow_drop_down_circle_outlined),
                              tooltip: 'Select from available locations',
                              onPressed: () => _showLocationSelector(
                                ctx,
                                locList,
                                locationCtrl,
                                (wrh) => setModalState(() => selectedWarehouse = wrh),
                              ),
                            )
                          : null,
                    ),
                    onChanged: (val) {
                      final match = locList.firstWhere(
                        (l) => l['location']?.toString().toUpperCase() == val.trim().toUpperCase(),
                        orElse: () => {},
                      );
                      selectedWarehouse = match['warehouse']?.toString();
                    },
                  ),

                  if (selectedWarehouse != null && selectedWarehouse!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(left: 4.0),
                      child: Text(
                        'Assigned Warehouse: $selectedWarehouse',
                        style: TextStyle(fontSize: 11, color: primary, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],

                  if (locList.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Text('QUICK SELECT:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ...locList.take(6).map((loc) {
                          final code = loc['location']?.toString() ?? '';
                          final wrh = loc['warehouse']?.toString() ?? '';
                          return ActionChip(
                            label: Text('$code${wrh.isNotEmpty ? ' ($wrh)' : ''}', style: const TextStyle(fontSize: 11)),
                            backgroundColor: locationCtrl.text == code ? primary.withOpacity(0.2) : null,
                            side: BorderSide(color: locationCtrl.text == code ? primary : Colors.grey.withOpacity(0.3)),
                            onPressed: () {
                              setModalState(() {
                                locationCtrl.text = code;
                                selectedWarehouse = wrh.isNotEmpty ? wrh : null;
                              });
                            },
                          );
                        }),
                        if (locList.length > 6)
                          ActionChip(
                            avatar: const Icon(Icons.search, size: 14),
                            label: Text('All (${locList.length})...', style: const TextStyle(fontSize: 11)),
                            onPressed: () => _showLocationSelector(
                              ctx,
                              locList,
                              locationCtrl,
                              (wrh) => setModalState(() => selectedWarehouse = wrh),
                            ),
                          ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('SAVE & MAP LOCATION', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      onPressed: () async {
                        final devId = deviceIdCtrl.text.trim();
                        final devName = deviceNameCtrl.text.trim();
                        final devMac = macCtrl.text.trim();
                        final loc = locationCtrl.text.trim();
                        if (devId.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Device Identifier cannot be empty.')));
                          return;
                        }
                        if (loc.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select or enter a location.')));
                          return;
                        }

                        Navigator.pop(ctx);
                        await _saveDeviceMapping(
                          deviceId: devId,
                          deviceName: devName.isNotEmpty ? devName : devId,
                          macAddress: devMac.isNotEmpty ? devMac : null,
                          siteCode: _userSiteCode,
                          warehouseCode: selectedWarehouse,
                          locationCode: loc,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showLocationSelector(
    BuildContext context,
    List<Map<String, dynamic>> locations,
    TextEditingController locationCtrl,
    Function(String?) onWarehouseSelected,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (pickerCtx) {
        String filter = '';
        return StatefulBuilder(
          builder: (pCtx, setPickerState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final primary = Theme.of(context).primaryColor;
            final filtered = filter.isEmpty
                ? locations
                : locations.where((l) {
                    final c = (l['location']?.toString() ?? '').toLowerCase();
                    final w = (l['warehouse']?.toString() ?? '').toLowerCase();
                    return c.contains(filter.toLowerCase()) || w.contains(filter.toLowerCase());
                  }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Select Location (${locations.length})',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(pickerCtx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search location or warehouse...',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (val) => setPickerState(() => filter = val),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('No matching locations found', style: TextStyle(color: Colors.grey)))
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final item = filtered[i];
                              final code = item['location']?.toString() ?? '';
                              final wrh = item['warehouse']?.toString() ?? '';
                              final type = item['locationType']?.toString() ?? '';
                              return ListTile(
                                dense: true,
                                title: Text(code, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('$wrh${type.isNotEmpty ? ' • $type' : ''}'),
                                trailing: const Icon(Icons.chevron_right, size: 16),
                                onTap: () {
                                  locationCtrl.text = code;
                                  onWarehouseSelected(wrh.isNotEmpty ? wrh : null);
                                  Navigator.pop(pickerCtx);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<String?> _scanBarcode(BuildContext context) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (bContext) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              AppBar(
                backgroundColor: Colors.transparent,
                title: const Text('Scan MAC / Device Barcode', style: TextStyle(color: Colors.white)),
                leading: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(bContext),
                ),
              ),
              Expanded(
                child: MobileScanner(
                  onDetect: (capture) {
                    final barcodes = capture.barcodes;
                    if (barcodes.isNotEmpty) {
                      final code = barcodes.first.rawValue;
                      if (code != null && code.trim().isNotEmpty) {
                        Navigator.pop(bContext, code.trim());
                      }
                    }
                  },
                  errorBuilder: (context, error) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.camera_alt_outlined, color: Colors.orange, size: 48),
                            const SizedBox(height: 12),
                            Text(
                              'Camera initialization failed: ${error.errorCode}',
                              style: const TextStyle(color: Colors.white70),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(bContext),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveDeviceMapping({
    required String deviceId,
    required String deviceName,
    String? macAddress,
    required String siteCode,
    String? warehouseCode,
    required String locationCode,
  }) async {
    setState(() => _isLoading = true);

    final item = DeviceItem(
      deviceId: deviceId,
      deviceName: deviceName,
      macAddress: macAddress,
      siteCode: siteCode,
      warehouseCode: warehouseCode,
      locationCode: locationCode,
      updatedAt: DateTime.now(),
      updatedBy: 'APP',
    );

    // 1. Immediately write to SQLite for 100% offline reliability
    await _db.insertOrUpdateDeviceLocation(item.toMap());

    // 2. If this is current device, update local session
    if (deviceId == _currentDeviceId) {
      await DeviceInfoService.instance.setAssignedLocation(
        siteCode: siteCode,
        warehouseCode: warehouseCode,
        locationCode: locationCode,
      );
      if (macAddress != null) {
        await DeviceInfoService.instance.setMacAddress(macAddress);
      }
      setState(() {
        _currentDeviceLocation = locationCode;
        if (macAddress != null) _currentDeviceMac = macAddress;
      });
    }

    // 3. Sync to Backend MSSQL if online
    try {
      final token = await _storage.getToken();
      final url = Uri.parse('${ApiConfig.baseUrl}Devices/assign');
      final payload = {
        'deviceId': deviceId,
        'macAddress': macAddress,
        'deviceName': deviceName,
        'siteCode': siteCode,
        'warehouseCode': warehouseCode,
        'locationCode': locationCode,
        'isActive': true,
      };

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
          'X-Device-Id': _currentDeviceId,
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 7));

      if (response.statusCode == 200) {
        final saved = DeviceItem.fromJson(jsonDecode(response.body));
        await _db.insertOrUpdateDeviceLocation(saved.toMap());
      }
    } catch (e) {
      debugPrint('Online assignment sync skipped/failed: $e (saved offline in SQLite)');
    }

    await _loadFromLocalDb();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Device "$deviceName" successfully mapped to Location "$locationCode"'),
          backgroundColor: Colors.teal.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.primaryColor;

    return IndustrialModuleLayout(
      title: 'Devices & Locations',
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_location_alt_rounded),
        label: const Text('Assign Location'),
        onPressed: () => _openAssignDialog(),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchDevicesOnline,
        color: primary,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Current Device Status Card
            _buildCurrentDeviceCard(isDark, primary),
            const SizedBox(height: 16),

            // Search Bar
            TextField(
              decoration: InputDecoration(
                hintText: 'Search by Device Name, MAC, or Location...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                            _applyFilter();
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.black.withOpacity(0.04),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                  _applyFilter();
                });
              },
            ),
            const SizedBox(height: 16),

            // Devices List
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'SITE DEVICES (${_filteredDevices.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
                ),
                Text(
                  'Site: $_userSiteCode',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: primary),
                ),
              ],
            ),
            const SizedBox(height: 10),

            if (_isLoading && _devices.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator(color: primary)),
              )
            else if (_filteredDevices.isEmpty)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      const Icon(Icons.devices_outlined, size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      const Text(
                        'No devices mapped to this site yet.',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Tap "Assign Location" below to map this device or scan a MAC address.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Map Current Device'),
                        onPressed: () => _openAssignDialog(),
                      ),
                    ],
                  ),
                ),
              )
            else
              ..._filteredDevices.map((d) => _buildDeviceCard(d, isDark, primary)),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentDeviceCard(bool isDark, Color primary) {
    final bool hasLocation = _currentDeviceLocation != null && _currentDeviceLocation!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E3A3A), const Color(0xFF122323)]
              : [const Color(0xFFE0F2F1), const Color(0xFFB2DFDB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primary.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.smartphone_rounded, color: primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'THIS HANDHELD DEVICE',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                    ),
                    Text(
                      _currentDeviceId,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Chip(
                label: Text(
                  hasLocation ? 'MAPPED' : 'NO LOCATION',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: hasLocation ? Colors.teal : Colors.orange,
                  ),
                ),
                backgroundColor: (hasLocation ? Colors.teal : Colors.orange).withOpacity(0.15),
                side: BorderSide.none,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Assigned Location', style: TextStyle(color: Colors.grey, fontSize: 11)),
                    const SizedBox(height: 2),
                    Text(
                      hasLocation ? _currentDeviceLocation! : 'Not Assigned',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: hasLocation ? primary : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Device MAC', style: TextStyle(color: Colors.grey, fontSize: 11)),
                    const SizedBox(height: 2),
                    Text(
                      _currentDeviceMac.isNotEmpty ? _currentDeviceMac : 'Not linked',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => _openAssignDialog(),
                child: Text(hasLocation ? 'Change' : 'Assign'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(DeviceItem d, bool isDark, Color primary) {
    final bool isCurrent = d.deviceId == _currentDeviceId;
    final bool hasLocation = d.locationCode.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isDark ? 2 : 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isCurrent ? primary.withOpacity(0.7) : (isDark ? Colors.white12 : Colors.black12),
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (hasLocation ? primary : Colors.orange).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                hasLocation ? Icons.location_on_rounded : Icons.location_off_rounded,
                color: hasLocation ? primary : Colors.orange,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          d.deviceName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                      if (isCurrent)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: primary.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'CURRENT',
                            style: TextStyle(color: primary, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.wifi, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        d.macAddress != null && d.macAddress!.isNotEmpty ? d.macAddress! : 'No MAC recorded',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(width: 12),
                      const Icon(Icons.business, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        d.siteCode,
                        style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: hasLocation ? primary.withOpacity(0.12) : Colors.orange.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      hasLocation
                          ? 'Location: ${d.locationCode}${d.warehouseCode != null ? ' (${d.warehouseCode})' : ''}'
                          : 'Pending Location Assignment',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: hasLocation ? primary : Colors.orange,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit Assignment',
              onPressed: () => _openAssignDialog(d),
            ),
          ],
        ),
      ),
    );
  }
}
