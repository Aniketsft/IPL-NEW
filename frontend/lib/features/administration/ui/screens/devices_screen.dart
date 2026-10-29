import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../../../core/config/api_config.dart';
import '../../../../core/secure_storage_service.dart';
import '../../../../core/services/device_info_service.dart';
import '../../../../core/widgets/industrial_module_layout.dart';
import '../../../logistics/data/local/local_database_helper.dart';

const Color _emeraldPrimary = Color(0xFF10B981);
const Color _emeraldAccent = Color(0xFF34D399);
const Color _emeraldDark = Color(0xFF047857);

class DeviceItem {
  final String deviceId;
  final String deviceName;
  final String? hardwareModel;
  final String siteCode;
  final String? warehouseCode;
  final String locationCode;
  final String? hepProfileId;
  final String? hepApiKey;
  final bool isLocked;
  final bool isLicensed;
  final String licenseStatus;
  final DateTime? licenseUpdatedAt;
  final String? licenseUpdatedBy;
  final String? assignedUserName;
  final bool isActive;
  final DateTime? updatedAt;
  final String? updatedBy;

  DeviceItem({
    required this.deviceId,
    required this.deviceName,
    this.hardwareModel,
    required this.siteCode,
    this.warehouseCode,
    required this.locationCode,
    this.hepProfileId,
    this.hepApiKey,
    this.isLocked = true,
    this.isLicensed = true,
    this.licenseStatus = 'VALID',
    this.licenseUpdatedAt,
    this.licenseUpdatedBy,
    this.assignedUserName,
    this.isActive = true,
    this.updatedAt,
    this.updatedBy,
  });

  factory DeviceItem.fromJson(Map<String, dynamic> json) {
    return DeviceItem(
      deviceId: json['deviceId']?.toString() ?? '',
      deviceName: json['deviceName']?.toString() ?? json['deviceId']?.toString() ?? '',
      hardwareModel: json['hardwareModel']?.toString(),
      siteCode: json['siteCode']?.toString() ?? '',
      warehouseCode: json['warehouseCode']?.toString(),
      locationCode: json['locationCode']?.toString() ?? '',
      hepProfileId: json['hepProfileId']?.toString(),
      hepApiKey: json['hepApiKey']?.toString(),
      isLocked: json['isLocked'] == null ? true : (json['isLocked'] is bool ? json['isLocked'] : json['isLocked'] == 1),
      isLicensed: json['isLicensed'] == null ? true : (json['isLicensed'] is bool ? json['isLicensed'] : json['isLicensed'] == 1),
      licenseStatus: json['licenseStatus']?.toString() ?? 'VALID',
      licenseUpdatedAt: json['licenseUpdatedAt'] != null ? DateTime.tryParse(json['licenseUpdatedAt'].toString()) : null,
      licenseUpdatedBy: json['licenseUpdatedBy']?.toString(),
      assignedUserName: json['assignedUserName']?.toString(),
      isActive: json['isActive'] == null ? true : (json['isActive'] is bool ? json['isActive'] : json['isActive'] == 1),
      updatedAt: json['updatedAt'] != null ? DateTime.tryParse(json['updatedAt'].toString()) : null,
      updatedBy: json['updatedBy']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'hardwareModel': hardwareModel,
      'siteCode': siteCode,
      'warehouseCode': warehouseCode,
      'locationCode': locationCode,
      'hepProfileId': hepProfileId,
      'hepApiKey': hepApiKey,
      'isLocked': isLocked ? 1 : 0,
      'isLicensed': isLicensed ? 1 : 0,
      'licenseStatus': licenseStatus,
      'licenseUpdatedAt': licenseUpdatedAt?.toIso8601String(),
      'licenseUpdatedBy': licenseUpdatedBy,
      'assignedUserName': assignedUserName,
      'isActive': isActive ? 1 : 0,
      'updatedAt': updatedAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
      'updatedBy': updatedBy ?? 'APP',
    };
  }

  DeviceItem copyWith({
    String? deviceId,
    String? deviceName,
    String? hardwareModel,
    String? siteCode,
    String? warehouseCode,
    String? locationCode,
    String? hepProfileId,
    String? hepApiKey,
    bool? isLocked,
    bool? isLicensed,
    String? licenseStatus,
    DateTime? licenseUpdatedAt,
    String? licenseUpdatedBy,
    String? assignedUserName,
    bool? isActive,
    DateTime? updatedAt,
    String? updatedBy,
  }) {
    return DeviceItem(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      hardwareModel: hardwareModel ?? this.hardwareModel,
      siteCode: siteCode ?? this.siteCode,
      warehouseCode: warehouseCode ?? this.warehouseCode,
      locationCode: locationCode ?? this.locationCode,
      hepProfileId: hepProfileId ?? this.hepProfileId,
      hepApiKey: hepApiKey ?? this.hepApiKey,
      isLocked: isLocked ?? this.isLocked,
      isLicensed: isLicensed ?? this.isLicensed,
      licenseStatus: licenseStatus ?? this.licenseStatus,
      licenseUpdatedAt: licenseUpdatedAt ?? this.licenseUpdatedAt,
      licenseUpdatedBy: licenseUpdatedBy ?? this.licenseUpdatedBy,
      assignedUserName: assignedUserName ?? this.assignedUserName,
      isActive: isActive ?? this.isActive,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }
}

class LorryOption {
  final String location;
  final String? plateNumber;
  final String? warehouse;
  final String? warehouseName;
  final String? locationType;
  final String description;

  LorryOption({
    required this.location,
    this.plateNumber,
    this.warehouse,
    this.warehouseName,
    this.locationType,
    required this.description,
  });

  factory LorryOption.fromJson(Map<String, dynamic> json) {
    final loc = json['location']?.toString() ?? '';
    final plate = json['plateNumber']?.toString();
    final wrh = json['warehouse']?.toString();
    final wrhName = json['warehouseName']?.toString();
    final type = json['locationType']?.toString();
    final desc = json['description']?.toString() ??
        (plate != null && plate.isNotEmpty ? '$loc • $plate' : '$loc (${wrhName ?? wrh ?? ''})');
    return LorryOption(
      location: loc,
      plateNumber: plate,
      warehouse: wrh,
      warehouseName: wrhName,
      locationType: type,
      description: desc,
    );
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
  List<LorryOption> _availableLorries = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _userSiteCode = 'POD';
  String _currentUsername = '';
  bool _isAdminUser = false;

  // Active tablet identity state
  String _currentDeviceId = '';
  String _currentDeviceName = '';
  String _currentHardwareModel = '';
  String? _currentDeviceLocation;
  String? _currentWarehouse;
  String? _currentHepProfileId;
  String? _currentHepApiKey;
  bool _currentIsLicensed = true;
  String _currentLicenseStatus = 'VALID';
  bool _currentIsLocked = true;

  // HEP editing unlock state
  bool _isAdminUnlocked = false;
  bool _showApiKey = false;
  late TextEditingController _hepProfileController;
  late TextEditingController _hepApiKeyController;
  late TextEditingController _deviceNameController;

  // Fleet Filter: 'ALL', 'LICENSED', 'UNLICENSED'
  String _fleetFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _initDeviceIdentity();
    _hepProfileController = TextEditingController(text: _currentHepProfileId ?? '');
    _hepApiKeyController = TextEditingController(text: _currentHepApiKey ?? '');
    _deviceNameController = TextEditingController(text: _currentDeviceName);
    _loadInitialData();
  }

