import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_connect/core/permissions.dart';
import 'package:pos_connect/core/responsive.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/user_model.dart';
import 'package:pos_connect/data/models/warehouse_model.dart';
import 'package:pos_connect/providers/auth_provider.dart';
import 'package:pos_connect/providers/license_provider.dart';
import 'package:pos_connect/providers/permission_provider.dart';
import 'package:pos_connect/providers/sync_provider.dart';
import 'package:pos_connect/providers/warehouse_provider.dart';
import 'package:pos_connect/services/license_service.dart';
import 'package:pos_connect/providers/settings_provider.dart';
import 'package:pos_connect/shared/widgets/pos_logo.dart';
import 'package:pos_connect/services/bluetooth_print_service.dart';
import 'package:pos_connect/services/offline_queue_service.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

class _NavItem {
  final String label;
  final IconData icon;
  final String route;

  const _NavItem(this.label, this.icon, this.route);
}

// ── Main nav (scrollable) ─────────────────────────────────────────────────
const _mainNavItems = [
  _NavItem('Tableau de bord', Icons.dashboard_rounded, '/dashboard'),
  _NavItem('Caisse', Icons.point_of_sale_rounded, '/pos'),
  _NavItem('Ventes', Icons.receipt_long_rounded, '/sales'),
  _NavItem('Achats', Icons.shopping_cart_rounded, '/purchases'),
  _NavItem('Produits', Icons.inventory_2_rounded, '/products'),
  _NavItem('Clients', Icons.people_alt_rounded, '/customers'),
  _NavItem('Fournisseurs', Icons.local_shipping_rounded, '/suppliers'),
  _NavItem('Dettes', Icons.account_balance_wallet_rounded, '/debts'),
  _NavItem('Retours', Icons.assignment_return_rounded, '/returns'),
  _NavItem('Inventaire',      Icons.warehouse_rounded, '/inventory'),
  _NavItem('Business', Icons.apartment_rounded,  '/warehouses'),
];

const _analyticsNavItems = [
  _NavItem('Événements', Icons.event_note_rounded, '/events'),
  _NavItem('Rapports', Icons.assessment_rounded, '/reports'),
  _NavItem('Rapports dépôts', Icons.store_mall_directory_rounded, '/reports/depots'),
  _NavItem('Statistiques', Icons.bar_chart_rounded, '/statistics'),
];

// ── HR / Payroll ──────────────────────────────────────────────────────────
const _hrNavItems = [
  _NavItem('RH & Paie', Icons.badge_rounded, '/hr'),
];

// ── Admin ─────────────────────────────────────────────────────────────────
const _adminNavItems = [
  _NavItem('Utilisateurs & Rôles', Icons.manage_accounts_rounded, '/users-admin'),
];

// ── Bottom-pinned items ────────────────────────────────────────────────────
const _bottomNavItems = [
  _NavItem('Profil', Icons.person_rounded, '/profile'),
  _NavItem('Paramètres', Icons.settings_rounded, '/settings'),
];

// ── Restaurant nav ─────────────────────────────────────────────────────────
const _restaurantMainNavItems = [
  _NavItem('Tableau de bord', Icons.dashboard_rounded,              '/dashboard'),
  _NavItem('Commandes',       Icons.receipt_long_rounded,           '/restaurant/commandes'),
  _NavItem('Tables',          Icons.table_restaurant_rounded,       '/restaurant/tables'),
  _NavItem('Cuisine',         Icons.restaurant_rounded,             '/restaurant/kitchen'),
  _NavItem('Ventes',          Icons.receipt_long_rounded,           '/sales'),
  _NavItem('Factures / Devis',Icons.description_rounded,            '/events'),
  _NavItem('Produits / Menu', Icons.inventory_2_rounded,            '/products'),
  _NavItem('Clients',         Icons.people_alt_rounded,             '/customers'),
  _NavItem('Dettes',          Icons.account_balance_wallet_rounded, '/debts'),
  _NavItem('Business',  Icons.apartment_rounded,              '/warehouses'),
];

const _restaurantAndroidBottomItems = [
  _NavItem('Commandes', Icons.receipt_long_rounded,     '/restaurant/commandes'),
  _NavItem('Tables',    Icons.table_restaurant_rounded, '/restaurant/tables'),
  _NavItem('Cuisine',   Icons.restaurant_rounded,       '/restaurant/kitchen'),
  _NavItem('Ventes',    Icons.receipt_long_rounded,     '/sales'),
];

