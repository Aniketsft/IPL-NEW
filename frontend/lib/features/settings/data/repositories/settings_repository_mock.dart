import 'dart:async';
import '../models/app_settings.dart';

class SettingsRepositoryMock {
  // Simulates an API call fetching settings configuration
  Future<AppSettings> getSettingsConfig() async {
    // Artificial network delay
    await Future.delayed(const Duration(milliseconds: 600));

    // In the future this will be an actual HTTP GET to the real backend controller
    // e.g. return AppSettings.fromJson(await _dio.get('/api/settings/config'));

    return AppSettings.mock();
  }

  // Simulates sending updated configuration to backend
  Future<void> updateSettings(AppSettings settings) async {
    // Artificial network delay to simulate DB write
    await Future.delayed(const Duration(milliseconds: 400));

    // e.g. await _dio.post('/api/settings/config', data: settings.toJson());
  }
}
