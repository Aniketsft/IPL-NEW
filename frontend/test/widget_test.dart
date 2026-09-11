import 'package:flutter_test/flutter_test.dart';
import 'package:enterprise_auth_mobile/core/config/auth_config.dart';
import 'package:enterprise_auth_mobile/core/config/api_config.dart';

void main() {
  test('Global AuthConfig and ApiConfig are properly wired with centralized timeout', () {
    expect(AuthConfig.sessionTimeout, const Duration(minutes: 30));
    expect(ApiConfig.sessionTimeout, const Duration(minutes: 30));
    expect(AuthConfig.tokenRefreshInterval, const Duration(minutes: 15));
  });
}