// ── Hôtel / Motel nav ──────────────────────────────────────────────────────
const _hotelMainNavItems = [
  _NavItem('Tableau de bord', Icons.dashboard_rounded,              '/dashboard'),
  _NavItem('Réservations',    Icons.book_online_rounded,            '/restaurant/commandes'),
  _NavItem('Chambres',        Icons.king_bed_rounded,               '/restaurant/tables'),
  _NavItem('Cuisine',         Icons.restaurant_rounded,             '/restaurant/kitchen'),
  _NavItem('Housekeeping',    Icons.cleaning_services_rounded,      '/restaurant/housekeeping'),
  _NavItem('Transactions',    Icons.receipt_long_rounded,           '/sales'),
  _NavItem('Factures / Devis',Icons.description_rounded,            '/events'),
  _NavItem('Bar & Produits',  Icons.inventory_2_rounded,            '/products'),
  _NavItem('Clients',         Icons.people_alt_rounded,             '/customers'),
  _NavItem('Dettes',          Icons.account_balance_wallet_rounded, '/debts'),
  _NavItem('Business',        Icons.apartment_rounded,              '/warehouses'),
];

const _hotelAndroidBottomItems = [
  _NavItem('Chambres',      Icons.king_bed_rounded,          '/restaurant/tables'),
  _NavItem('Cuisine',       Icons.restaurant_rounded,        '/restaurant/kitchen'),
  _NavItem('Housekeeping',  Icons.cleaning_services_rounded, '/restaurant/housekeeping'),
  _NavItem('Transactions',  Icons.receipt_long_rounded,      '/sales'),
];

List<_NavItem> _resolveMainNav(String businessType) {
  if (businessType == 'restaurant') return _restaurantMainNavItems;
  if (businessType == 'hotel')      return _hotelMainNavItems;
  return _mainNavItems;
}

List<_NavItem> _resolveAndroidBottom(String businessType) {
  if (businessType == 'restaurant') return _restaurantAndroidBottomItems;
  if (businessType == 'hotel')      return _hotelAndroidBottomItems;
  return _androidBottomNavItems;
}

// ── Android nav (focused cashier workflow) ────────────────────────────────
const _androidBottomNavItems = [
  _NavItem('Caisse',  Icons.point_of_sale_rounded, '/pos'),
  _NavItem('Ventes',  Icons.receipt_long_rounded,  '/sales'),
  _NavItem('Clients', Icons.people_alt_rounded,    '/customers'),
  _NavItem('Profil',  Icons.person_rounded,        '/profile'),
];

const _androidDrawerMainItems = [
  _NavItem('Caisse',          Icons.point_of_sale_rounded,  '/pos'),
  _NavItem('Ventes',          Icons.receipt_long_rounded,   '/sales'),
  _NavItem('Clients',         Icons.people_alt_rounded,     '/customers'),
  _NavItem('Produits',        Icons.inventory_2_rounded,    '/products'),
  _NavItem('Factures / Devis',Icons.description_rounded,    '/events'),
];

// All items for title lookup (includes all business types)
const _allNavItems = [
  ..._mainNavItems,
  ..._restaurantMainNavItems,
  ..._hotelMainNavItems,
  ..._analyticsNavItems,
  ..._hrNavItems,
  ..._adminNavItems,
  ..._bottomNavItems,
];

// Required permission per route (null = always visible)
const Map<String, String> _routePermission = {
  '/purchases':  Perm.purchasesRead,
  '/suppliers':  Perm.suppliersRead,
  '/returns':    Perm.returnsRead,
  '/inventory':  Perm.inventoryRead,
  '/events':          Perm.invoicesRead,
  '/reports/depots':  Perm.reportsReadAll,
  '/statistics':      Perm.reportsReadAll,
  '/hr':         Perm.employeesRead,
  '/settings':    Perm.configUpdate,
  '/warehouses':  Perm.warehousesRead,
};

bool _canShowItem(_NavItem item, UserModel? user) {
  if (kIsWeb && item.route == '/pos') return false; // Caisse non disponible sur web
  final perm = _routePermission[item.route];
  if (perm == null) return true;
  return user?.hasPermission(perm) ?? false;
}

