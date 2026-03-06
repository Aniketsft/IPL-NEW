import 'package:enterprise_auth_mobile/features/auth/domain/repositories/iauth_repository.dart';

class RegisterUseCase {
  final IAuthRepository repository;

  RegisterUseCase(this.repository);

  Future<void> execute(String email, String username, String password) {
    return repository.register(email, username, password);
  }
}
