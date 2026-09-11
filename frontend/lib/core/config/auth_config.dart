class AuthConfig {
  /// Single canonical source of truth for session and authentication timeouts across the app.
  /// This single variable governs:
  /// 1. User Inactivity Timeout (idle timer auto-logout).
  /// 2. Offline Session Max Validity window.
  /// 3. In-memory / background activity lapse threshold.
  /// 
  /// Default is 30 minutes, directly matching the backend JWT ExpiryMinutes (30).
  /// Changing this single value automatically adjusts all timeout-related behaviors app-wide.
  static const Duration sessionTimeout = Duration(minutes: 30);

  /// Proactive Sliding Token Refresh Interval:
  /// Derived automatically from [sessionTimeout] (half the session window, clamped between 1 and 15 minutes)
  /// to seamlessly refresh active sessions before the token expires.
  static Duration get tokenRefreshInterval =>
      Duration(minutes: (sessionTimeout.inMinutes ~/ 2).clamp(1, 15));
}
