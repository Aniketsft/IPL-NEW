import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:async';
import 'dart:convert';
import 'package:enterprise_auth_mobile/core/config/auth_config.dart';
import 'package:enterprise_auth_mobile/core/network_service.dart';
import 'package:enterprise_auth_mobile/core/secure_storage_service.dart';
import 'package:enterprise_auth_mobile/features/auth/domain/usecases/login_use_case.dart';
import 'package:enterprise_auth_mobile/features/auth/domain/usecases/register_use_case.dart';
import 'package:enterprise_auth_mobile/features/auth/domain/usecases/forgot_password_use_case.dart';
import 'package:enterprise_auth_mobile/features/auth/domain/repositories/iauth_repository.dart';
import 'package:enterprise_auth_mobile/core/config/api_config.dart';
import 'package:enterprise_auth_mobile/core/services/device_info_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'package:http/http.dart' as http;
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final LoginUseCase _loginUseCase;
  final RegisterUseCase _registerUseCase;
  final ForgotPasswordUseCase _forgotPasswordUseCase;
  final SecureStorageService _storageService;
  final IAuthRepository _authRepository;

  Timer? _authTimer;
  Timer? _inactivityTimer;
  Timer? _refreshTimer;
  DateTime? _lastActivityTime;

  AuthBloc({
    required LoginUseCase loginUseCase,
    required RegisterUseCase registerUseCase,
    required ForgotPasswordUseCase forgotPasswordUseCase,
    required SecureStorageService storageService,
    required IAuthRepository authRepository,
  }) : _loginUseCase = loginUseCase,
       _registerUseCase = registerUseCase,
       _forgotPasswordUseCase = forgotPasswordUseCase,
       _storageService = storageService,
       _authRepository = authRepository,
       super(AuthInitial()) {
    on<AppStarted>(_onAppStarted);
    on<LoginSubmitted>(_onLoginSubmitted);
    on<RegisterSubmitted>(_onRegisterSubmitted);
    on<LogoutRequested>(_onLogoutRequested);
    on<ForgotPasswordSubmitted>(_onForgotPasswordSubmitted);
    on<UserInteracted>(_onUserInteracted);
    on<PerformTokenRefresh>(_onPerformTokenRefresh);
    on<ValidateSession>(_onValidateSession);
    on<SoftSessionCheck>(_onSoftSessionCheck);
  }

  Future<void> _onAppStarted(AppStarted event, Emitter<AuthState> emit) async {
    // Force login screen on startup as requested
    emit(Unauthenticated());
  }

  Future<void> _onLoginSubmitted(
    LoginSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final user = await _loginUseCase.execute(event.username, event.password);

      print('AuthBloc: Login successful for ${user.username}');
      print('AuthBloc: Permissions received: ${user.permissions}');

      _lastActivityTime = DateTime.now();
      _startTimers();
      await _updateAuthTimer();

      emit(
        Authenticated(
          username: user.username,
          permissions: user.permissions,
          siteCode: user.siteCode,
        ),
      );

      // On Login: Resolve and map device location from SQLite & Backend Heartbeat
      unawaited(_syncDeviceLocationOnLogin(user.siteCode ?? 'IPL'));
    } catch (e) {
      emit(AuthFailure(e.toString()));
    }
  }

  Future<void> _onRegisterSubmitted(
    RegisterSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      await _registerUseCase.execute(
        event.email,
        event.username,
        event.password,
      );
      emit(AuthSuccess("User registered successfully. Please login."));
    } catch (e) {
      emit(AuthFailure(e.toString()));
    }
  }

  Future<void> _onForgotPasswordSubmitted(
    ForgotPasswordSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      await _forgotPasswordUseCase.execute(event.email);
      emit(AuthSuccess("Reset link sent if account exists."));
    } catch (e) {
      emit(AuthFailure(e.toString()));
    }
  }

  Future<void> _onLogoutRequested(
    LogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    _cancelAllTimers();
    _lastActivityTime = null;
    await _storageService.deleteAll();
    emit(Unauthenticated());
  }

  Future<void> _onUserInteracted(
    UserInteracted event,
    Emitter<AuthState> emit,
  ) async {
    if (state is! Authenticated) return;

    // 1. Inactivity check — has the user been completely idle for a full shift?
    if (_lastActivityTime != null &&
        DateTime.now().difference(_lastActivityTime!) >= AuthConfig.sessionTimeout) {
      print('AuthBloc: User interacted after ${AuthConfig.sessionTimeout.inHours}h idle. Auto-logging out.');
      add(LogoutRequested());
      return;
    }

    // 2. JWT check — if online JWT is expired, attempt a silent refresh before forcing logout.
    //    For offline sessions ('OFFLINE_SESSION_'), skip network refresh and keep the session active.
    final token = await _storageService.getToken();
    final isOfflineSession = token != null && token.startsWith('OFFLINE_SESSION_');

    if (!isOfflineSession && (token == null || token.isEmpty || isTokenExpired(token))) {
      print('AuthBloc: JWT expired on interaction — attempting silent refresh.');
      final success = await _authRepository.refreshToken();
      if (!success) {
        final offlineValid = await _authRepository.isOfflineSessionValid();
        if (!offlineValid) {
          print('AuthBloc: Silent refresh failed and offline session invalid. Logging out.');
          add(LogoutRequested());
          return;
        }
        final username = await _storageService.getUsername() ?? 'user';
        await _storageService.saveToken('OFFLINE_SESSION_$username');
        _cancelAllTimers();
        _startInactivityTimer();
        print('AuthBloc: Silent refresh offline. Transitioned to OFFLINE mode (valid for 7 days).');
      } else {
        await _updateAuthTimer();
      }
    }

    // 3. Active, valid session — slide the inactivity timer forward.
    _lastActivityTime = DateTime.now();
    _startInactivityTimer();
  }

  /// Hard session validation — called when returning from background.
  /// Checks inactivity and JWT, but attempts silent refresh before logging out.
  Future<void> _onValidateSession(
    ValidateSession event,
    Emitter<AuthState> emit,
  ) async {
    if (state is! Authenticated) return;

    // If the user has been away for longer than a full shift, log out.
    if (_lastActivityTime != null &&
        DateTime.now().difference(_lastActivityTime!) >= AuthConfig.sessionTimeout) {
      print('AuthBloc: Session expired (${AuthConfig.sessionTimeout.inHours}h idle). Auto-logging out.');
      add(LogoutRequested());
      return;
    }

    // JWT may have expired while phone was locked — try a silent refresh if not an offline session.
    final token = await _storageService.getToken();
    final isOfflineSession = token != null && token.startsWith('OFFLINE_SESSION_');

    if (!isOfflineSession && (token == null || token.isEmpty || isTokenExpired(token))) {
      print('AuthBloc: JWT expired on resume — attempting silent refresh.');
      final success = await _authRepository.refreshToken();
      if (!success) {
        final offlineValid = await _authRepository.isOfflineSessionValid();
        if (!offlineValid) {
          print('AuthBloc: Post-resume refresh failed and offline invalid. Logging out.');
          add(LogoutRequested());
        } else {
          final username = await _storageService.getUsername() ?? 'user';
          await _storageService.saveToken('OFFLINE_SESSION_$username');
          _cancelAllTimers();
          _startInactivityTimer();
          print('AuthBloc: Post-resume refresh offline. Transitioned to OFFLINE session.');
        }
      } else {
        await _updateAuthTimer();
      }
    }
  }

  /// Soft check — fired by InactivityWatcher when the phone is briefly woken.
  /// Does NOT logout under any circumstance. Simply updates the last-seen timestamp.
  Future<void> _onSoftSessionCheck(
    SoftSessionCheck event,
    Emitter<AuthState> emit,
  ) async {
    if (state is! Authenticated) return;
    // If we're within the inactivity window, just slide the timer.
    if (_lastActivityTime != null &&
        DateTime.now().difference(_lastActivityTime!) < AuthConfig.sessionTimeout) {
      _lastActivityTime = DateTime.now();
      _startInactivityTimer();
    }
    // If over the window, a hard ValidateSession from InactivityWatcher will handle it.
  }

  Future<void> _onPerformTokenRefresh(
    PerformTokenRefresh event,
    Emitter<AuthState> emit,
  ) async {
    if (state is! Authenticated) return;
    final token = await _storageService.getToken();
    if (token == null || token.startsWith('OFFLINE_SESSION_')) {
      print('AuthBloc: Skipping token refresh for offline session.');
      return;
    }
    final success = await _authRepository.refreshToken();
    if (success) {
      await _updateAuthTimer();
    } else {
      final offlineValid = await _authRepository.isOfflineSessionValid();
      if (offlineValid) {
        final username = await _storageService.getUsername() ?? 'user';
        await _storageService.saveToken('OFFLINE_SESSION_$username');
        _cancelAllTimers();
        _startInactivityTimer();
        print('AuthBloc: Network unavailable for token refresh. Session safely converted to OFFLINE mode (valid for 7 days).');
      } else {
        print('AuthBloc: Token refresh failed and offline credentials expired. Logging out.');
        add(LogoutRequested());
      }
    }
  }

  @override
  Future<void> close() {
    _cancelAllTimers();
    return super.close();
  }

  void _cancelAllTimers() {
    _authTimer?.cancel();
    _inactivityTimer?.cancel();
    _refreshTimer?.cancel();
  }

  void _startInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(AuthConfig.sessionTimeout, () {
      print('AuthBloc: Inactivity timer expired (${AuthConfig.sessionTimeout.inHours}h). Auto-logging out.');
      add(LogoutRequested());
    });
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(AuthConfig.tokenRefreshInterval, (_) {
      add(PerformTokenRefresh());
    });
  }

  void _startTimers() {
    _inactivityTimer?.cancel();
    _refreshTimer?.cancel();
    _startInactivityTimer();
    _storageService.getToken().then((token) {
      if (token != null && !token.startsWith('OFFLINE_SESSION_')) {
        _startRefreshTimer();
      }
    });
  }

  Future<void> _updateAuthTimer() async {
    _authTimer?.cancel();
    final token = await _storageService.getToken();
    if (token == null || token.startsWith('OFFLINE_SESSION_')) return;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return;
      final normalized = base64Url.normalize(parts[1]);
      final payloadString = utf8.decode(base64Url.decode(normalized));
      final payloadMap = jsonDecode(payloadString);
      if (payloadMap is Map<String, dynamic> && payloadMap.containsKey('exp')) {
        final exp = payloadMap['exp'];
        final expInt = exp is int ? exp : int.tryParse(exp.toString()) ?? 0;
        final currentSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final remainingSeconds = expInt - currentSeconds;
        if (remainingSeconds > 0) {
          _authTimer = Timer(Duration(seconds: remainingSeconds), () {
            // JWT is about to expire — attempt a silent refresh before logging out
            print('AuthBloc: JWT hard expiry reached. Attempting silent refresh.');
            add(PerformTokenRefresh());
          });
        } else {
          add(PerformTokenRefresh());
        }
      }
    } catch (e) {
      // Ignore malformed tokens
    }
  }

  Future<void> _syncDeviceLocationOnLogin(String siteCode) async {
    try {
      final deviceService = DeviceInfoService.instance;
      final devId = deviceService.deviceId;
      final mac = deviceService.macAddress;
      final db = LocalDatabaseHelper.instance;

      // 1. Immediately read local SQLite mapping if available
      var localMapping = await db.getDeviceLocation(devId);
      if (localMapping == null && mac.isNotEmpty) {
        localMapping = await db.getDeviceLocationByMac(mac);
      }
      if (localMapping != null && localMapping['locationCode'] != null) {
        await deviceService.setAssignedLocation(
          siteCode: localMapping['siteCode'] ?? siteCode,
          warehouseCode: localMapping['warehouseCode'],
          locationCode: localMapping['locationCode'],
        );
      }

      // 2. Online Heartbeat: auto-register and replicate assigned location
      final token = await _storageService.getToken();
      final url = Uri.parse('${ApiConfig.baseUrl}Devices/heartbeat');
      final resp = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
          'X-Device-Id': devId,
        },
        body: jsonEncode({
          'deviceId': devId,
          'macAddress': mac.isNotEmpty ? mac : null,
          'deviceName': devId,
          'siteCode': siteCode,
        }),
      ).timeout(const Duration(seconds: 5));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data != null && data['locationCode'] != null) {
          final loc = data['locationCode'].toString();
          final wrh = data['warehouseCode']?.toString();
          final site = data['siteCode']?.toString() ?? siteCode;
          final returnedMac = data['macAddress']?.toString();

          if (returnedMac != null && returnedMac.isNotEmpty) {
            await deviceService.setMacAddress(returnedMac);
          }
          await deviceService.setAssignedLocation(
            siteCode: site,
            warehouseCode: wrh,
            locationCode: loc,
          );
          await db.insertOrUpdateDeviceLocation(Map<String, dynamic>.from(data));
        }
      }
    } catch (e) {
      print('AuthBloc: Device location sync error (offline fallback used): $e');
    }
  }
}

