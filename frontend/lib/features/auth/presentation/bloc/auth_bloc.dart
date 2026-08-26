import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:async';
import 'dart:convert';
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

  static const Duration _inactivityTimeout = Duration(minutes: 5);
  static const Duration _refreshInterval = Duration(minutes: 5);

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

      await _startAuthTimer();

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
    await _storageService.deleteAll();
    emit(Unauthenticated());
  }

  void _onUserInteracted(
    UserInteracted event,
    Emitter<AuthState> emit,
  ) {
    if (state is Authenticated) {
      _startInactivityTimer();
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
    _inactivityTimer = Timer(_inactivityTimeout, () {
      add(LogoutRequested());
    });
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      add(PerformTokenRefresh());
    });
  }

  Future<void> _startAuthTimer() async {
    _cancelAllTimers();
    _startInactivityTimer();
    _startRefreshTimer();
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