  @override
  void dispose() {
    _hepProfileController.dispose();
    _hepApiKeyController.dispose();
    _deviceNameController.dispose();
    super.dispose();
  }

  void _initDeviceIdentity() {
    final devService = DeviceInfoService.instance;
    _currentDeviceId = devService.deviceId;
    _currentDeviceName = devService.deviceName;
    _currentHardwareModel = devService.hardwareModel;
    _currentDeviceLocation = devService.assignedLocation;
    _currentWarehouse = devService.assignedWarehouse;
    _currentHepProfileId = devService.hepProfileId;
    _currentHepApiKey = devService.hepApiKey;
    _currentIsLicensed = devService.isLicensed;
    _currentLicenseStatus = devService.licenseStatus;
    _currentIsLocked = devService.isLocked;
  }

  Future<void> _loadInitialData() async {
    final site = await _storage.getSiteCode() ?? 'POD';
    final user = await _storage.getUsername() ?? '';
    final token = await _storage.getToken();

    bool admin = false;
    if (user.toLowerCase() == 'admin' || user.toLowerCase() == 'superadmin') {
      admin = true;
    } else if (token != null) {
      try {
        final parts = token.split('.');
        if (parts.length == 3) {
          final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
          if (payload is Map<String, dynamic>) {
            final roles = payload['role'] ?? payload['http://schemas.microsoft.com/ws/2008/06/identity/claims/role'];
            final permissions = payload['permission'];
            if (roles != null && (roles.toString().contains('Admin') || roles.toString().contains('SuperAdmin'))) {
              admin = true;
            }
            if (permissions != null && permissions.toString().contains('administration.devices.write')) {
              admin = true;
            }
          }
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _userSiteCode = site;
        _currentUsername = user;
        _isAdminUser = admin;
      });
    }

    // 1. Purge any legacy non-UUID records
    await _db.purgeLegacyDeviceIds();

    // 2. Load lorries for this site from SQLite / API
    await _loadSiteLorries(site);

    // 3. Load cached devices from SQLite
    await _loadFromLocalDb();

    // 4. Sync online with backend (heartbeat + device list)
    await _syncOnlineWithBackend();
  }

  Future<void> _loadSiteLorries(String site) async {
    final siteKey = site.trim().toUpperCase();

    // 1. Immediately read from local SQLite tbl_locations (exact Delivery query)
    try {
      var locs = await _db.getLorryLocations(siteCode: siteKey);
      if (locs.isEmpty) {
        // Fallback to broader location query if specific lorry filter returns empty
        locs = await _db.getLocations(siteCode: siteKey);
      }

      if (locs.isNotEmpty && mounted) {
        final lorries = locs
            .where((l) {
              final loc = (l['location'] ?? '').toString();
              return !loc.contains('DAM') && !loc.contains('SCRAP') && !loc.contains('RETURN') && !loc.contains('REJ') && !loc.contains('QUAR');
            })
            .map((l) {
              final loc = l['location']?.toString() ?? '';
              final wrh = l['warehouse']?.toString();
              final wrhName = l['warehouseName']?.toString();
              final type = l['locationType']?.toString();
              final typeName = l['locationTypeName']?.toString();
              final plate = (typeName != null && typeName.isNotEmpty && !typeName.contains('DAM') && !typeName.contains('SCRAP') && !typeName.contains('RETURN')) ? typeName : null;
              final desc = plate != null ? '$loc • $plate' : '$loc (${wrhName ?? wrh ?? siteKey})';
              return LorryOption(
                location: loc,
                plateNumber: plate,
                warehouse: wrh,
                warehouseName: wrhName,
                locationType: type,
                description: desc,
              );
            }).toList();

        if (lorries.isNotEmpty && mounted) {
          setState(() {
            _availableLorries = lorries;
          });
        }
      }
    } catch (e) {
      debugPrint('Error reading lorries from SQLite tbl_locations: $e');
    }

    // 2. Online background fetch & SQLite caching: update tbl_locations with fresh ERP fleet
    try {
      final token = await _storage.getToken();
      final url = Uri.parse('${ApiConfig.baseUrl}Devices/site-lorries?site=$siteKey');
      final resp = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
          'X-Device-Id': _currentDeviceId,
        },
      ).timeout(const Duration(seconds: 4));

