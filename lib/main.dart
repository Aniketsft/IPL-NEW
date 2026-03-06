import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:enterprise_auth_mobile/core/app_theme.dart';
import 'package:enterprise_auth_mobile/core/secure_storage_service.dart';
import 'package:enterprise_auth_mobile/core/theme_cubit.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_event.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_state.dart';
import 'package:enterprise_auth_mobile/features/auth/data/repositories/auth_repository.dart';
import 'package:enterprise_auth_mobile/features/auth/domain/usecases/login_use_case.dart';
import 'package:enterprise_auth_mobile/features/auth/domain/usecases/register_use_case.dart';
import 'package:enterprise_auth_mobile/features/auth/domain/usecases/forgot_password_use_case.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/pages/login_screen.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/pages/home_screen.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/delivery_repository.dart'
    as enterprise_auth_mobile_repo;
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/order_bloc.dart'
    as enterprise_auth_mobile_bloc;
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/local_repository.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/sync/sync_manager.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/usecases/get_production_tracking_use_case.dart';
import 'package:enterprise_auth_mobile/features/manufacturing/bloc/manufacturing_bloc.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider(create: (_) => SecureStorageService()),
        RepositoryProvider(
          create: (context) => AuthRepository(
            storageService: context.read<SecureStorageService>(),
          ),
        ),
        RepositoryProvider(
          create: (_) => enterprise_auth_mobile_repo.DeliveryRepository(),
        ),
        RepositoryProvider(create: (_) => LocalRepository()),
        RepositoryProvider(
          create: (context) => SyncManager(
            localRepository: context.read<LocalRepository>(),
            deliveryRepository: context
                .read<enterprise_auth_mobile_repo.DeliveryRepository>(),
          )..startPeriodicSync(),
        ),
        RepositoryProvider(
          create: (context) => GetProductionTrackingUseCase(
            context.read<enterprise_auth_mobile_repo.DeliveryRepository>(),
          ),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (context) {
              final authRepo = context.read<AuthRepository>();
              return AuthBloc(
                loginUseCase: LoginUseCase(authRepo),
                registerUseCase: RegisterUseCase(authRepo),
                forgotPasswordUseCase: ForgotPasswordUseCase(authRepo),
              )..add(AppStarted());
            },
          ),
          BlocProvider(
            create: (context) => enterprise_auth_mobile_bloc.OrderBloc(
              getProductionTrackingUseCase: context
                  .read<GetProductionTrackingUseCase>(),
            ),
          ),
          BlocProvider(
            create: (context) => ManufacturingBloc(
              getProductionTracking: context
                  .read<GetProductionTrackingUseCase>(),
            ),
          ),
          BlocProvider(create: (_) => ThemeCubit()),
        ],
        child: BlocBuilder<ThemeCubit, ThemeMode>(
          builder: (context, themeMode) {
            return MaterialApp(
              title: 'Enterprise Auth',
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: themeMode,
              debugShowCheckedModeBanner: false,
              home: BlocBuilder<AuthBloc, AuthState>(
                builder: (context, state) {
                  if (state is Authenticated) {
                    return HomeScreen(
                      username: state.username,
                      permissions: state.permissions,
                    );
                  }
                  return const LoginScreen();
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
