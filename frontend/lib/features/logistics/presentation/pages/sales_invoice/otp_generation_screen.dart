import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../../core/widgets/industrial_module_layout.dart';

class OtpRecord {
  final String id;
  final String code;
  final String reason;
  final String customerCode;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String generatedBy;
  bool isRevoked;

  OtpRecord({
    required this.id,
    required this.code,
    required this.reason,
    required this.customerCode,
    required this.createdAt,
    required this.expiresAt,
    required this.generatedBy,
    this.isRevoked = false,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isActive => !isRevoked && !isExpired;

  Duration get remainingTime {
    final now = DateTime.now();
    if (now.isAfter(expiresAt)) return Duration.zero;
    return expiresAt.difference(now);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'reason': reason,
        'customerCode': customerCode,
        'createdAt': createdAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'generatedBy': generatedBy,
        'isRevoked': isRevoked,
      };

  factory OtpRecord.fromJson(Map<String, dynamic> json) => OtpRecord(
        id: json['id'] as String? ?? '',
        code: json['code'] as String? ?? '',
        reason: json['reason'] as String? ?? 'General Override',
        customerCode: json['customerCode'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? '') ??
            DateTime.now(),
        generatedBy: json['generatedBy'] as String? ?? 'Supervisor',
        isRevoked: json['isRevoked'] as bool? ?? false,
      );
}

class OtpGenerationScreen extends StatefulWidget {
  final String? initialCustomerCode;

  const OtpGenerationScreen({
    super.key,
    this.initialCustomerCode,
  });

  @override
  State<OtpGenerationScreen> createState() => _OtpGenerationScreenState();
}

class _OtpGenerationScreenState extends State<OtpGenerationScreen> {
  static const String _prefKey = 'sales_supervisor_generated_otps';

  final TextEditingController _customerController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  final List<String> _reasons = const [
    'Credit Limit Override',
    'Customer On HOLD',
    'Price / Margin Override',
    'Return Authorization',
    'Special Discount Override',
  ];

  late String _selectedReason;
  int _selectedDurationMinutes = 30; // 15, 30, 60, 480 (8h/EOD)

  List<OtpRecord> _history = [];
  OtpRecord? _currentActiveOtp;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _selectedReason = _reasons.first;
    if (widget.initialCustomerCode != null &&
        widget.initialCustomerCode!.isNotEmpty) {
      _customerController.text = widget.initialCustomerCode!;
    }
    _loadHistory();
    _startTicker();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _customerController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _startTicker() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_prefKey) ?? [];
      final list = raw
          .map((item) =>
              OtpRecord.fromJson(jsonDecode(item) as Map<String, dynamic>))
          .toList();

      // Sort newest first
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (mounted) {
        setState(() {
          _history = list;
          // Set current active if available
          final active = list.where((o) => o.isActive).toList();
          _currentActiveOtp = active.isNotEmpty ? active.first : null;
        });
      }
    } catch (e) {
      debugPrint('Error loading OTP history: $e');
    }
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = _history.map((o) => jsonEncode(o.toJson())).toList();
      await prefs.setStringList(_prefKey, raw);
    } catch (e) {
      debugPrint('Error saving OTP history: $e');
    }
  }

  void _generateNewOtp() {
    final rng = Random.secure();
    // 6 digit code between 100000 and 999999
    final code = (100000 + rng.nextInt(900000)).toString();

    final now = DateTime.now();
    DateTime expiry;
    if (_selectedDurationMinutes >= 480) {
      // End of day (23:59:59)
      expiry = DateTime(now.year, now.month, now.day, 23, 59, 59);
    } else {
      expiry = now.add(Duration(minutes: _selectedDurationMinutes));
    }

    final newOtp = OtpRecord(
      id: '${now.millisecondsSinceEpoch}_$code',
      code: code,
      reason: _selectedReason,
      customerCode: _customerController.text.trim().toUpperCase(),
      createdAt: now,
      expiresAt: expiry,
      generatedBy: 'Supervisor',
    );

    setState(() {
      _currentActiveOtp = newOtp;
      _history.insert(0, newOtp);
    });

    _saveHistory();

    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Generated OTP: $code for $_selectedReason'),
        backgroundColor: const Color(0xFF00B4D8),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _copyToClipboard(String code) {
    Clipboard.setData(ClipboardData(text: code));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text('OTP $code copied to clipboard!'),
          ],
        ),
        backgroundColor: const Color(0xFF2E7D32),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _revokeOtp(OtpRecord otp) {
    setState(() {
      otp.isRevoked = true;
      if (_currentActiveOtp?.id == otp.id) {
        _currentActiveOtp = null;
      }
    });
    _saveHistory();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('OTP has been revoked.'),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _clearExpired() {
    setState(() {
      _history.removeWhere((o) => !o.isActive);
    });
    _saveHistory();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Expired & revoked OTPs cleared.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.inSeconds <= 0) return 'Expired';
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes.toString().padLeft(2, '0')}m ${seconds.toString().padLeft(2, '0')}s';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return IndustrialModuleLayout(
      title: 'OTP Generation',
      extraActions: [
        if (_history.any((o) => !o.isActive))
          IconButton(
            tooltip: 'Clear Expired',
            icon: const Icon(Icons.cleaning_services_rounded, size: 20),
            onPressed: _clearExpired,
          ),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Description Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E2630) : const Color(0xFFE8F4FD),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF334E68)
                      : const Color(0xFFBEE3F8),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9F1C).withOpacity(0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.security_rounded,
                      color: Color(0xFFFF9F1C),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Supervisor Override Hub',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Generate short-lived authorization codes to bypass credit limits, customer holds, or locked prices in the field.',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white70 : Colors.black54,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Active / Generated OTP Card
            if (_currentActiveOtp != null && _currentActiveOtp!.isActive)
              _buildActiveOtpHeroCard(_currentActiveOtp!, isDark, theme)
            else
              _buildNoActiveOtpPlaceholder(isDark),

            const SizedBox(height: 20),

            // Configuration Section
            Text(
              'NEW OVERRIDE CONFIGURATION',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
            const SizedBox(height: 10),

            // Reason Selector Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E24) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Override Reason',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _selectedReason,
                    isExpanded: true,
                    dropdownColor: isDark ? const Color(0xFF26262E) : Colors.white,
                    decoration: InputDecoration(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      prefixIcon: const Icon(Icons.rule_rounded, size: 20),
                    ),
                    items: _reasons
                        .map((r) => DropdownMenuItem(
                              value: r,
                              child: Text(
                                r,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedReason = val);
                    },
                  ),
                  const SizedBox(height: 14),

                  // Target Customer Code (Optional)
                  Text(
                    'Target Customer (Optional)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _customerController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'e.g. CUST001 (Blank = Any customer)',
                      hintStyle: const TextStyle(fontSize: 12),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      prefixIcon:
                          const Icon(Icons.person_pin_circle_rounded, size: 20),
                      suffixIcon: _customerController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                setState(() => _customerController.clear());
                              },
                            )
                          : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 14),

                  // Duration Chips
                  Text(
                    'Validity Duration',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildDurationChip(15, '15 Minutes', isDark, theme),
                      _buildDurationChip(30, '30 Minutes', isDark, theme),
                      _buildDurationChip(60, '1 Hour', isDark, theme),
                      _buildDurationChip(480, 'Today (EOD)', isDark, theme),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Generate Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00B4D8),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.bolt_rounded, size: 22),
                      label: const Text(
                        'GENERATE SECURE OTP',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                      onPressed: _generateNewOtp,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // History Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'RECENT GENERATED OVERRIDES (${_history.length})',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // History List
            if (_history.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E24) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.history_toggle_off_rounded,
                        size: 36,
                        color: isDark ? Colors.white24 : Colors.black26,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No OTPs generated during this session',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _history.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, idx) {
                  final otp = _history[idx];
                  return _buildHistoryItem(otp, isDark, theme);
                },
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationChip(
    int minutes,
    String label,
    bool isDark,
    ThemeData theme,
  ) {
    final isSelected = _selectedDurationMinutes == minutes;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected
              ? Colors.white
              : (isDark ? Colors.white70 : Colors.black87),
        ),
      ),
      selected: isSelected,
      selectedColor: theme.primaryColor,
      backgroundColor: isDark ? const Color(0xFF26262E) : const Color(0xFFF0F0F5),
      onSelected: (_) {
        setState(() => _selectedDurationMinutes = minutes);
      },
    );
  }

  Widget _buildActiveOtpHeroCard(
    OtpRecord otp,
    bool isDark,
    ThemeData theme,
  ) {
    final remaining = otp.remainingTime;
    final remainingFormatted = _formatDuration(remaining);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF0D3B4C), const Color(0xFF142433)]
              : [const Color(0xFFE0F7FA), const Color(0xFFE8F5E9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF00B4D8).withOpacity(0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00B4D8).withOpacity(0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32).withOpacity(0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF4CAF50).withOpacity(0.4),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.fiber_manual_record,
                        color: Color(0xFF4CAF50), size: 10),
                    SizedBox(width: 6),
                    Text(
                      'ACTIVE PIN',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: Color(0xFF4CAF50),
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.timer_outlined,
                      size: 16, color: Color(0xFF00B4D8)),
                  const SizedBox(width: 4),
                  Text(
                    remainingFormatted,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00B4D8),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Big 6-digit display
          GestureDetector(
            onTap: () => _copyToClipboard(otp.code),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
              decoration: BoxDecoration(
                color: isDark ? Colors.black45 : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    otp.code.split('').join('  '),
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4.0,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Icon(
                    Icons.copy_rounded,
                    size: 22,
                    color: Color(0xFF00B4D8),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Reason and customer summary
          Text(
            otp.reason,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            otp.customerCode.isEmpty
                ? 'Applies to: ALL CUSTOMERS'
                : 'Customer: ${otp.customerCode}',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
          const SizedBox(height: 14),

          // Actions Row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF00B4D8),
                  side: const BorderSide(color: Color(0xFF00B4D8)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copy PIN', style: TextStyle(fontSize: 12)),
                onPressed: () => _copyToClipboard(otp.code),
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.block_rounded, size: 16),
                label: const Text('Revoke', style: TextStyle(fontSize: 12)),
                onPressed: () => _revokeOtp(otp),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNoActiveOtpPlaceholder(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black12,
        ),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.vpn_key_outlined,
              size: 32,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
            const SizedBox(height: 8),
            Text(
              'No active supervisor PIN currently running',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Configure reason below and tap "Generate Secure OTP"',
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryItem(
    OtpRecord otp,
    bool isDark,
    ThemeData theme,
  ) {
    Color badgeColor;
    String badgeText;
    if (otp.isRevoked) {
      badgeColor = Colors.redAccent;
      badgeText = 'REVOKED';
    } else if (otp.isExpired) {
      badgeColor = Colors.grey;
      badgeText = 'EXPIRED';
    } else {
      badgeColor = const Color(0xFF4CAF50);
      badgeText = 'ACTIVE';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black12,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2B2B36) : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              otp.code,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
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
                        otp.reason,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          color: badgeColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Target: ${otp.customerCode.isEmpty ? 'ANY' : otp.customerCode} • ${DateFormat('HH:mm').format(otp.createdAt)}',
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ],
            ),
          ),
          if (otp.isActive)
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 18),
              tooltip: 'Copy',
              onPressed: () => _copyToClipboard(otp.code),
            ),
        ],
      ),
    );
  }
}