class AppShell extends ConsumerWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final license = ref.watch(licenseProvider).valueOrNull;

    // Blocked: replace entire shell with the block screen
    if (license != null && license.access == LicenseAccess.blocked) {
      return _LicenseBlockedScreen(
        message: license.message ?? 'Accès bloqué.',
        isOffline: license.isOffline,
      );
    }

    final authState = ref.watch(authProvider);
    final shell = context.isMobile
        ? _MobileShell(child: child)
        : _DesktopShell(child: child);

    final banners = <Widget>[];

    // Bandeau d'avertissement plan expirant (vient du login, pour tous les utilisateurs)
    if (authState.planWarning != null) {
      banners.add(_PlanWarningBanner(
        warning: authState.planWarning!,
        onDismiss: () => ref.read(authProvider.notifier).dismissPlanWarning(),
      ));
    }

    // Licence expiry / offline warning
    if (license != null && license.hasWarning && license.message != null) {
      banners.add(_LicenseWarningBanner(
        message: license.message!,
        isOffline: license.isOffline,
      ));
    }

    // Caisse over-limit warning — desktop/web only (billing managed by admin, not cashiers)
    final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (!isAndroid && license != null && license.caisseOverLimit) {
      final extra = license.currentCaisses - license.maxCaisses;
      banners.add(_CaisseOverLimitBanner(
        extra: extra,
        priceHtg: license.pricePerExtraCaisseHtg,
        priceUsd: license.pricePerExtraCaisseUsd,
      ));
    }

    if (banners.isNotEmpty) {
      return Column(
        children: [...banners, Expanded(child: shell)],
      );
    }

    return shell;
  }
}

// ── Desktop shell ─────────────────────────────────────────────────────────