      if (resp.statusCode == 200 && resp.body.trim().isNotEmpty) {
        final List<dynamic> list = jsonDecode(resp.body);
        if (list.isNotEmpty) {
          // Persist directly into SQLite tbl_locations
          await _db.saveLocations(list, siteCode: siteKey);

          // Re-query SQLite to ensure local database remains the single source of truth
          final freshRows = await _db.getLorryLocations(siteCode: siteKey);
          final freshLorries = freshRows
              .where((l) {
                final loc = (l['location'] ?? '').toString();
                return !loc.contains('DAM') && !loc.contains('SCRAP') && !loc.contains('RETURN');
              })
              .map((l) {
                final loc = l['location']?.toString() ?? '';
                final wrh = l['warehouse']?.toString();
                final wrhName = l['warehouseName']?.toString();
                final type = l['locationType']?.toString();
                final typeName = l['locationTypeName']?.toString();
                final plate = (typeName != null && typeName.isNotEmpty && !typeName.contains('DAM') && !typeName.contains('SCRAP')) ? typeName : null;
                final desc = plate != null ? '$loc • $plate' : '$loc (${wrhName ?? wrh ?? siteKey})';
                return LorryOption(
                  location: loc,
                  plateNumber: plate,
                  warehouse: wrh,
                  warehouseName: wrhName,
                  locationType: type,
                  description: desc,
                );
              }).toList();

          if (freshLorries.isNotEmpty && mounted) {
            setState(() {
              _availableLorries = freshLorries;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Background live lorry sync skipped: $e');
    }
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
        _syncCurrentDeviceFromList(list);
      }
    } catch (e) {
      debugPrint('Error loading devices from SQLite: $e');
    }
  }

  void _syncCurrentDeviceFromList(List<DeviceItem> list) {
    DeviceItem? match;
    if (DeviceInfoService.isValidUuid(_currentDeviceId)) {
      match = list.where((d) => d.deviceId.toLowerCase() == _currentDeviceId.toLowerCase()).firstOrNull;
    }

    match ??= list.where((d) =>
      (d.deviceName.isNotEmpty && d.deviceName == _currentDeviceName) ||
      (d.hardwareModel != null && d.hardwareModel == _currentHardwareModel) ||
      (d.deviceName == _currentHardwareModel)
    ).firstOrNull;

    if (match != null && match.deviceId.isNotEmpty) {
      final realUuid = match.deviceId.toLowerCase();
      setState(() {
        _currentDeviceId = realUuid;
        _currentDeviceName = match!.deviceName;
        _currentDeviceLocation = match.locationCode;
        _currentWarehouse = match.warehouseCode;
        _currentHepProfileId = match.hepProfileId;
        _currentHepApiKey = match.hepApiKey;
        _currentIsLicensed = match.isLicensed;
        _currentLicenseStatus = match.licenseStatus;
        _currentIsLocked = match.isLocked;

        _hepProfileController.text = match.hepProfileId ?? '';
        _hepApiKeyController.text = match.hepApiKey ?? '';
        _deviceNameController.text = match.deviceName;
      });

      if (DeviceInfoService.isValidUuid(realUuid)) {
        DeviceInfoService.instance.setDeviceIdentity(
          uuid: realUuid,
          name: match.deviceName,
          siteCode: match.siteCode,
          warehouseCode: match.warehouseCode,
          locationCode: match.locationCode,
          hepProfileId: match.hepProfileId,
          hepApiKey: match.hepApiKey,
          isLicensed: match.isLicensed,
          licenseStatus: match.licenseStatus,
          isLocked: match.isLocked,
        );
      }
    }
  }

  Future<void> _syncOnlineWithBackend() async {
    try {
      final token = await _storage.getToken();

      // 1. Trigger Heartbeat for calling device
      try {
        final hbUrl = Uri.parse('${ApiConfig.baseUrl}Devices/heartbeat');
        final hbResp = await http.post(
          hbUrl,
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
            'X-Device-Id': _currentDeviceId,
          },
          body: jsonEncode({
            'deviceId': _currentDeviceId,
            'hardwareModel': _currentHardwareModel,
            'siteCode': _userSiteCode,
          }),
        ).timeout(const Duration(seconds: 4));

        if (hbResp.statusCode == 200 && hbResp.body.trim().isNotEmpty) {
          final data = jsonDecode(hbResp.body);
          final updatedItem = DeviceItem.fromJson(data);
          await _db.insertOrUpdateDeviceLocation(updatedItem.toMap());
          if (DeviceInfoService.isValidUuid(updatedItem.deviceId)) {
            final realUuid = updatedItem.deviceId.toLowerCase();
            if (mounted) {
              setState(() {
                _currentDeviceId = realUuid;
                _currentDeviceName = updatedItem.deviceName;
                _currentDeviceLocation = updatedItem.locationCode;
                _currentWarehouse = updatedItem.warehouseCode;
                _currentHepProfileId = updatedItem.hepProfileId;
                _currentHepApiKey = updatedItem.hepApiKey;
                _currentIsLicensed = updatedItem.isLicensed;
                _currentLicenseStatus = updatedItem.licenseStatus;
                _currentIsLocked = updatedItem.isLocked;
              });
            }
            await DeviceInfoService.instance.setDeviceIdentity(
              uuid: realUuid,
              name: updatedItem.deviceName,
              siteCode: updatedItem.siteCode,
              warehouseCode: updatedItem.warehouseCode,
              locationCode: updatedItem.locationCode,
              hepProfileId: updatedItem.hepProfileId,
              hepApiKey: updatedItem.hepApiKey,
              isLicensed: updatedItem.isLicensed,
              licenseStatus: updatedItem.licenseStatus,
              isLocked: updatedItem.isLocked,
            );
          }
        }
      } catch (_) {}

      // 2. Fetch full Site Fleet
      final url = Uri.parse('${ApiConfig.baseUrl}Devices?site=$_userSiteCode');
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
          'X-Device-Id': _currentDeviceId,
        },
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final onlineList = data.map((e) => DeviceItem.fromJson(e)).toList();

        await _db.saveDeviceLocationsBatch(onlineList.map((d) => d.toMap()).toList());

        if (mounted) {
          setState(() {
            _devices = onlineList;
            _applyFilter();
            _isLoading = false;
          });
          _syncCurrentDeviceFromList(onlineList);
        }
      } else {
        if (_devices.isEmpty && mounted) {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      debugPrint('Devices online sync failed (using local SQLite cache): $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilter() {
    List<DeviceItem> filtered = List.from(_devices);

    // Apply status filter
    if (_fleetFilter == 'LICENSED') {
      filtered = filtered.where((d) => d.isLicensed).toList();
    } else if (_fleetFilter == 'UNLICENSED') {
      filtered = filtered.where((d) => !d.isLicensed).toList();
    }

    // Apply search query
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      filtered = filtered.where((d) {
        return d.deviceName.toLowerCase().contains(q) ||
            d.deviceId.toLowerCase().contains(q) ||
            d.locationCode.toLowerCase().contains(q) ||
            (d.hardwareModel?.toLowerCase().contains(q) ?? false) ||
            (d.assignedUserName?.toLowerCase().contains(q) ?? false);
      }).toList();
    }

    setState(() {
      _filteredDevices = filtered;
    });
  }

  // --- ACTIONS ---

  /// Field Operator / Driver Lorry Switch
  Future<void> _updateLorryLocation(String newLocation, String? warehouse) async {
    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);

    // 1. Immediately update SQLite
    final currentDev = _devices.firstWhere(
      (d) => d.deviceId == _currentDeviceId,
      orElse: () => DeviceItem(
        deviceId: _currentDeviceId,
        deviceName: _currentDeviceName,
        siteCode: _userSiteCode,
        locationCode: newLocation,
        warehouseCode: warehouse,
      ),
    );

    final updated = currentDev.copyWith(
      locationCode: newLocation,
      warehouseCode: warehouse,
      updatedAt: DateTime.now(),
    );

    await _db.insertOrUpdateDeviceLocation(updated.toMap());
    await DeviceInfoService.instance.setAssignedLocation(
      siteCode: _userSiteCode,
      warehouseCode: warehouse,
      locationCode: newLocation,
    );

    setState(() {
      _currentDeviceLocation = newLocation;
      _currentWarehouse = warehouse;
    });

    // 2. Sync to Backend
    try {
      final token = await _storage.getToken();
      final encodedId = Uri.encodeComponent(_currentDeviceId);
      final url = Uri.parse('${ApiConfig.baseUrl}Devices/$encodedId/location');
      final resp = await http.put(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
          'X-Device-Id': _currentDeviceId,
        },
        body: jsonEncode({
          'locationCode': newLocation,
          'warehouseCode': warehouse,
        }),
      ).timeout(const Duration(seconds: 6));

      if (resp.statusCode == 200 && resp.body.trim().isNotEmpty) {
        final saved = DeviceItem.fromJson(jsonDecode(resp.body));
        await _db.insertOrUpdateDeviceLocation(saved.toMap());
        _syncCurrentDeviceFromList([saved]);
      }
    } catch (e) {
      debugPrint('Lorry location online sync deferred (saved offline in SQLite): $e');
    }

