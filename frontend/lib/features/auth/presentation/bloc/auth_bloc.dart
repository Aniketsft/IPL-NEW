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

    // 2. JWT check — if expired, attempt a silent refresh before forcing logout.
    //    This handles the case where the 15-min refresh timer misfired (e.g. offline).
    final token = await _storageService.getToken();
    if (token == null || token.isEmpty || isTokenExpired(token)) {
      print('AuthBloc: JWT expired on interaction — attempting silent refresh.');
      try {
        await _authRepository.refreshToken();
        final newToken = await _storageService.getToken();
        if (newToken == null || newToken.isEmpty || isTokenExpired(newToken)) {
          // Refresh returned but token is still bad — check offline validity
          final offlineValid = await _authRepository.isOfflineSessionValid();
          if (!offlineValid) {
            print('AuthBloc: Silent refresh failed and offline session invalid. Logging out.');
            add(LogoutRequested());
            return;
          }
          // Offline session is still valid — let the user keep working
          print('AuthBloc: Silent refresh failed but offline session valid. Continuing.');
        } else {
          await _updateAuthTimer();
        }
      } catch (_) {
        // Network unreachable — check offline window before deciding
        final offlineValid = await _authRepository.isOfflineSessionValid();
        if (!offlineValid) {
          print('AuthBloc: Offline session expired. Logging out.');
          add(LogoutRequested());
          return;
        }
        print('AuthBloc: Offline — continuing with cached session.');
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

    // JWT may have expired while phone was locked — try a silent refresh.
    final token = await _storageService.getToken();
    if (token == null || token.isEmpty || isTokenExpired(token)) {
      print('AuthBloc: JWT expired on resume — attempting silent refresh.');
      try {
        await _authRepository.refreshToken();
        final newToken = await _storageService.getToken();
        if (newToken == null || newToken.isEmpty || isTokenExpired(newToken)) {
          final offlineValid = await _authRepository.isOfflineSessionValid();
          if (!offlineValid) {
            print('AuthBloc: Post-resume refresh failed and offline invalid. Logging out.');
            add(LogoutRequested());
          }
        } else {
          await _updateAuthTimer();
        }
      } catch (_) {
        final offlineValid = await _authRepository.isOfflineSessionValid();
        if (!offlineValid) {
          print('AuthBloc: Post-resume offline session expired. Logging out.');
          add(LogoutRequested());
        }
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
    try {
      await _authRepository.refreshToken();
      await _updateAuthTimer();
    } catch (_) {
      // Network may be unavailable. isOfflineSessionValid will guard on next interaction.
      print('AuthBloc: Periodic token refresh failed (possibly offline). Will retry next cycle.');
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
    _startRefreshTimer();
  }

  Future<void> _updateAuthTimer() async {
    _authTimer?.cancel();
    final token = await _storageService.getToken();
    if (token == null) return;
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
}

