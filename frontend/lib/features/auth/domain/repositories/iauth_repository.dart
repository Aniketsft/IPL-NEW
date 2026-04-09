import 'package:enterprise_auth_mobile/features/auth/domain/entities/user.dart';

abstract class IAuthRepository {
  Future<User> login(String username, String password);
  Future<void> register(String email, String username, String password);
  Future<void> forgotPassword(String email);
  Future<void> logout();
}
