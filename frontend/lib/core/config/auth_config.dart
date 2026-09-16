class AuthConfig {
  // ─────────────────────────────────────────────────────────────────────────
  // UX / Inactivity Timeout
  // ─────────────────────────────────────────────────────────────────────────
  /// How long a user can be completely idle (no touches) before the app
  /// automatically locks and requires re-login.
  /// Set to a full work-shift (8 hours) so active field workers are never
  /// interrupted mid-task. This is a UX policy, NOT a security token lifetime.
  static const Duration sessionTimeout = Duration(hours: 8);

  // ─────────────────────────────────────────────────────────────────────────
  // JWT / Token Lifecycle
  // ─────────────────────────────────────────────────────────────────────────
  /// Proactive Sliding Token Refresh Interval.
  /// Fires a background refresh well before the server-issued JWT expires
  /// (backend default: 30 min). Clamped to 1–15 min to avoid excessive calls.
  static const Duration tokenRefreshInterval = Duration(minutes: 15);

  /// How many minutes before JWT expiry to start warning / proactively refresh.
  /// Used by the AuthBloc to attempt a silent refresh instead of hard-logging out.
  static const Duration jwtExpiryWarningThreshold = Duration(minutes: 5);

  // ─────────────────────────────────────────────────────────────────────────
  // Offline Credential Window
  // ─────────────────────────────────────────────────────────────────────────
  /// How long a cached (hashed) credential remains valid for offline login
  /// when the server is unreachable. Intended to cover full weeks on-site
  /// without connectivity. The JWT refresh will naturally re-anchor this
  /// whenever the device is online.
  static const Duration offlineLoginWindow = Duration(days: 7);
}