    await _loadFromLocalDb();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('Lorry assigned to: $newLocation (${warehouse ?? _userSiteCode})')),
            ],
          ),
          backgroundColor: Colors.teal.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Toggle License (Admin Only)
  Future<void> _toggleDeviceLicense(String targetDeviceId, bool currentVal) async {
    HapticFeedback.heavyImpact();

    if (!_isAdminUser) {
      _showAdminAuthPrompt(
        title: 'Admin Verification Required',
        message: 'Only authorized administrators can validate or revoke device operational licenses.',
        onSuccess: () => _executeLicenseToggle(targetDeviceId, !currentVal),
      );
      return;
    }

    await _executeLicenseToggle(targetDeviceId, !currentVal);
  }

  Future<void> _executeLicenseToggle(String targetDeviceId, bool newVal) async {
    setState(() => _isLoading = true);

    try {
      final token = await _storage.getToken();
      final encodedTargetId = Uri.encodeComponent(targetDeviceId);
      final url = Uri.parse('${ApiConfig.baseUrl}Devices/$encodedTargetId/toggle-license');
      final resp = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
          'X-Device-Id': _currentDeviceId,
        },
        body: jsonEncode({
          'isLicensed': newVal,
          'licenseStatus': newVal ? 'VALID' : 'UNVALIDATED',
        }),
      ).timeout(const Duration(seconds: 6));

      if (resp.statusCode == 200 && resp.body.trim().isNotEmpty) {
        final updated = DeviceItem.fromJson(jsonDecode(resp.body));
        await _db.insertOrUpdateDeviceLocation(updated.toMap());

        if (targetDeviceId == _currentDeviceId) {
          await DeviceInfoService.instance.setLicenseStatus(
            isLicensed: updated.isLicensed,
            status: updated.licenseStatus,
          );
          setState(() {
            _currentIsLicensed = updated.isLicensed;
            _currentLicenseStatus = updated.licenseStatus;
          });
        }

        await _loadFromLocalDb();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                newVal
                    ? 'Device license VALIDATED successfully.'
                    : 'Device license marked as UNVALIDATED.',
              ),
              backgroundColor: newVal ? _emeraldPrimary : Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        String msg = 'Failed to toggle license (Status: ${resp.statusCode}).';
        if (resp.body.trim().isNotEmpty) {
          try {
            final err = jsonDecode(resp.body);
            if (err is Map<String, dynamic> && err['message'] != null) {
              msg = err['message'].toString();
            }
          } catch (_) {
            msg = resp.body.trim();
          }
        }
        _showErrorSnackBar(msg);
      }
    } catch (e) {
      _showErrorSnackBar('Network error updating license: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Save Admin Configuration (DeviceName, HEP credentials, Lock State)
  Future<void> _saveAdminConfig() async {
    final newName = _deviceNameController.text.trim();
    final newHepId = _hepProfileController.text.trim();
    final newHepKey = _hepApiKeyController.text.trim();

    if (newName.isEmpty) {
      _showErrorSnackBar('Device Name cannot be empty.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final token = await _storage.getToken();
      final encodedId = Uri.encodeComponent(_currentDeviceId);
      final url = Uri.parse('${ApiConfig.baseUrl}Devices/$encodedId/admin-config');
      final resp = await http.put(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
          'X-Device-Id': _currentDeviceId,
        },
        body: jsonEncode({
          'deviceName': newName,
          'siteCode': _userSiteCode,
          'hepProfileId': newHepId.isNotEmpty ? newHepId : null,
          'hepApiKey': newHepKey.isNotEmpty ? newHepKey : null,
          'isLocked': true, // Auto re-lock after saving
        }),
      ).timeout(const Duration(seconds: 6));

      if (resp.statusCode == 200 && resp.body.trim().isNotEmpty) {
        final saved = DeviceItem.fromJson(jsonDecode(resp.body));
        await _db.insertOrUpdateDeviceLocation(saved.toMap());

        await DeviceInfoService.instance.setDeviceIdentity(
          uuid: saved.deviceId,
          name: saved.deviceName,
          siteCode: saved.siteCode,
          warehouseCode: saved.warehouseCode,
          locationCode: saved.locationCode,
          hepProfileId: saved.hepProfileId,
          hepApiKey: saved.hepApiKey,
          isLicensed: saved.isLicensed,
          licenseStatus: saved.licenseStatus,
          isLocked: saved.isLocked,
        );

        setState(() {
          _currentDeviceName = saved.deviceName;
          _currentHepProfileId = saved.hepProfileId;
          _currentHepApiKey = saved.hepApiKey;
          _currentIsLocked = true;
          _isAdminUnlocked = false;
        });

        await _loadFromLocalDb();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Configuration saved securely & device re-locked.'),
              backgroundColor: Colors.teal.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        String msg = 'Failed to save admin configuration (Status: ${resp.statusCode}).';
        if (resp.body.trim().isNotEmpty) {
          try {
            final err = jsonDecode(resp.body);
            if (err is Map<String, dynamic> && err['message'] != null) {
              msg = err['message'].toString();
            }
          } catch (_) {
            msg = resp.body.trim();
          }
        } else if (resp.statusCode == 403) {
          msg = 'Access denied (403): Administrator privileges required.';
        } else if (resp.statusCode == 409) {
          msg = 'Device Name already in use. Please enter a unique name.';
        }
        _showErrorSnackBar(msg);
      }
    } catch (e) {
      _showErrorSnackBar('Network error saving configuration: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Provision a Brand New Tablet
  void _openProvisionDialog() {
    final nameCtrl = TextEditingController();
    String? selectedLorry = _availableLorries.isNotEmpty ? _availableLorries.first.location : null;
    String? selectedWarehouse = _availableLorries.isNotEmpty ? _availableLorries.first.warehouse : null;
    final hepProfileCtrl = TextEditingController();
    final hepKeyCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          final theme = Theme.of(context);
          final isDark = theme.brightness == Brightness.dark;
          final primary = theme.primaryColor;

          return Container(
            padding: EdgeInsets.only(
              top: 24,
              left: 20,
              right: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border.all(color: isDark ? Colors.white12 : Colors.black12, width: 1.0),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.add_to_queue_rounded, color: primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'PROVISION NEW TABLET',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                            ),
                            Text(
                              'Server will issue backend UUID • Site: $_userSiteCode',
                              style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  Divider(height: 24, color: isDark ? Colors.white12 : Colors.black12),

                  // Tablet Name (Must be Unique)
                  Text('TABLET NAME (MUST BE UNIQUE)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? Colors.white60 : Colors.black54)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tablet Name *',
                      hintText: 'e.g. LORRY-04-TABLET',
                      prefixIcon: Icon(Icons.tablet_android_rounded),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Lorry Selection
                  Text('ASSIGN LORRY LOCATION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? Colors.white60 : Colors.black54)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: selectedLorry,
                    decoration: const InputDecoration(
                      labelText: 'Lorry / Location *',
                      prefixIcon: Icon(Icons.local_shipping_outlined),
                    ),
                    items: _availableLorries.map((lorry) {
                      return DropdownMenuItem<String>(
                        value: lorry.location,
                        child: Text(lorry.description, style: const TextStyle(fontSize: 14)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setModalState(() {
                        selectedLorry = val;
                        final match = _availableLorries.firstWhere((l) => l.location == val, orElse: () => _availableLorries.first);
                        selectedWarehouse = match.warehouse;
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  // EBS - HEP Credentials Section (Optional on provision)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF161616) : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.vpn_key_rounded, size: 16, color: primary),
                            const SizedBox(width: 6),
                            Text(
                              'EBS — HEP SOFTWARE SETTINGS (OPTIONAL)',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: hepProfileCtrl,
                          decoration: const InputDecoration(
                            labelText: 'HEP Profile ID',
                            hintText: 'e.g. HEP-POD-04',
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: hepKeyCtrl,
                          decoration: const InputDecoration(
                            labelText: 'HEP API Key',
                            hintText: 'Enter API Key',
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.check_circle_rounded),
                      label: const Text(
                        'PROVISION & GENERATE UUID',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      onPressed: () async {
                        final name = nameCtrl.text.trim();
                        if (name.isEmpty) {
                          _showErrorSnackBar('Tablet Name is required.');
                          return;
                        }
                        if (selectedLorry == null || selectedLorry!.isEmpty) {
                          _showErrorSnackBar('Please select an assigned Lorry.');
                          return;
                        }

                        Navigator.pop(ctx);
                        await _executeProvisioning(
                          deviceName: name,
                          lorryLocation: selectedLorry!,
                          warehouse: selectedWarehouse,
                          hepProfileId: hepProfileCtrl.text.trim().isNotEmpty ? hepProfileCtrl.text.trim() : null,
                          hepApiKey: hepKeyCtrl.text.trim().isNotEmpty ? hepKeyCtrl.text.trim() : null,
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

  Future<void> _executeProvisioning({
    required String deviceName,
    required String lorryLocation,
    String? warehouse,
    String? hepProfileId,
    String? hepApiKey,
  }) async {
    setState(() => _isLoading = true);

    try {
      final token = await _storage.getToken();
      final url = Uri.parse('${ApiConfig.baseUrl}Devices/provision');
      final resp = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
          'X-Device-Id': _currentDeviceId,
        },
        body: jsonEncode({
          'deviceName': deviceName,
          'hardwareModel': _currentHardwareModel,
          'siteCode': _userSiteCode,
          'locationCode': lorryLocation,
          'warehouseCode': warehouse,
          'hepProfileId': hepProfileId,
          'hepApiKey': hepApiKey,
        }),
      ).timeout(const Duration(seconds: 8));

      if (resp.statusCode == 201 || resp.statusCode == 200) {
        final newDevice = DeviceItem.fromJson(jsonDecode(resp.body));
        await _db.insertOrUpdateDeviceLocation(newDevice.toMap());

        // Assign to this tablet
        await DeviceInfoService.instance.setDeviceIdentity(
          uuid: newDevice.deviceId,
          name: newDevice.deviceName,
          siteCode: newDevice.siteCode,
          warehouseCode: newDevice.warehouseCode,
          locationCode: newDevice.locationCode,
          hepProfileId: newDevice.hepProfileId,
          hepApiKey: newDevice.hepApiKey,
          isLicensed: newDevice.isLicensed,
          licenseStatus: newDevice.licenseStatus,
          isLocked: newDevice.isLocked,
        );

        setState(() {
          _currentDeviceId = newDevice.deviceId;
          _currentDeviceName = newDevice.deviceName;
          _currentDeviceLocation = newDevice.locationCode;
          _currentWarehouse = newDevice.warehouseCode;
          _currentHepProfileId = newDevice.hepProfileId;
          _currentHepApiKey = newDevice.hepApiKey;
          _currentIsLicensed = newDevice.isLicensed;
          _currentLicenseStatus = newDevice.licenseStatus;
          _currentIsLocked = true;
          _isAdminUnlocked = false;

          _deviceNameController.text = newDevice.deviceName;
          _hepProfileController.text = newDevice.hepProfileId ?? '';
          _hepApiKeyController.text = newDevice.hepApiKey ?? '';
        });

        await _syncOnlineWithBackend();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Tablet "$deviceName" provisioned with UUID: ${newDevice.deviceId}'),
              backgroundColor: Colors.teal.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else if (resp.statusCode == 409) {
        final err = jsonDecode(resp.body);
        _showErrorSnackBar(err['message'] ?? 'Device Name already exists in system.');
      } else {
        final err = jsonDecode(resp.body);
        _showErrorSnackBar(err['message'] ?? 'Provisioning failed.');
      }
    } catch (e) {
      _showErrorSnackBar('Network error during provisioning: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAdminAuthPrompt({
    required String title,
    required String message,
    required VoidCallback onSuccess,
  }) {
    final passwordCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.admin_panel_settings_rounded, color: Colors.amber),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: const TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 16),
            TextField(
              controller: passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Administrator Password',
                prefixIcon: Icon(Icons.lock_outline),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () async {
              final pwd = passwordCtrl.text.trim();
              if (pwd.isEmpty) return;

              // Validate with backend login endpoint or admin check
              Navigator.pop(dCtx);
              final valid = await _verifyAdminPassword(pwd);
              if (valid) {
                onSuccess();
              } else {
                _showErrorSnackBar('Invalid administrator credentials.');
              }
            },
            child: const Text('UNLOCK'),
          ),
        ],
      ),
    );
  }

  Future<bool> _verifyAdminPassword(String password) async {
    try {
      final url = Uri.parse('${ApiConfig.baseUrl}Auth/login');
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': 'admin',
          'password': password,
        }),
      ).timeout(const Duration(seconds: 4));

      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void _showErrorSnackBar(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // --- BUILD UI ---

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.primaryColor;

    final licensedCount = _devices.where((d) => d.isLicensed).length;
    final unlicensedCount = _devices.where((d) => !d.isLicensed).length;

    return IndustrialModuleLayout(
      title: 'Tablet Fleet',
      extraActions: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? theme.cardColor : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.business_rounded, size: 13, color: primary),
              const SizedBox(width: 5),
              Text(
                _userSiteCode,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        if (_isAdminUser) ...[
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.add_to_queue_rounded, size: 20),
            tooltip: 'Provision New Tablet',
            onPressed: _openProvisionDialog,
          ),
        ],
        const SizedBox(width: 6),
      ],
      body: RefreshIndicator(
        onRefresh: _syncOnlineWithBackend,
        color: primary,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // 1. License Status Banner (Top Sticky Ribbon)
            _buildLicenseStatusBar(theme, isDark),
            const SizedBox(height: 14),

            // 2. This Handheld Tablet Hero Card
            _buildHeroIdentityCard(theme, isDark, primary),
            const SizedBox(height: 14),

            // 3. Active Lorry Assignment Card (Driver & Field User Accessible)
            _buildLorryAssignmentCard(theme, isDark, primary),
            const SizedBox(height: 14),

            // 4. EBS — HEP Software Credentials Card (Locked by Default)
            _buildHepSoftwareCard(theme, isDark, primary),
            const SizedBox(height: 20),

            // 5. Fleet Section Header & Filter Controls
            _buildFleetHeader(theme, isDark, primary, licensedCount, unlicensedCount),
            const SizedBox(height: 12),

            // 6. Fleet Search Bar
            _buildFleetSearchBar(theme, isDark),
            const SizedBox(height: 12),

            // 7. Site Devices List (40+ tablets)
            if (_isLoading && _devices.isEmpty)
              Padding(
                padding: const EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator(color: primary)),
              )
            else if (_filteredDevices.isEmpty)
              _buildEmptyFleetState(theme, isDark, primary)
            else
              ..._filteredDevices.map((d) => _buildFleetDeviceCard(d, theme, isDark, primary)),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // --- WIDGET COMPONENTS ---

  /// Section 1: Top License Status Bar (Theme Standard)
  Widget _buildLicenseStatusBar(ThemeData theme, bool isDark) {
    final bool isLic = _currentIsLicensed;
    final statusColor = isLic ? Colors.green : Colors.redAccent;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: statusColor.withOpacity(0.35),
          width: 1.0,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isLic ? Icons.verified_user_rounded : Icons.gpp_bad_rounded,
              color: statusColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Text(
                      isLic ? 'DEVICE LICENSED & OPERATIONAL' : 'DEVICE UNLICENSED',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        color: statusColor,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _currentLicenseStatus,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  isLic
                      ? 'Operational license verified. ERP, billing, and sync active.'
                      : 'Privileges suspended. Admin toggle required to validate.',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch.adaptive(
                value: _currentIsLicensed,
                activeColor: Colors.green,
                inactiveThumbColor: Colors.redAccent,
                inactiveTrackColor: Colors.red.withOpacity(0.3),
                onChanged: (val) => _toggleDeviceLicense(_currentDeviceId, _currentIsLicensed),
              ),
              Text(
                'ADMIN',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white38 : Colors.black38,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Section 2: This Tablet Hero Card (Theme Standard)
  Widget _buildHeroIdentityCard(ThemeData theme, bool isDark, Color primary) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black12,
          width: 1.0,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.tablet_android_rounded, color: primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'THIS TABLET',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white70 : Colors.black54,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _currentIsLocked
                                ? Colors.amber.withOpacity(0.12)
                                : Colors.blue.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: _currentIsLocked
                                  ? Colors.amber.withOpacity(0.4)
                                  : Colors.blue.withOpacity(0.4),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _currentIsLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                                size: 10,
                                color: _currentIsLocked ? Colors.amber : Colors.blueAccent,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                _currentIsLocked ? 'LOCKED' : 'UNLOCKED',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: _currentIsLocked ? Colors.amber : Colors.blueAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _currentDeviceName.isNotEmpty ? _currentDeviceName : 'Unprovisioned Tablet',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _currentHardwareModel,
                      style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.black54),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (_isAdminUser)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? Colors.white70 : Colors.black87,
                    side: BorderSide(color: isDark ? Colors.white24 : Colors.black12),
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  ),
                  icon: const Icon(Icons.add_to_queue_rounded, size: 14),
                  label: const Text('Provision', style: TextStyle(fontSize: 11)),
                  onPressed: _openProvisionDialog,
                ),
            ],
          ),
          Divider(height: 20, color: isDark ? Colors.white12 : Colors.black12),

          // Monospace Backend UUID (Full untruncated 36 characters)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'BACKEND UUID',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white54 : Colors.black54,
                  letterSpacing: 0.8,
                ),
              ),
              if (DeviceInfoService.isValidUuid(_currentDeviceId))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'AUTHENTICATED',
                    style: TextStyle(color: Colors.green, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF161616) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: DeviceInfoService.isValidUuid(_currentDeviceId)
                    ? (isDark ? Colors.white12 : Colors.black12)
                    : Colors.amber.withOpacity(0.4),
                width: 1.0,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.fingerprint_rounded,
                  size: 16,
                  color: DeviceInfoService.isValidUuid(_currentDeviceId) ? primary : Colors.amber,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      DeviceInfoService.isValidUuid(_currentDeviceId)
                          ? _currentDeviceId.toLowerCase()
                          : 'Resolving Backend UUID...',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: DeviceInfoService.isValidUuid(_currentDeviceId)
                            ? (isDark ? Colors.white : Colors.black87)
                            : Colors.amber,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (DeviceInfoService.isValidUuid(_currentDeviceId))
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: _currentDeviceId.toLowerCase()));
                      HapticFeedback.selectionClick();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('UUID copied: ${_currentDeviceId.toLowerCase()}'),
                          duration: const Duration(seconds: 2),
                          backgroundColor: theme.cardColor,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.copy_rounded, size: 16, color: isDark ? Colors.white60 : Colors.black54),
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.sync_rounded, size: 16, color: Colors.amber),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Fetch UUID from Backend',
                    onPressed: _syncOnlineWithBackend,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Section 3: Lorry Assignment Card (Driver / Field User Accessible)
  Widget _buildLorryAssignmentCard(ThemeData theme, bool isDark, Color primary) {
    final bool hasLocation = _currentDeviceLocation != null && _currentDeviceLocation!.isNotEmpty;

    // Resolve vehicle registration plate number from cached lorries
    LorryOption? activeLorry;
    if (hasLocation) {
      for (final l in _availableLorries) {
        if (l.location.trim().toUpperCase() == _currentDeviceLocation!.trim().toUpperCase()) {
          activeLorry = l;
          break;
        }
      }
    }
    final bool hasPlate = activeLorry?.plateNumber != null && activeLorry!.plateNumber!.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black12,
          width: 1.0,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.local_shipping_rounded, color: primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ACTIVE LORRY & VEHICLE',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.6,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Field operators can freely change assigned delivery vehicle for this shift.',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Current Lorry Display & Selector
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF161616) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: hasLocation
                    ? (isDark ? Colors.white12 : Colors.black12)
                    : Colors.amber.withOpacity(0.5),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  hasLocation ? Icons.check_circle_rounded : Icons.pending_rounded,
                  color: hasLocation ? Colors.green : Colors.amber,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            hasLocation
                                ? 'Lorry ${activeLorry?.location ?? _currentDeviceLocation}'
                                : 'No Lorry Assigned',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: hasLocation
                                  ? (isDark ? Colors.white : Colors.black87)
                                  : Colors.amber,
                            ),
                          ),
                          if (hasPlate)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: primary.withOpacity(0.3),
                                ),
                              ),
                              child: Text(
                                activeLorry!.plateNumber!,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                  color: primary,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Warehouse: ${_currentWarehouse ?? activeLorry?.warehouse ?? "Default"} • Site: $_userSiteCode',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primary,
                    side: BorderSide(color: primary.withOpacity(0.5)),
                    backgroundColor: primary.withOpacity(0.06),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                  label: const Text('Change', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  onPressed: () => _showLorryPickerModal(context),
                ),
              ],
            ),
          ),

          // Quick Select Lorries
          if (_availableLorries.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'QUICK SELECT SITE VEHICLES:',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _availableLorries.map((l) {
                final isSelected =
                    l.location.trim().toUpperCase() == (_currentDeviceLocation ?? '').trim().toUpperCase();
                return InkWell(
                  onTap: () => _updateLorryLocation(l.location, l.warehouse),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? primary.withOpacity(0.15)
                          : (isDark ? const Color(0xFF161616) : Colors.grey.shade100),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? primary
                            : (isDark ? Colors.white12 : Colors.black12),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.local_shipping_rounded,
                          size: 13,
                          color: isSelected ? primary : (isDark ? Colors.white60 : Colors.black54),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          l.location,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? primary
                                : (isDark ? Colors.white : Colors.black87),
                          ),
                        ),
                        if (l.plateNumber != null && l.plateNumber!.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(
                            '•',
                            style: TextStyle(
                              fontSize: 11,
                              color: isSelected ? primary : (isDark ? Colors.white38 : Colors.black38),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            l.plateNumber!,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? primary
                                  : (isDark ? Colors.white70 : Colors.black54),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  void _showLorryPickerModal(BuildContext context) {
    if (_availableLorries.isEmpty) {
      _loadSiteLorries(_userSiteCode);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (pCtx) {
        String filter = '';
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final theme = Theme.of(context);
            final isDark = theme.brightness == Brightness.dark;
            final primary = theme.primaryColor;
            final q = filter.trim().toLowerCase();
            final filtered = q.isEmpty
                ? _availableLorries
                : _availableLorries.where((l) {
                    final loc = l.location.toLowerCase();
                    final desc = l.description.toLowerCase();
                    final plate = (l.plateNumber ?? '').toLowerCase();
                    return loc.contains(q) || desc.contains(q) || plate.contains(q);
                  }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.72,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.black12,
                  width: 1.0,
                ),
              ),
              child: Column(
                children: [
                  // Top Drag Handle
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.local_shipping_rounded, color: primary, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Select Site Vehicle (${_availableLorries.length})',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.refresh_rounded, size: 20),
                            tooltip: 'Reload from Server',
                            onPressed: () async {
                              await _loadSiteLorries(_userSiteCode);
                              setModalState(() {});
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20),
                            onPressed: () => Navigator.pop(pCtx),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search lorry code or plate number...',
                      prefixIcon: Icon(Icons.search, size: 18),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    onChanged: (val) => setModalState(() => filter = val),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.local_shipping_outlined, size: 36, color: Colors.grey),
                                const SizedBox(height: 8),
                                Text(
                                  'No matching vehicles found',
                                  style: TextStyle(color: isDark ? Colors.white60 : Colors.black54),
                                ),
                                const SizedBox(height: 12),
                                TextButton.icon(
                                  icon: const Icon(Icons.refresh_rounded, size: 16),
                                  label: const Text('Reset Vehicles'),
                                  onPressed: () async {
                                    await _loadSiteLorries(_userSiteCode);
                                    setModalState(() {
                                      filter = '';
                                    });
                                  },
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color: isDark ? Colors.white12 : Colors.black12,
                            ),
                            itemBuilder: (_, i) {
                              final item = filtered[i];
                              final isSelected =
                                  item.location.trim().toUpperCase() == (_currentDeviceLocation ?? '').trim().toUpperCase();
                              return ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? primary.withOpacity(0.15)
                                        : (isDark ? Colors.white10 : Colors.black.withOpacity(0.04)),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.local_shipping_rounded,
                                    color: isSelected ? primary : (isDark ? Colors.white60 : Colors.black54),
                                    size: 20,
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Text(
                                      'Lorry ${item.location}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: isSelected
                                            ? primary
                                            : (isDark ? Colors.white : Colors.black87),
                                      ),
                                    ),
                                    if (item.plateNumber != null && item.plateNumber!.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isDark ? Colors.white10 : Colors.grey.shade200,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          item.plateNumber!,
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                subtitle: Text(
                                  'Warehouse: ${item.warehouse ?? _userSiteCode}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? Colors.white54 : Colors.black54,
                                  ),
                                ),
                                trailing: isSelected
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: primary.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.check_circle_rounded, size: 14, color: primary),
                                          const SizedBox(width: 4),
                                          Text(
                                            'ACTIVE',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: primary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : Icon(
                                      Icons.chevron_right_rounded,
                                      size: 18,
                                      color: isDark ? Colors.white38 : Colors.black38,
                                    ),
                                onTap: () {
                                  Navigator.pop(pCtx);
                                  _updateLorryLocation(item.location, item.warehouse);
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

  /// Section 4: EBS — HEP Software Credentials Card (Locked by default)
  Widget _buildHepSoftwareCard(ThemeData theme, bool isDark, Color primary) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isAdminUnlocked
              ? primary.withOpacity(0.5)
              : (isDark ? Colors.white12 : Colors.black12),
          width: 1.0,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _isAdminUnlocked
                      ? primary.withOpacity(0.12)
                      : (isDark ? Colors.white10 : Colors.black.withOpacity(0.04)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.vpn_key_rounded,
                  color: _isAdminUnlocked ? primary : (isDark ? Colors.white60 : Colors.black54),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Text(
                          'EBS — HEP SOFTWARE CREDENTIALS',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.6,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: _isAdminUnlocked
                                ? primary.withOpacity(0.15)
                                : (isDark ? Colors.white10 : Colors.black.withOpacity(0.06)),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _isAdminUnlocked ? 'UNLOCKED' : 'LOCKED',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                              color: _isAdminUnlocked
                                  ? primary
                                  : (isDark ? Colors.white60 : Colors.black54),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Profile ID and API Key are locked against unauthorized field tampering.',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // If Unlocked: Device Name can also be edited
          if (_isAdminUnlocked) ...[
            TextField(
              controller: _deviceNameController,
              decoration: const InputDecoration(
                labelText: 'Tablet Name (Unique)',
                hintText: 'e.g. LORRY-04-TABLET',
                prefixIcon: Icon(Icons.badge_outlined, size: 20),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
          ],

          // HEP Profile ID
          TextField(
            controller: _hepProfileController,
            enabled: _isAdminUnlocked,
            decoration: const InputDecoration(
              labelText: 'HEP Profile ID',
              hintText: 'e.g. HEP-PROD-POD-01',
              prefixIcon: Icon(Icons.account_box_outlined, size: 20),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),

          // HEP API Key
          TextField(
            controller: _hepApiKeyController,
            enabled: _isAdminUnlocked,
            obscureText: !_showApiKey && !_isAdminUnlocked,
            decoration: InputDecoration(
              labelText: 'HEP API Key',
              hintText: _isAdminUnlocked ? 'Enter API Key' : '••••••••••••••••',
              prefixIcon: const Icon(Icons.key_rounded, size: 20),
              suffixIcon: IconButton(
                icon: Icon(_showApiKey ? Icons.visibility_off : Icons.visibility, size: 18),
                onPressed: () => setState(() => _showApiKey = !_showApiKey),
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),

          // Lock / Save Action Buttons
          if (!_isAdminUnlocked)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: primary,
                  side: BorderSide(color: primary, width: 1.2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.lock_open_rounded, size: 18),
                label: const Text(
                  'UNLOCK WITH ADMIN CREDENTIALS',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5),
                ),
                onPressed: () {
                  if (_isAdminUser) {
                    setState(() => _isAdminUnlocked = true);
                  } else {
                    _showAdminAuthPrompt(
                      title: 'Unlock Configuration',
                      message: 'Enter administrator credentials to edit Device Name and HEP Software keys.',
                      onSuccess: () => setState(() => _isAdminUnlocked = true),
                    );
                  }
                },
              ),
            )
          else
            Row(
              children: [
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => setState(() => _isAdminUnlocked = false),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.save_rounded, size: 18),
                    label: const Text(
                      'SAVE & RE-LOCK',
                      style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                    onPressed: _saveAdminConfig,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Section 5: Fleet Overview Header
  Widget _buildFleetHeader(ThemeData theme, bool isDark, Color primary, int licCount, int unlicCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'SITE TABLET FLEET (${_devices.length})',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.black54,
                letterSpacing: 0.8,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
              ),
              child: Text(
                'Isolated Site: $_userSiteCode',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  color: primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              FilterChip(
                selected: _fleetFilter == 'ALL',
                label: Text('All (${_devices.length})'),
                backgroundColor: theme.cardColor,
                selectedColor: primary.withOpacity(0.15),
                checkmarkColor: primary,
                side: BorderSide(
                  color: _fleetFilter == 'ALL'
                      ? primary
                      : (isDark ? Colors.white12 : Colors.black12),
                ),
                onSelected: (val) {
                  setState(() {
                    _fleetFilter = 'ALL';
                    _applyFilter();
                  });
                },
              ),
              const SizedBox(width: 8),
              FilterChip(
                selected: _fleetFilter == 'LICENSED',
                label: Text('Licensed ($licCount)'),
                selectedColor: Colors.green.withOpacity(0.15),
                backgroundColor: theme.cardColor,
                checkmarkColor: Colors.green,
                side: BorderSide(
                  color: _fleetFilter == 'LICENSED'
                      ? Colors.green
                      : (isDark ? Colors.white12 : Colors.black12),
                ),
                onSelected: (val) {
                  setState(() {
                    _fleetFilter = 'LICENSED';
                    _applyFilter();
                  });
                },
              ),
              const SizedBox(width: 8),
              FilterChip(
                selected: _fleetFilter == 'UNLICENSED',
                label: Text('Unlicensed ($unlicCount)'),
                selectedColor: Colors.redAccent.withOpacity(0.15),
                backgroundColor: theme.cardColor,
                checkmarkColor: Colors.redAccent,
                side: BorderSide(
                  color: _fleetFilter == 'UNLICENSED'
                      ? Colors.redAccent
                      : (isDark ? Colors.white12 : Colors.black12),
                ),
                onSelected: (val) {
                  setState(() {
                    _fleetFilter = 'UNLICENSED';
                    _applyFilter();
                  });
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Section 6: Fleet Search Bar
  Widget _buildFleetSearchBar(ThemeData theme, bool isDark) {
    return TextField(
      decoration: InputDecoration(
        hintText: 'Search tablet name, UUID, lorry code...',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () {
                  setState(() {
                    _searchQuery = '';
                    _applyFilter();
                  });
                },
              )
            : null,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      onChanged: (val) {
        setState(() {
          _searchQuery = val;
          _applyFilter();
        });
      },
    );
  }

  /// Section 7: Empty Fleet State
  Widget _buildEmptyFleetState(ThemeData theme, bool isDark, Color primary) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black12,
        ),
      ),
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(
            Icons.tablet_android_outlined,
            size: 40,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
          const SizedBox(height: 12),
          Text(
            'No matching tablets found for this site.',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Provision a new tablet using the header action above.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.white60 : Colors.black54,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: primary,
              side: BorderSide(color: primary),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.add_to_queue_rounded, size: 18),
            label: const Text('Provision Tablet', style: TextStyle(fontWeight: FontWeight.w600)),
            onPressed: _openProvisionDialog,
          ),
        ],
      ),
    );
  }

  /// Section 8: Single Fleet Device Card
  Widget _buildFleetDeviceCard(DeviceItem d, ThemeData theme, bool isDark, Color primary) {
    final bool isCurrent = d.deviceId == _currentDeviceId;
    final bool isLic = d.isLicensed;
    final bool hasLocation = d.locationCode.isNotEmpty;

    // Resolve vehicle registration plate number for this fleet device
    LorryOption? fleetLorry;
    if (hasLocation) {
      for (final l in _availableLorries) {
        if (l.location.trim().toUpperCase() == d.locationCode.trim().toUpperCase()) {
          fleetLorry = l;
          break;
        }
      }
    }
    final bool hasFleetPlate = fleetLorry?.plateNumber != null && fleetLorry!.plateNumber!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrent
              ? primary
              : (isLic
                  ? (isDark ? Colors.white12 : Colors.black12)
                  : Colors.redAccent.withOpacity(0.4)),
          width: isCurrent ? 1.5 : 1.0,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.tablet_android_rounded,
                  color: isLic ? primary : Colors.redAccent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            d.deviceName,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isCurrent)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: primary.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: primary.withOpacity(0.4)),
                            ),
                            child: Text(
                              'THIS TABLET',
                              style: TextStyle(
                                color: primary,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      d.hardwareModel ?? 'Android Tablet',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // License Badge & Toggle
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: (isLic ? Colors.green : Colors.redAccent).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: (isLic ? Colors.green : Colors.redAccent).withOpacity(0.4),
                      ),
                    ),
                    child: Text(
                      isLic ? 'VALID' : 'UNLICENSED',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        color: isLic ? Colors.green : Colors.redAccent,
                      ),
                    ),
                  ),
                  if (_isAdminUser)
                    Transform.scale(
                      scale: 0.75,
                      alignment: Alignment.centerRight,
                      child: Switch.adaptive(
                        value: d.isLicensed,
                        activeColor: Colors.green,
                        onChanged: (val) => _toggleDeviceLicense(d.deviceId, d.isLicensed),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(
            height: 1,
            color: isDark ? Colors.white12 : Colors.black12,
          ),
          const SizedBox(height: 10),

          // Metadata Row: Lorry and UUID
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF161616) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.black12,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.local_shipping_outlined,
                        size: 13,
                        color: hasLocation ? primary : Colors.amber,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          hasLocation ? 'Lorry ${d.locationCode}' : 'Pending Lorry',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: hasLocation
                                ? (isDark ? Colors.white : Colors.black87)
                                : Colors.amber,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasFleetPlate) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            fleetLorry!.plateNumber!,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: d.deviceId));
                  HapticFeedback.selectionClick();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('UUID copied: ${d.deviceId}'),
                      duration: const Duration(seconds: 2),
                      backgroundColor: theme.cardColor,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF161616) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.black12,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.fingerprint_rounded,
                        size: 13,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        d.deviceId.length > 8 ? '${d.deviceId.substring(0, 8)}...' : d.deviceId,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.copy_rounded,
                        size: 12,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
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


