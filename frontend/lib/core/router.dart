import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/providers/auth_provider.dart';
import 'package:pos_connect/features/auth/login_screen.dart';
import 'package:pos_connect/features/auth/register_screen.dart';
import 'package:pos_connect/features/billing/billing_screen.dart';
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
import 'package:pos_connect/features/admin/admin_screen.dart';
import 'package:pos_connect/features/audit/audit_screen.dart';
import 'package:pos_connect/features/warehouses/warehouses_screen.dart';
import 'package:pos_connect/features/reports/depot_reports_screen.dart';
import 'package:pos_connect/data/models/restaurant_model.dart';
import 'package:pos_connect/features/restaurant/tables_screen.dart';
import 'package:pos_connect/features/restaurant/table_order_screen.dart';
import 'package:pos_connect/features/restaurant/kitchen_screen.dart';
import 'package:pos_connect/features/restaurant/housekeeping_screen.dart';
import 'package:pos_connect/features/restaurant/commandes_screen.dart';
import 'package:pos_connect/features/restaurant/commande_screen.dart';
import 'package:pos_connect/features/public/home_screen.dart';
import 'package:pos_connect/features/public/contact_screen.dart';
import 'package:pos_connect/features/public/terms_screen.dart';
import 'package:pos_connect/features/public/privacy_screen.dart';
import 'package:pos_connect/shared/widgets/app_shell.dart';

// Notifies GoRouter when auth state changes, without recreating the router.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    ref.listen<AuthState>(authProvider, (_, __) => notifyListeners());
  }
}

// Routes qui ne nécessitent pas d'authentification.
const _kPublicRoutes = {
  '/splash', '/login', '/home', '/contact', '/terms',
  '/privacy', '/register', '/install', '/admin', '/change-password',
};

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthRefreshNotifier(ref);
  // Sauvegarde de l'URL d'origine lors d'un refresh sur une page protégée.
  String? pendingDeepLink;

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final isLoading  = authState.isLoading;
      final isLoggedIn = authState.isAuthenticated;
      final mustChange = authState.user?.mustChangePassword ?? false;
      final location   = state.matchedLocation;

      // ── Auth en cours de vérification ────────────────────────────────────
      // Sauvegarder l'URL protégée et afficher le splash pendant la vérif.
      if (isLoading) {
        if (!_kPublicRoutes.contains(location)) {
          pendingDeepLink = state.uri.toString();
        }
        return location == '/splash' ? null : '/splash';
      }

      // ── Splash : auth résolue, naviguer vers la bonne destination ────────
      if (location == '/splash') {
        if (!isLoggedIn) {
          pendingDeepLink = null;
          return kIsWeb ? '/home' : '/login';
        }
        if (mustChange) {
          pendingDeepLink = null;
          return '/change-password';
        }
        // Restaurer l'URL d'origine (deep link depuis un refresh) ou dashboard
        final target = pendingDeepLink ?? '/dashboard';
        pendingDeepLink = null;
        return target;
      }

      // ── Routes publiques ─────────────────────────────────────────────────
      if (location == '/install') {
        final isMobile = !kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.iOS);
        return isMobile ? '/login' : null;
      }
      if (location == '/register') return null;
      if (location == '/admin') return null;
      if (location == '/home' || location == '/contact' ||
          location == '/terms' || location == '/privacy') {
        return isLoggedIn ? '/dashboard' : null;
      }

      // ── Routes protégées ─────────────────────────────────────────────────
      if (!isLoggedIn && location != '/login') return kIsWeb ? '/home' : '/login';
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
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/contact',
        builder: (context, state) => const ContactScreen(),
      ),
      GoRoute(
        path: '/terms',
        builder: (context, state) => const TermsScreen(),
      ),
      GoRoute(
        path: '/privacy',
        builder: (context, state) => const PrivacyScreen(),
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
            path: '/reports/depots',
            builder: (context, state) => const DepotReportsScreen(),
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
          GoRoute(
            path: '/billing',
            builder: (context, state) => const BillingScreen(),
          ),
          GoRoute(
            path: '/audit',
            builder: (context, state) => const AuditScreen(),
          ),
          GoRoute(
            path: '/warehouses',
            builder: (context, state) => const WarehousesScreen(),
          ),
          GoRoute(
            path: '/restaurant/tables',
            builder: (context, state) => const TablesScreen(),
          ),
          GoRoute(
            path: '/restaurant/table/:tableId',
            builder: (context, state) => TableOrderScreen(
              tableId: state.pathParameters['tableId']!,
              table: state.extra as RestaurantTableModel?,
            ),
          ),
          GoRoute(
            path: '/restaurant/kitchen',
            builder: (context, state) => const KitchenScreen(),
          ),
          GoRoute(
            path: '/restaurant/housekeeping',
            builder: (context, state) => const HousekeepingScreen(),
          ),
          GoRoute(
            path: '/restaurant/commandes',
            builder: (context, state) => CommandesScreen(
              autoTableId: state.extra as String?,
            ),
          ),
          GoRoute(
            path: '/restaurant/commande/:orderId',
            builder: (context, state) => CommandeScreen(
              orderId: state.pathParameters['orderId']!,
            ),
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
