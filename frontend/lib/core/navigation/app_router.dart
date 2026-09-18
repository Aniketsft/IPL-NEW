import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:enterprise_auth_mobile/core/navigation/app_routes.dart';

// Import screens (adjust paths as necessary for actual integration)
import 'package:enterprise_auth_mobile/features/auth/presentation/pages/login_screen.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/pages/home_screen.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/pages/sales_invoice/sales_menu_screen.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/pages/sales_invoice/select_transaction_screen.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/pages/sales_invoice/order_summary_screen.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/pages/sales_invoice/amount_only_credit_note_screen.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/pages/sales_invoice/customer_selection_screen.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/pages/sales_invoice/sales_invoice_product_selection_screen.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/pages/sales_invoice/transaction_history_screen.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/pages/sales_invoice/payment_processing_screen.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_state.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

class AppRouter {
  final AuthBloc authBloc;

  AppRouter(this.authBloc);

  late final GoRouter router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.home,
    refreshListenable: GoRouterRefreshStream(authBloc.stream),
    redirect: (context, state) {
      final authState = authBloc.state;
      final isLoggingIn = state.uri.toString() == AppRoutes.login;

      if (authState is AuthInitial || authState is AuthLoading) {
        return null;
      }

      final isAuthenticated = authState is Authenticated;

      if (!isAuthenticated && !isLoggingIn) {
        return AppRoutes.login;
      }

      if (isAuthenticated && isLoggingIn) {
        return AppRoutes.home;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) {
          final authState = authBloc.state;
          if (authState is Authenticated) {
            return HomeScreen(
              username: authState.username,
              permissions: authState.permissions,
            );
          }
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        },
      ),
      // --- Sales Module Routes ---
      GoRoute(
        path: AppRoutes.salesMenu,
        builder: (context, state) {
          final authState = authBloc.state;
          return SalesMenuScreen(
            permissions: authState is Authenticated ? authState.permissions : [],
          );
        },
      ),
      GoRoute(
        path: AppRoutes.selectTransaction,
        builder: (context, state) {
          final authState = authBloc.state;
          return SelectTransactionScreen(
            permissions: authState is Authenticated ? authState.permissions : [],
          );
        },
      ),
      GoRoute(
        path: AppRoutes.orderSummary,
        builder: (context, state) => const OrderSummaryScreen(),
      ),
      GoRoute(
        path: AppRoutes.amountOnlyCreditNote,
        builder: (context, state) => const AmountOnlyCreditNoteScreen(),
      ),
      GoRoute(
        path: AppRoutes.customerSelection,
        builder: (context, state) => const CustomerSelectionScreen(),
      ),
      GoRoute(
        path: AppRoutes.productSelection,
        builder: (context, state) {
          final siteCode = state.uri.queryParameters['siteCode'] ?? 'ALL';
          return SalesInvoiceProductSelectionScreen(siteCode: siteCode);
        },
      ),
      GoRoute(
        path: AppRoutes.transactionHistory,
        builder: (context, state) {
          final transactionType = state.uri.queryParameters['type'] ?? 'INVOICE';
          return TransactionHistoryScreen(transactionType: transactionType);
        },
      ),
      GoRoute(
        path: AppRoutes.paymentProcessing,
        builder: (context, state) {
          final isCreditNote = state.extra as bool? ?? false;
          
          return PaymentProcessingScreen(
            isCreditNoteRefund: isCreditNote,
          );
        },
      ),
    ],
  );
}

// Utility class to convert Bloc stream to Listenable for GoRouter
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }
  late final StreamSubscription<dynamic> _subscription;
  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
