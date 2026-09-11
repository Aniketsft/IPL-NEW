import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:enterprise_auth_mobile/core/config/auth_config.dart';
import 'package:enterprise_auth_mobile/core/config/api_config.dart';
import 'package:enterprise_auth_mobile/core/network_service.dart';
import 'package:enterprise_auth_mobile/core/secure_storage_service.dart';
import 'package:enterprise_auth_mobile/features/auth/domain/entities/user.dart';
import 'package:enterprise_auth_mobile/features/auth/domain/repositories/iauth_repository.dart';
import 'package:enterprise_auth_mobile/features/auth/domain/usecases/forgot_password_use_case.dart';
import 'package:enterprise_auth_mobile/features/auth/domain/usecases/login_use_case.dart';
import 'package:enterprise_auth_mobile/features/auth/domain/usecases/register_use_case.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_event.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_state.dart';

class FakeSecureStorageService implements SecureStorageService {
  String? token;
  String? username;
  String? schema;

  @override
  Future<void> saveToken(String t) async => token = t;

  @override
  Future<String?> getToken() async => token;

  @override
  Future<void> saveUsername(String u) async => username = u;

  @override
  Future<String?> getUsername() async => username;

  @override
  Future<void> saveSchema(String s) async => schema = s;

  @override
  Future<String?> getSchema() async => schema;

  @override
  Future<void> deleteAll() async {
    token = null;
    username = null;
    schema = null;
  }
}

class FakeAuthRepository implements IAuthRepository {
  bool offlineValid = true;

  @override
  Future<User> login(String username, String password) async {
    return User(
      id: 'test-id-123',
      username: username,
      email: 'test@example.com',
      permissions: ['read', 'write'],
      siteCode: 'TEST',
    );
  }

  @override
  Future<void> register(String email, String username, String password) async {}

  @override
  Future<void> forgotPassword(String email) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<void> refreshToken() async {}

  @override
  Future<bool> isOfflineSessionValid() async => offlineValid;
}

String createTestJwt({required int secondsFromNow}) {
  const header = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9';
  final expTimestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000) + secondsFromNow;
  final payloadJson = jsonEncode({'exp': expTimestamp, 'sub': 'user-1'});
  final payload = base64Url.encode(utf8.encode(payloadJson)).replaceAll('=', '');
  return '$header.$payload.signature';
}

void main() {
  group('Centralized Timeout & Auto-Logout Architecture', () {
    late FakeSecureStorageService storageService;
    late FakeAuthRepository authRepository;
    late AuthBloc authBloc;

    setUp(() {
      storageService = FakeSecureStorageService();
      authRepository = FakeAuthRepository();
      authBloc = AuthBloc(
        loginUseCase: LoginUseCase(authRepository),
        registerUseCase: RegisterUseCase(authRepository),
        forgotPasswordUseCase: ForgotPasswordUseCase(authRepository),
        storageService: storageService,
        authRepository: authRepository,
      );
    });

    tearDown(() {
      authBloc.close();
    });

    test('Single canonical time variable governs sessionTimeout across config', () {
      expect(AuthConfig.sessionTimeout, const Duration(minutes: 30));
      expect(ApiConfig.sessionTimeout, AuthConfig.sessionTimeout);
      expect(AuthConfig.tokenRefreshInterval, const Duration(minutes: 15));
    });

    test('isTokenExpired correctly validates JWT expiration', () {
      final validToken = createTestJwt(secondsFromNow: 1800);
      final expiredToken = createTestJwt(secondsFromNow: -10);
      const malformedToken = 'invalid.token';

      expect(isTokenExpired(validToken), isFalse);
      expect(isTokenExpired(expiredToken), isTrue);
      expect(isTokenExpired(malformedToken), isTrue);
    });

    test('Auto-logout occurs immediately when JWT token is lost while authenticated', () async {
      // 1. Log in with a valid token
      final validToken = createTestJwt(secondsFromNow: 1800);
      await storageService.saveToken(validToken);

      authBloc.add(LoginSubmitted(username: 'admin', password: 'password'));
      await expectLater(
        authBloc.stream,
        emitsInOrder([
          isA<AuthLoading>(),
          isA<Authenticated>(),
        ]),
      );

      // 2. Simulate JWT token being lost/wiped from storage
      await storageService.deleteAll();
      expect(await storageService.getToken(), isNull);

      // 3. Trigger ValidateSession (e.g. app resume from sleep/background)
      authBloc.add(ValidateSession());
      await expectLater(
        authBloc.stream,
        emits(isA<Unauthenticated>()),
      );
    });

    test('Auto-logout occurs when user interacts after JWT token is lost', () async {
      final validToken = createTestJwt(secondsFromNow: 1800);
      await storageService.saveToken(validToken);

      authBloc.add(LoginSubmitted(username: 'admin', password: 'password'));
      await expectLater(
        authBloc.stream,
        emitsInOrder([
          isA<AuthLoading>(),
          isA<Authenticated>(),
        ]),
      );

      // Token wiped from storage
      await storageService.deleteAll();

      // User interacts (e.g. screen tap)
      authBloc.add(UserInteracted());
      await expectLater(
        authBloc.stream,
        emits(isA<Unauthenticated>()),
      );
    });

    test('Auto-logout occurs when JWT token has expired locally', () async {
      // 1. Log in
      final validToken = createTestJwt(secondsFromNow: 1800);
      await storageService.saveToken(validToken);

      authBloc.add(LoginSubmitted(username: 'admin', password: 'password'));
      await expectLater(
        authBloc.stream,
        emitsInOrder([
          isA<AuthLoading>(),
          isA<Authenticated>(),
        ]),
      );

      // 2. Token expires
      final expiredToken = createTestJwt(secondsFromNow: -5);
      await storageService.saveToken(expiredToken);

      // 3. User interaction or validation catches expired token
      authBloc.add(ValidateSession());
      await expectLater(
        authBloc.stream,
        emits(isA<Unauthenticated>()),
      );
    });

    test('Continuous user interaction within timeout maintains Authenticated session', () async {
      final validToken = createTestJwt(secondsFromNow: 1800);
      await storageService.saveToken(validToken);

      authBloc.add(LoginSubmitted(username: 'admin', password: 'password'));
      await expectLater(
        authBloc.stream,
        emitsInOrder([
          isA<AuthLoading>(),
          isA<Authenticated>(),
        ]),
      );

      // User interacts within timeout
      authBloc.add(UserInteracted());
      await Future.delayed(const Duration(milliseconds: 50));

      // Session should remain Authenticated
      expect(authBloc.state, isA<Authenticated>());
    });
  });
}
