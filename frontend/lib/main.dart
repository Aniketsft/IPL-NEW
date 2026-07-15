import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:enterprise_auth_mobile/core/app_theme.dart';
import 'package:enterprise_auth_mobile/core/secure_storage_service.dart';
import 'package:enterprise_auth_mobile/core/theme_cubit.dart';
import 'package:enterprise_auth_mobile/core/bloc/app_sync/app_sync_bloc.dart';
import 'package:enterprise_auth_mobile/core/bloc/app_sync/app_sync_event.dart';
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
import 'package:enterprise_auth_mobile/features/logistics/domain/usecases/get_sites_use_case.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/usecases/get_customers_use_case.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/usecases/get_sales_reps_use_case.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/usecases/synchronize_logistics_use_case.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/usecases/set_preparation_status_use_case.dart';
import 'package:enterprise_auth_mobile/core/network_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sync_bloc.dart';
import 'package:enterprise_auth_mobile/features/manufacturing/bloc/manufacturing_bloc.dart';
import 'package:enterprise_auth_mobile/core/utils/audio/audio_service.dart';
import 'package:enterprise_auth_mobile/core/services/printer_service.dart';
import 'package:enterprise_auth_mobile/core/services/device_info_service.dart';
import 'package:enterprise_auth_mobile/core/utils/barcode_scanner/hardware_scanner_service.dart';
import 'package:enterprise_auth_mobile/core/widgets/inactivity_watcher.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize core services
  AudioService.instance;
  await PrinterService.instance.init();
  await DeviceInfoService.instance.init();
  await HardwareScannerService().init(); // Warm up Zebra and Sunmi scanners globally
  
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
          create: (context) => NetworkService(
            storageService: context.read<SecureStorageService>(),
          ),
        ),
        RepositoryProvider(
          create: (context) => AuthRepository(
            networkService: context.read<NetworkService>(),
            storageService: context.read<SecureStorageService>(),
          ),
        ),
        RepositoryProvider(
          create: (context) => enterprise_auth_mobile_repo.DeliveryRepository(
            networkService: context.read<NetworkService>(),
            storageService: context.read<SecureStorageService>(),
          ),
        ),
        RepositoryProvider(create: (_) => LocalRepository()),
        RepositoryProvider(
          create: (context) => SyncManager(
            localRepository: context.read<LocalRepository>(),
            deliveryRepository: context
                .read<enterprise_auth_mobile_repo.DeliveryRepository>(),
          ), // Periodic sync disabled — all syncing goes through Sync/push exclusively
        ),
        RepositoryProvider(
          create: (context) => GetProductionTrackingUseCase(
            context.read<enterprise_auth_mobile_repo.DeliveryRepository>(),
          ),
        ),
        RepositoryProvider(
          create: (context) => GetSitesUseCase(
            context.read<enterprise_auth_mobile_repo.DeliveryRepository>(),
          ),
        ),
        RepositoryProvider(
          create: (context) => GetCustomersUseCase(
            context.read<enterprise_auth_mobile_repo.DeliveryRepository>(),
          ),
        ),
        RepositoryProvider(
          create: (context) => GetSalesRepsUseCase(
            context.read<enterprise_auth_mobile_repo.DeliveryRepository>(),
          ),
        ),
        RepositoryProvider(
          create: (context) => SynchronizeLogisticsUseCase(
            context.read<enterprise_auth_mobile_repo.DeliveryRepository>(),
          ),
        ),
        RepositoryProvider(
          create: (context) => SetPreparationStatusUseCase(
            context.read<enterprise_auth_mobile_repo.DeliveryRepository>(),
          ),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (context) {
              final authRepo = context.read<AuthRepository>();
              final authBloc = AuthBloc(
                loginUseCase: LoginUseCase(authRepo),
                registerUseCase: RegisterUseCase(authRepo),
                forgotPasswordUseCase: ForgotPasswordUseCase(authRepo),
                storageService: context.read<SecureStorageService>(),
              )..add(AppStarted());

              context.read<NetworkService>().onUnauthorized = () {
                authBloc.add(LogoutRequested());
              };

              return authBloc;
            },
          ),
          BlocProvider(
            create: (context) => enterprise_auth_mobile_bloc.OrderBloc(
              getProductionTrackingUseCase: context.read<GetProductionTrackingUseCase>(),
              getSitesUseCase: context.read<GetSitesUseCase>(),
              getCustomersUseCase: context.read<GetCustomersUseCase>(),
              getSalesRepsUseCase: context.read<GetSalesRepsUseCase>(),
            ),
          ),
          BlocProvider(
            create: (context) => AppSyncBloc()..add(LoadAppSyncTimeEvent()),
          ),
          BlocProvider(
            create: (context) => ManufacturingBloc(
              getProductionTracking: context
                  .read<GetProductionTrackingUseCase>(),
              synchronizeLogistics: context.read<SynchronizeLogisticsUseCase>(),
              setPreparationStatus: context.read<SetPreparationStatusUseCase>(),
              storageService: context.read<SecureStorageService>(),
              appSyncBloc: context.read<AppSyncBloc>(),
            ),
          ),
          BlocProvider(
            create: (context) => SyncBloc(
              synchronizeLogisticsUseCase:
                  context.read<SynchronizeLogisticsUseCase>(),
              appSyncBloc: context.read<AppSyncBloc>(),
            ),
          ),
          BlocProvider(create: (_) => ThemeCubit()),
        ],
        child: BlocBuilder<ThemeCubit, ThemeMode>(
          builder: (context, themeMode) {
            return InactivityWatcher(
              child: MaterialApp(
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
              ),
            );
          },
        ),
      ),
    );
  }
}