class _DesktopShell extends ConsumerWidget {
  final Widget child;
  const _DesktopShell({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final isAdmin = ref.watch(isAdminProvider);
    final location = GoRouterState.of(context).uri.toString();
    final tenant = ref.watch(tenantProvider).valueOrNull;
    final isCloudMode = tenant != null;
    final businessName = tenant?['business_name'] as String?;
    final displayName = businessName ?? user?.fullName ?? 'Utilisateur';
    final rawInitial = displayName.isNotEmpty ? displayName : 'U';
    final initial = rawInitial[0].toUpperCase();

    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 220,
            color: AppColors.sidebar,
            child: Column(
              children: [
                // Logo / Brand
                Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: const Color(0xFFCC0000), width: 1),
                        ),
                        padding: const EdgeInsets.all(8),
                        child: const PosLogo(width: 40),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Color(0xFF2A3F55), height: 1),
                const SizedBox(height: 8),

                // Scrollable nav
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      // Operations
                      ..._resolveMainNav(ref.watch(settingsProvider).businessType)
                          .where((i) => _canShowItem(i, user))
                          .map((item) => _SidebarItem(
                                item: item,
                                isActive: location.startsWith(item.route),
                                onTap: () => context.go(item.route),
                              )),

                      // Analytics section
                      if (_analyticsNavItems.any((i) => _canShowItem(i, user))) ...[
                        _SectionDivider(label: 'Analyse'),
                        ..._analyticsNavItems
                            .where((i) => _canShowItem(i, user))
                            .map((item) => _SidebarItem(
                                  item: item,
                                  isActive: location.startsWith(item.route),
                                  onTap: () => context.go(item.route),
                                )),
                      ],

                      // HR & Payroll section
                      if (_hrNavItems.any((i) => _canShowItem(i, user))) ...[
                        _SectionDivider(label: 'RH & Paie'),
                        ..._hrNavItems
                            .where((i) => _canShowItem(i, user))
                            .map((item) => _SidebarItem(
                                  item: item,
                                  isActive: location.startsWith(item.route),
                                  onTap: () => context.go(item.route),
                                )),
                      ],

                      // Administration (admin only)
                      if (isAdmin) ...[
                        _SectionDivider(label: 'Administration'),
                        ..._adminNavItems.map((item) => _SidebarItem(
                              item: item,
                              isActive: location.startsWith(item.route),
                              onTap: () => context.go(item.route),
                            )),
                        _SidebarItem(
                          item: const _NavItem('Journal d\'audit',
                              Icons.history_rounded, '/audit'),
                          isActive: location.startsWith('/audit'),
                          onTap: () => context.go('/audit'),
                        ),
                        if (isCloudMode || kIsWeb || isAdmin)
                          _SidebarItem(
                            item: const _NavItem('Abonnement',
                                Icons.workspace_premium_rounded, '/billing'),
                            isActive: location.startsWith('/billing'),
                            onTap: () => context.go('/billing'),
                          ),
                      ],
                    ],
                  ),
                ),

                // Bottom pinned
                const Divider(color: Color(0xFF2A3F55), height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
                  child: Column(
                    children: _bottomNavItems
                        .where((i) => _canShowItem(i, user))
                        .map((item) => _SidebarItem(
                              item: item,
                              isActive: location.startsWith(item.route),
                              onTap: () => context.go(item.route),
                            ))
                        .toList(),
                  ),
                ),

                // User + Logout
                const Divider(color: Color(0xFF2A3F55), height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: AppColors.primary,
                        child: Text(
                          initial,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              user?.username ?? '',
                              style: const TextStyle(
                                  color: Color(0xFF8BA4BE), fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout_rounded,
                            color: Color(0xFF8BA4BE), size: 18),
                        tooltip: 'Déconnexion',
                        onPressed: () =>
                            ref.read(authProvider.notifier).logout(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: Column(
              children: [
                _TopBar(),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sidebar widgets ────────────────────────────────────────────────────────

class _SectionDivider extends StatelessWidget {
  final String label;
  const _SectionDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF4A6278),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final _NavItem item;
  final bool isActive;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: isActive ? AppColors.sidebarSelected : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: AppColors.sidebarHover,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  size: 18,
                  color: isActive
                      ? Colors.white
                      : const Color(0xFF8BA4BE),
                ),
                const SizedBox(width: 10),
                Text(
                  item.label,
                  style: TextStyle(
                    color: isActive
                        ? Colors.white
                        : const Color(0xFFB8CCE0),
                    fontSize: 13,
                    fontWeight: isActive
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Top bar ────────────────────────────────────────────────────────────────

class _TopBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = GoRouterState.of(context).uri.toString();
    final title = _allNavItems
        .firstWhere(
          (i) => route.startsWith(i.route),
          orElse: () => const _NavItem('', Icons.home, '/'),
        )
        .label;

    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          const _WarehouseSelector(),
          const SizedBox(width: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.circle, size: 8, color: AppColors.accent),
                const SizedBox(width: 6),
                const Text(
                  'Connecté',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.accent,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Warehouse selector dropdown ───────────────────────────────────────────

class _WarehouseSelector extends ConsumerWidget {
  const _WarehouseSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final warehouses = ref.watch(warehouseListProvider).valueOrNull ?? [];
    final active    = ref.watch(activeWarehouseProvider);
    final canSwitch = ref.watch(hasPermissionProvider(Perm.configUpdate));
    final user      = ref.watch(authProvider).user;

    // Init selection when list loads — restrict to user's assigned warehouses
    if (warehouses.isNotEmpty) {
      Future.microtask(() =>
          ref.read(activeWarehouseProvider.notifier).initFromList(
            warehouses,
            userWarehouseIds: user?.warehouseIds ?? [],
          ));
    }

    // Toujours résoudre le dépôt courant (fallback sur défaut ou premier)
    final current = warehouses.isEmpty
        ? null
        : warehouses.firstWhere(
            (w) => w.id == (active?.id ?? ''),
            orElse: () => warehouses.firstWhere(
              (w) => w.isDefault,
              orElse: () => warehouses.first,
            ),
          );

    // Afficher toujours le nom du dépôt courant (même s'il n'y en a qu'un)
    final label = current?.name ?? active?.name ?? 'Dépôt';
    final isDefault = current?.isDefault ?? false;

    final canChange = canSwitch && warehouses.length > 1;

    final decoration = BoxDecoration(
      border: Border.all(color: AppColors.divider),
      borderRadius: BorderRadius.circular(8),
      color: AppColors.background,
    );

    // Badge « défaut »
    Widget defaultBadge() => Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text('défaut',
              style: TextStyle(fontSize: 10, color: AppColors.primary)),
        );

    // Version lecture seule (1 dépôt ou pas permission)
    if (!canChange) {
      return Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: decoration,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warehouse_outlined, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary)),
            if (isDefault) ...[const SizedBox(width: 4), defaultBadge()],
          ],
        ),
      );
    }

    // Version dropdown (multi-dépôts + permission)
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: decoration,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<WarehouseModel>(
          value: current,
          isDense: true,
          icon: const Icon(Icons.expand_more, size: 16, color: AppColors.textSecondary),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
          items: warehouses.map((w) => DropdownMenuItem(
            value: w,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warehouse_outlined, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(w.name),
                if (w.isDefault) ...[const SizedBox(width: 4), defaultBadge()],
              ],
            ),
          )).toList(),
          onChanged: (w) {
            if (w != null) {
              ref.read(activeWarehouseProvider.notifier).setWarehouse(w);
            }
          },
        ),
      ),
    );
  }
}

