import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/network_service.dart';
import '../../../../core/secure_storage_service.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_state.dart';
import '../../data/local/local_database_helper.dart';

class DiscountLimitDialog extends StatefulWidget {
  const DiscountLimitDialog({super.key});

  static Future<double?> show(BuildContext context) {
    return showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const DiscountLimitDialog(),
    );
  }

  @override
  State<DiscountLimitDialog> createState() => _DiscountLimitDialogState();
}

class _DiscountLimitDialogState extends State<DiscountLimitDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;
  double _currentLimit = 5.0;
  String? _errorText;
  String? _statusNote;

  @override
  void initState() {
    super.initState();
    _loadCurrentLimit();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatLimit(double val) =>
      val % 1 == 0 ? val.toInt().toString() : val.toStringAsFixed(2);

  bool get _canUpdate {
    final authState = context.read<AuthBloc>().state;
    if (authState is! Authenticated) return false;
    final perms = authState.permissions;
    return perms.contains('logistics.sales.discount_limit.update') ||
        perms.contains('logistics.sales.discount_limit.create') ||
        perms.contains('admin') ||
        perms.contains('*');
  }

  Future<void> _loadCurrentLimit() async {
    double localLimit = await LocalDatabaseHelper.instance.getMaxDiscountPercent();
    if (mounted) {
      setState(() {
        _currentLimit = localLimit;
        _controller.text = _formatLimit(localLimit);
      });
    }

    try {
      final token = await SecureStorageService().getToken();
      if (token != null && !token.startsWith('OFFLINE_SESSION_') && mounted) {
        final dio = context.read<NetworkService>().dio;
        final resp = await dio.get('Sync/global-settings');
        if (resp.statusCode == 200 && resp.data is Map) {
          final settingsMap = <String, String>{};
          (resp.data as Map).forEach((k, v) {
            if (k != null && v != null) {
              settingsMap[k.toString()] = v.toString();
            }
          });
          if (settingsMap.isNotEmpty) {
            await LocalDatabaseHelper.instance.saveGlobalSettingsMap(settingsMap);
            final refreshed = await LocalDatabaseHelper.instance.getMaxDiscountPercent();
            localLimit = refreshed;
            _statusNote = 'Loaded latest setting from server.';
          }
        }
      }
    } catch (_) {
      _statusNote = 'Showing locally synced limit (offline).';
    }

    if (mounted) {
      setState(() {
        _currentLimit = localLimit;
        _controller.text = _formatLimit(localLimit);
        _isLoading = false;
      });
    }
  }

  Future<void> _saveLimit() async {
    final parsed = double.tryParse(_controller.text.trim());
    if (parsed == null || parsed.isNaN || parsed.isInfinite || parsed < 0 || parsed > 100) {
      setState(() {
        _errorText = 'Enter a percentage between 0 and 100.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    final formattedValue = _formatLimit(parsed);
    final authState = context.read<AuthBloc>().state;
    final username = authState is Authenticated ? authState.username : null;

    try {
      final token = await SecureStorageService().getToken();
      final isOffline = token == null || token.isEmpty || token.startsWith('OFFLINE_SESSION_');

      if (!isOffline) {
        final dio = context.read<NetworkService>().dio;
        final resp = await dio.put(
          'Sync/global-settings/discount-limit',
          data: {'maxDiscountPercent': parsed},
        );

        if (resp.statusCode == 200) {
          await LocalDatabaseHelper.instance.updateGlobalSetting(
            'MaxDiscountPercent',
            formattedValue,
            isSynced: true,
            updatedBy: username,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Discount limit updated to $formattedValue% and saved to server.'),
                backgroundColor: const Color(0xFF2E7D32),
              ),
            );
            Navigator.of(context).pop(parsed);
          }
          return;
        }
      }

      // Offline fallback: queue locally for next Sync/push
      await LocalDatabaseHelper.instance.updateGlobalSetting(
        'MaxDiscountPercent',
        formattedValue,
        isSynced: false,
        updatedBy: username,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved locally ($formattedValue%). Will sync to server when online.'),
            backgroundColor: Colors.orange.shade800,
          ),
        );
        Navigator.of(context).pop(parsed);
      }
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 403 || status == 401) {
        setState(() {
          _isSaving = false;
          _errorText = 'You are not authorized to update the discount limit.';
        });
        return;
      }
      if (status == 400) {
        setState(() {
          _isSaving = false;
          _errorText = e.response?.data?['error']?.toString() ?? 'Invalid discount limit value.';
        });
        return;
      }

      // Transient network failure: queue locally for next sync
      await LocalDatabaseHelper.instance.updateGlobalSetting(
        'MaxDiscountPercent',
        formattedValue,
        isSynced: false,
        updatedBy: username,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Server unreachable. Saved locally ($formattedValue%) for next sync.'),
            backgroundColor: Colors.orange.shade800,
          ),
        );
        Navigator.of(context).pop(parsed);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorText = 'Failed to update discount limit: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final canEdit = _canUpdate;

    return AlertDialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.tune_rounded, color: theme.primaryColor),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Max Discount Limit',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
        ],
      ),
      content: _isLoading
          ? const SizedBox(
              height: 90,
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Applies globally across all salesmen after Data Sync.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Current Limit:',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      Text(
                        '${_formatLimit(_currentLimit)}%',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: theme.primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  enabled: canEdit && !_isSaving,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}(\.\d{0,2})?$')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'New Discount Limit (%)',
                    hintText: 'e.g. 5 or 10',
                    suffixText: '%',
                    border: const OutlineInputBorder(),
                    errorText: _errorText,
                  ),
                ),
                if (_statusNote != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _statusNote!,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ],
                if (!canEdit) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Read-only access. Update permission is required to modify.',
                    style: TextStyle(fontSize: 11, color: Colors.orange),
                  ),
                ],
              ],
            ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('CANCEL'),
        ),
        if (canEdit)
          ElevatedButton.icon(
            onPressed: (_isLoading || _isSaving) ? null : _saveLimit,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save_rounded, size: 18),
            label: Text(_isSaving ? 'SAVING...' : 'SAVE & SYNC'),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primaryColor,
              foregroundColor: Colors.white,
            ),
          ),
      ],
    );
  }
}
