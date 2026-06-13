import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/providers/auth_provider.dart';
import 'package:pos_connect/features/auth/login_screen.dart';
import 'package:pos_connect/features/dashboard/dashboard_screen.dart';
import 'package:pos_connect/features/pos/pos_screen.dart';
import 'package:pos_connect/features/sales/sales_screen.dart';
import 'package:pos_connect/features/purchases/purchases_screen.dart';
import 'package:pos_connect/features/products/products_screen.dart';
import 'package:pos_connect/features/customers/customers_screen.dart';
import 'package:pos_connect/features/suppliers/suppliers_screen.dart';
import 'package:pos_connect/features/debts/debts_screen.dart';
import 'package:pos_connect/features/events/events_screen.dart';
import 'package:pos_connect/features/reports/reports_screen.dart';
import 'package:pos_connect/features/statistics/statistics_screen.dart';
import 'package:pos_connect/features/profile/profile_screen.dart';
import 'package:pos_connect/features/inventory/inventory_screen.dart';
import 'package:pos_connect/features/returns/returns_screen.dart';
import 'package:pos_connect/features/settings/settings_screen.dart';
import 'package:pos_connect/features/splash/splash_screen.dart';
import 'package:pos_connect/features/auth/force_change_password_screen.dart';
import 'package:pos_connect/features/installer/installer_screen.dart';
import 'package:pos_connect/features/hr/hr_screen.dart';
import 'package:pos_connect/features/users/users_screen.dart';
import 'package:pos_connect/shared/widgets/app_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final isLoggedIn = authState.isAuthenticated;
      final mustChange = authState.user?.mustChangePassword ?? false;
      final location = state.matchedLocation;

      if (location == '/splash') return null;
      if (location == '/install') return null; // always accessible pre-setup
      if (!isLoggedIn && location != '/login') return '/login';
      if (isLoggedIn && location == '/login') {
        return mustChange ? '/change-password' : '/dashboard';
      }
      if (isLoggedIn && mustChange && location != '/change-password') {
        return '/change-password';
      }
      if (isLoggedIn && !mustChange && location == '/change-password') {
        return '/dashboard';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/change-password',
        builder: (context, state) => const ForceChangePasswordScreen(),
      ),
      GoRoute(
        path: '/install',
        builder: (context, state) => const InstallerScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/pos',
            builder: (context, state) => const PosScreen(),
          ),
          GoRoute(
            path: '/sales',
            builder: (context, state) => const SalesScreen(),
          ),
          GoRoute(
            path: '/purchases',
            builder: (context, state) => const PurchasesScreen(),
          ),
          GoRoute(
            path: '/products',
            builder: (context, state) => const ProductsScreen(),
          ),
          GoRoute(
            path: '/customers',
            builder: (context, state) => const CustomersScreen(),
          ),
          GoRoute(
            path: '/suppliers',
            builder: (context, state) => const SuppliersScreen(),
          ),
          GoRoute(
            path: '/debts',
            builder: (context, state) => const DebtsScreen(),
          ),
          GoRoute(
            path: '/returns',
            builder: (context, state) => const ReturnsScreen(),
          ),
          GoRoute(
            path: '/inventory',
            builder: (context, state) => const InventoryScreen(),
          ),
          GoRoute(
            path: '/events',
            builder: (context, state) => const EventsScreen(),
          ),
          GoRoute(
            path: '/reports',
            builder: (context, state) => const ReportsScreen(),
          ),
          GoRoute(
            path: '/statistics',
            builder: (context, state) => const StatisticsScreen(),
          ),
          GoRoute(
            path: '/hr',
            builder: (context, state) => const HrScreen(),
          ),
          GoRoute(
            path: '/users-admin',
            builder: (context, state) => const UsersScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Page introuvable: ${state.uri}'),
      ),
    ),
  );
});