// ── Mobile shell ───────────────────────────────────────────────────────────

class _MobileShell extends ConsumerStatefulWidget {
  final Widget child;
  const _MobileShell({required this.child});

  @override
  ConsumerState<_MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends ConsumerState<_MobileShell> {
  Timer? _pendingRefreshTimer;
  bool _isSyncing = false;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    if (_isAndroid) {
      // Rafraîchit le compteur d'opérations en attente toutes les 10 secondes.
      _pendingRefreshTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => ref.invalidate(pendingOfflineCountProvider),
      );
    }
  }

  @override
  void dispose() {
    _pendingRefreshTimer?.cancel();
    super.dispose();
  }

  void _showPaperSizeSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _PrintSettingsSheet(),
    );
  }

  void _showDebugSheet(BuildContext context, WidgetRef ref) {
    final user = ref.read(authProvider).user;
    final active = ref.read(activeWarehouseProvider);
    final whAsync = ref.read(warehouseListProvider);
    final warehouses = whAsync.valueOrNull ?? [];
    final whState = whAsync.when(
      data: (d) => 'OK (${d.length} dépôt${d.length == 1 ? '' : 's'})',
      loading: () => '⏳ chargement...',
      error: (e, _) => '❌ ERREUR: $e',
    );
    final hasRestriction = (user?.warehouseIds ?? []).isNotEmpty;
    final apiWh = hasRestriction ? active?.id : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final screenH = MediaQuery.sizeOf(ctx).height;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: screenH * 0.75),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Debug — Warehouse', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const Divider(),
                  _DebugRow('Utilisateur', user?.username ?? '—'),
                  _DebugRow('Rôles', user?.roles.join(', ') ?? '—'),
                  _DebugRow('warehouseIds (user)', user?.warehouseIds.isEmpty == true ? '[] (accès total)' : user?.warehouseIds.join(', ') ?? '—'),
                  const Divider(),
                  _DebugRow('Dépôt actif (provider)', active != null ? '${active.name} (${active.id})' : '⚠ null'),
                  _DebugRow('hasRestriction', '$hasRestriction'),
                  _DebugRow('warehouseId envoyé API', apiWh ?? 'null → backend retourne tout'),
                  const Divider(),
                  _DebugRow('Provider état', whState),
                  _DebugRow('Dépôts disponibles (${warehouses.length})',
                      warehouses.isEmpty ? '—' : warehouses.map((w) => '${w.name}${w.isDefault ? " ★" : ""}').join(', ')),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _syncNow() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    try {
      await OfflineQueueService.instance.drain(dio);
    } finally {
      ref.invalidate(pendingOfflineCountProvider);
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final isAdmin = ref.watch(isAdminProvider);
    final user = ref.watch(authProvider).user;

    final businessType = ref.watch(settingsProvider).businessType;
    final bottomItems = _isAndroid
        ? _resolveAndroidBottom(businessType).toList()
        : _resolveMainNav(businessType).take(5).toList();

    // Sur Android, _WarehouseSelector n'est pas affiché → initFromList n'est jamais
    // appelé. On le fait ici pour que le dépôt actif soit correctement initialisé.
    if (_isAndroid) {
      final warehouses = ref.watch(warehouseListProvider).valueOrNull ?? [];
      final active = ref.watch(activeWarehouseProvider);
      debugPrint('[WH-DEBUG] build: user=${user?.username} warehouseIds=${user?.warehouseIds} '
          'active=${active?.name}(${active?.id}) warehouses=${warehouses.map((w) => "${w.name}:${w.id}").toList()}');
      if (warehouses.isNotEmpty) {
        Future.microtask(() async {
          await ref.read(activeWarehouseProvider.notifier).initFromList(
            warehouses,
            userWarehouseIds: user?.warehouseIds ?? [],
          );
          final selected = ref.read(activeWarehouseProvider);
          final hasRestriction = (user?.warehouseIds ?? []).isNotEmpty;
          final apiWh = hasRestriction ? selected?.id : null;
          debugPrint('[WH-DEBUG] initFromList done → selected=${selected?.name}(${selected?.id}) '
              'hasRestriction=$hasRestriction apiWarehouseId=$apiWh');
        });
      }
    }

    final currentIndex =
        bottomItems.indexWhere((i) => location.startsWith(i.route));

    final pageTitle = _allNavItems
        .firstWhere(
          (i) => location.startsWith(i.route),
          orElse: () => const _NavItem('POS Connect', Icons.home, '/'),
        )
        .label;

    final pendingCount = _isAndroid
        ? (ref.watch(pendingOfflineCountProvider).valueOrNull ?? 0)
        : 0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: Text(
          pageTitle,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          // Indicateur dépôt actif — visible sur web (pas sur Android natif)
          if (!_isAndroid)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Center(child: _WarehouseSelector()),
            ),
          // Bouton taille papier imprimante — Android seulement
          if (_isAndroid)
            IconButton(
              icon: const Icon(Icons.receipt_long_outlined, size: 20,
                  color: AppColors.textSecondary),
              tooltip: 'Taille papier imprimante',
              onPressed: () => _showPaperSizeSheet(context, ref),
            ),
          // Bouton debug — Android seulement
          if (_isAndroid)
            IconButton(
              icon: const Icon(Icons.bug_report_outlined, size: 20,
                  color: AppColors.textSecondary),
              tooltip: 'Debug warehouse',
              onPressed: () => _showDebugSheet(context, ref),
            ),
          // Actions Android : sync + connecté
          if (_isAndroid)
            if (_isSyncing)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.accent),
                ),
              )
            else if (pendingCount > 0)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton.icon(
                  onPressed: _syncNow,
                  icon: const Icon(Icons.sync_rounded, size: 16),
                  label: Text('$pendingCount en attente'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.orange,
                    textStyle: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 8, color: AppColors.accent),
                    const SizedBox(width: 4),
                    Text(
                      'Connecté',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.accent,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.divider),
        ),
      ),
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex < 0 ? 0 : currentIndex,
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.15),
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        onDestinationSelected: (i) => context.go(bottomItems[i].route),
        destinations: bottomItems
            .map((item) => NavigationDestination(
                  icon: Icon(item.icon),
                  label: item.label,
                ))
            .toList(),
      ),
      drawer: Drawer(
        backgroundColor: AppColors.sidebar,
        child: Column(
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: AppColors.sidebar),
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.point_of_sale,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'POS Connect',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: _isAndroid
                    ? _buildAndroidDrawerItems(context, location, isAdmin, user,
                        ref.watch(settingsProvider).businessType)
                    : _buildFullDrawerItems(context, location, isAdmin, user,
                        ref.watch(settingsProvider).businessType),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Color(0xFF8BA4BE)),
              title: const Text('Déconnexion',
                  style: TextStyle(color: Colors.white)),
              onTap: () => ref.read(authProvider.notifier).logout(),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildAndroidDrawerItems(
    BuildContext context,
    String location,
    bool isAdmin,
    UserModel? user,
    String businessType,
  ) {
    void go(String route) {
      Navigator.pop(context);
      context.go(route);
    }

    final mainItems = businessType == 'restaurant'
        ? _restaurantMainNavItems
        : businessType == 'hotel'
            ? _hotelMainNavItems
            : _androidDrawerMainItems;

    return [
      ...mainItems.map((item) => _SidebarItem(
            item: item,
            isActive: location.startsWith(item.route),
            onTap: () => go(item.route),
          )),
      if (isAdmin) ...[
        _SectionDivider(label: 'Administration'),
        ..._adminNavItems.map((item) => _SidebarItem(
              item: item,
              isActive: location.startsWith(item.route),
              onTap: () => go(item.route),
            )),
        // Business — affiché ici seulement s'il n'est pas déjà dans mainItems
        if (!mainItems.any((i) => i.route == '/warehouses'))
          _SidebarItem(
            item: const _NavItem('Business', Icons.apartment_rounded, '/warehouses'),
            isActive: location.startsWith('/warehouses'),
            onTap: () => go('/warehouses'),
          ),
      ],
      _SectionDivider(label: 'Compte'),
      ..._bottomNavItems
          .where((i) => _canShowItem(i, user))
          .map((item) => _SidebarItem(
                item: item,
                isActive: location.startsWith(item.route),
                onTap: () => go(item.route),
              )),
    ];
  }

  List<Widget> _buildFullDrawerItems(
    BuildContext context,
    String location,
    bool isAdmin,
    UserModel? user,
    String businessType,
  ) {
    void go(String route) {
      Navigator.pop(context);
      context.go(route);
    }

    return [
      ..._resolveMainNav(businessType)
          .where((i) => _canShowItem(i, user))
          .map((item) => _SidebarItem(
                item: item,
                isActive: location.startsWith(item.route),
                onTap: () => go(item.route),
              )),
      if (_analyticsNavItems.any((i) => _canShowItem(i, user))) ...[
        _SectionDivider(label: 'Analyse'),
        ..._analyticsNavItems
            .where((i) => _canShowItem(i, user))
            .map((item) => _SidebarItem(
                  item: item,
                  isActive: location.startsWith(item.route),
                  onTap: () => go(item.route),
                )),
      ],
      if (_hrNavItems.any((i) => _canShowItem(i, user))) ...[
        _SectionDivider(label: 'RH & Paie'),
        ..._hrNavItems
            .where((i) => _canShowItem(i, user))
            .map((item) => _SidebarItem(
                  item: item,
                  isActive: location.startsWith(item.route),
                  onTap: () => go(item.route),
                )),
      ],
      if (isAdmin) ...[
        _SectionDivider(label: 'Administration'),
        ..._adminNavItems.map((item) => _SidebarItem(
              item: item,
              isActive: location.startsWith(item.route),
              onTap: () => go(item.route),
            )),
        _SidebarItem(
          item: const _NavItem(
              'Journal d\'audit', Icons.history_rounded, '/audit'),
          isActive: location.startsWith('/audit'),
          onTap: () => go('/audit'),
        ),
      ],
      _SectionDivider(label: 'Compte'),
      ..._bottomNavItems
          .where((i) => _canShowItem(i, user))
          .map((item) => _SidebarItem(
                item: item,
                isActive: location.startsWith(item.route),
                onTap: () => go(item.route),
              )),
    ];
  }
}

