import 'package:enterprise_auth_mobile/features/auth/domain/entities/user.dart';
import 'package:enterprise_auth_mobile/features/auth/domain/repositories/iauth_repository.dart';

class LoginUseCase {
  final IAuthRepository repository;

  LoginUseCase(this.repository);

  Future<User> execute(String username, String password) {
    return repository.login(username, password);
  }
}
