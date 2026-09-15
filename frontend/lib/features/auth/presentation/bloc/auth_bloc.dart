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
    if (state is Authenticated) {
      // 1. Check if inactivity timeout has elapsed
      if (_lastActivityTime != null &&
          DateTime.now().difference(_lastActivityTime!) >= AuthConfig.sessionTimeout) {
        print('AuthBloc: User interacted after timeout (${AuthConfig.sessionTimeout.inMinutes}m). Auto-logging out.');
        add(LogoutRequested());
        return;
      }

      // 2. Check if JWT token is lost or expired
      final token = await _storageService.getToken();
      if (token == null || token.isEmpty || isTokenExpired(token)) {
        print('AuthBloc: JWT token is lost or expired on user interaction. Auto-logging out.');
        add(LogoutRequested());
        return;
      }

      // 3. User is actively interacting with a valid session: refresh timestamp and timer
      _lastActivityTime = DateTime.now();
      _startInactivityTimer();
    }
  }

  Future<void> _onValidateSession(
    ValidateSession event,
    Emitter<AuthState> emit,
  ) async {
    if (state is Authenticated) {
      // 1. Check if inactivity elapsed while app was paused or in background
      if (_lastActivityTime != null &&
          DateTime.now().difference(_lastActivityTime!) >= AuthConfig.sessionTimeout) {
        print('AuthBloc: Session expired due to inactivity while paused/idle. Auto-logging out.');
        add(LogoutRequested());
        return;
      }

      // 2. Check if JWT token is lost or expired
      final token = await _storageService.getToken();
      if (token == null || token.isEmpty || isTokenExpired(token)) {
        print('AuthBloc: JWT token is lost or expired during session validation. Auto-logging out.');
        add(LogoutRequested());
        return;
      }
    }
  }

  Future<void> _onPerformTokenRefresh(
    PerformTokenRefresh event,
    Emitter<AuthState> emit,
  ) async {
    if (state is Authenticated) {
      await _authRepository.refreshToken();
      final isValid = await _authRepository.isOfflineSessionValid();
      if (!isValid) {
        add(LogoutRequested());
      } else {
        await _updateAuthTimer();
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
      print('AuthBloc: Inactivity timer expired (${AuthConfig.sessionTimeout.inMinutes}m). Auto-logging out.');
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
            add(LogoutRequested());
          });
        } else {
          add(LogoutRequested());
        }
      }
    } catch (e) {
      // Ignore
    }
  }
}