// ── Debug helper ──────────────────────────────────────────────────────────────

class _DebugRow extends StatelessWidget {
  final String label;
  final String value;
  const _DebugRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// License widgets
// ═════════════════════════════════════════════════════════════════════════════

// ── Bandeau avertissement plan expirant ───────────────────────────────────────

class _PlanWarningBanner extends StatelessWidget {
  final Map<String, dynamic> warning;
  final VoidCallback onDismiss;

  const _PlanWarningBanner({required this.warning, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final daysLeft = warning['days_left'] as int? ?? 0;
    final type = warning['type'] as String? ?? 'trial';
    final label = type == 'trial' ? "période d'essai" : 'abonnement';

    final String msg;
    if (daysLeft == 0) {
      msg = 'Votre $label expire aujourd\'hui. Renouvelez maintenant.';
    } else if (daysLeft == 1) {
      msg = 'Votre $label expire demain. Renouvelez maintenant.';
    } else {
      msg = 'Votre $label expire dans $daysLeft jours. Renouvelez maintenant.';
    }

    return Material(
      color: const Color(0xFFD97706), // amber-600
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.access_time_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  msg,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => context.go('/billing'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                  ),
                ),
                child: const Text('Renouveler'),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Bandeau avertissement licence (offline / expiry via signed blob) ──────────

class _LicenseWarningBanner extends StatefulWidget {
  final String message;
  final bool isOffline;
  const _LicenseWarningBanner({required this.message, required this.isOffline});

  @override
  State<_LicenseWarningBanner> createState() => _LicenseWarningBannerState();
}

class _LicenseWarningBannerState extends State<_LicenseWarningBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    return Material(
      color: widget.isOffline ? const Color(0xFFF59E0B) : const Color(0xFFEF4444),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                widget.isOffline ? Icons.wifi_off_rounded : Icons.warning_amber_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => setState(() => _dismissed = true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LicenseBlockedScreen extends StatelessWidget {
  final String message;
  final bool isOffline;
  const _LicenseBlockedScreen({required this.message, required this.isOffline});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B2A3B),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isOffline ? Icons.wifi_off_rounded : Icons.lock_rounded,
                  color: Colors.redAccent,
                  size: 36,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                isOffline ? 'Connexion requise' : 'Accès suspendu',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 32),
              if (isOffline)
                FilledButton.icon(
                  onPressed: () => context.go('/dashboard'),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Réessayer'),
                )
              else
                FilledButton.icon(
                  onPressed: () => context.go('/billing'),
                  icon: const Icon(Icons.credit_card_rounded),
                  label: const Text('Voir les abonnements'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CaisseOverLimitBanner extends StatefulWidget {
  final int extra;
  final double priceHtg;
  final double priceUsd;
  const _CaisseOverLimitBanner({
    required this.extra,
    required this.priceHtg,
    required this.priceUsd,
  });

  @override
  State<_CaisseOverLimitBanner> createState() => _CaisseOverLimitBannerState();
}

class _CaisseOverLimitBannerState extends State<_CaisseOverLimitBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    final totalHtg = (widget.extra * widget.priceHtg).toStringAsFixed(0);
    final totalUsd = (widget.extra * widget.priceUsd).toStringAsFixed(2);
    return Material(
      color: Colors.orange.shade700,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.point_of_sale_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${widget.extra} caisse(s) supplémentaire(s) — ${widget.extra} × ${widget.priceHtg.toStringAsFixed(0)} HTG = $totalHtg HTG / $totalUsd USD/mois',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 16),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => setState(() => _dismissed = true),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sheet : paramètres d'impression (papier + imprimante BT) ─────────────────

class _PrintSettingsSheet extends ConsumerStatefulWidget {
  const _PrintSettingsSheet();

  @override
  ConsumerState<_PrintSettingsSheet> createState() =>
      _PrintSettingsSheetState();
}

class _PrintSettingsSheetState extends ConsumerState<_PrintSettingsSheet> {
  List<BluetoothInfo>? _paired;
  bool _loadingBt = false;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    if (_isAndroid) _loadPaired();
  }

  Future<void> _loadPaired() async {
    setState(() => _loadingBt = true);
    try {
      _paired = await BluetoothPrintService.instance.getPairedPrinters();
    } catch (_) {
      _paired = [];
    }
    if (mounted) setState(() => _loadingBt = false);
  }

  Future<void> _selectPrinter(String mac, String name) async {
    final s = ref.read(settingsProvider);
    await ref.read(settingsProvider.notifier).save(
          s.copyWith(bluetoothPrinterMac: mac, bluetoothPrinterName: name),
        );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _clearPrinter() async {
    final s = ref.read(settingsProvider);
    await ref.read(settingsProvider.notifier).save(
          s.copyWith(bluetoothPrinterMac: '', bluetoothPrinterName: ''),
        );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final savedMac = settings.bluetoothPrinterMac;
    final savedName = settings.bluetoothPrinterName;

    final screenH = MediaQuery.sizeOf(context).height;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: screenH * 0.82),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // ── Titre ──────────────────────────────────────────────────────
            const Row(children: [
              Icon(Icons.print_outlined, size: 20),
              SizedBox(width: 8),
              Text('Paramètres d\'impression',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ]),
            const SizedBox(height: 20),

            // ── Taille du papier ───────────────────────────────────────────
            const Text('Taille du papier',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                    value: 58,
                    icon: Icon(Icons.receipt_outlined, size: 16),
                    label: Text('58 mm')),
                ButtonSegment(
                    value: 80,
                    icon: Icon(Icons.receipt_long_outlined, size: 16),
                    label: Text('80 mm')),
              ],
              selected: {settings.paperWidth},
              onSelectionChanged: (val) async {
                await ref.read(settingsProvider.notifier).save(
                      settings.copyWith(paperWidth: val.first),
                    );
              },
            ),

            // ── Imprimante BT (Android uniquement) ─────────────────────────
            if (_isAndroid) ...[
              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 16),
              Row(children: [
                const Text('Imprimante Bluetooth',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
                const Spacer(),
                if (_loadingBt)
                  const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                else
                  GestureDetector(
                    onTap: _loadPaired,
                    child: const Icon(Icons.refresh_rounded,
                        size: 18, color: AppColors.textSecondary),
                  ),
              ]),
              const SizedBox(height: 8),

              // Imprimante sauvegardée
              if (savedMac.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.check_circle_rounded,
                        color: AppColors.primary, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              savedName.isNotEmpty ? savedName : savedMac,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13)),
                          Text(savedMac,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _clearPrinter,
                      style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8)),
                      child: const Text('Effacer',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ]),
                ),

              // Liste des appareils appairés
              if (_loadingBt)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Recherche...',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                )
              else if (_paired == null || _paired!.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Aucune imprimante appairée trouvée',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                )
              else
                ..._paired!.map((d) {
                  final isSelected = savedMac == d.macAdress;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(Icons.bluetooth_rounded,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        size: 20),
                    title: Text(d.name,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: isSelected ? AppColors.primary : null)),
                    subtitle: Text(d.macAdress,
                        style: const TextStyle(fontSize: 11)),
                    trailing: isSelected
                        ? const Icon(Icons.check_rounded,
                            color: AppColors.primary, size: 18)
                        : null,
                    onTap: () => _selectPrinter(d.macAdress, d.name),
                  );
                }),
            ],
            const SizedBox(height: 4),
          ],
        ),
        ),
      ),
    );
  }
}
