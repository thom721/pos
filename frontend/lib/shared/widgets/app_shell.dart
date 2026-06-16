import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_connect/core/permissions.dart';
import 'package:pos_connect/core/responsive.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/models/user_model.dart';
import 'package:pos_connect/providers/auth_provider.dart';
import 'package:pos_connect/providers/license_provider.dart';
import 'package:pos_connect/providers/permission_provider.dart';
import 'package:pos_connect/services/license_service.dart';

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
  _NavItem('Inventaire', Icons.warehouse_rounded, '/inventory'),
];

const _analyticsNavItems = [
  _NavItem('Événements', Icons.event_note_rounded, '/events'),
  _NavItem('Rapports', Icons.assessment_rounded, '/reports'),
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

// All items for title lookup
const _allNavItems = [
  ..._mainNavItems,
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
  '/events':     Perm.reportsReadAll,
  '/statistics': Perm.reportsReadAll,
  '/hr':         Perm.employeesRead,
  '/settings':   Perm.configUpdate,
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

    final shell = context.isMobile
        ? _MobileShell(child: child)
        : _DesktopShell(child: child);

    final banners = <Widget>[];

    // Licence expiry / offline warning
    if (license != null && license.hasWarning && license.message != null) {
      banners.add(_LicenseWarningBanner(
        message: license.message!,
        isOffline: license.isOffline,
      ));
    }

    // Caisse over-limit warning (non-blocking)
    if (license != null && license.caisseOverLimit) {
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
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.point_of_sale,
                            color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'POS Connect',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
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
                      ..._mainNavItems
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
                        if (isCloudMode)
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

// ── Mobile shell ───────────────────────────────────────────────────────────

class _MobileShell extends ConsumerStatefulWidget {
  final Widget child;
  const _MobileShell({required this.child});

  @override
  ConsumerState<_MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends ConsumerState<_MobileShell> {
  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final isAdmin = ref.watch(isAdminProvider);
    final user = ref.watch(authProvider).user;
    final bottomItems = _mainNavItems.take(5).toList();
    final currentIndex =
        bottomItems.indexWhere((i) => location.startsWith(i.route));

    final pageTitle = _allNavItems
        .firstWhere(
          (i) => location.startsWith(i.route),
          orElse: () => const _NavItem('POS Connect', Icons.home, '/'),
        )
        .label;

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
        labelBehavior:
            NavigationDestinationLabelBehavior.onlyShowSelected,
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
                    width: 36,
                    height: 36,
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
                children: [
                  ..._mainNavItems
                      .where((i) => _canShowItem(i, user))
                      .map((item) => _SidebarItem(
                            item: item,
                            isActive: location.startsWith(item.route),
                            onTap: () {
                              Navigator.pop(context);
                              context.go(item.route);
                            },
                          )),
                  if (_analyticsNavItems.any((i) => _canShowItem(i, user))) ...[
                    _SectionDivider(label: 'Analyse'),
                    ..._analyticsNavItems
                        .where((i) => _canShowItem(i, user))
                        .map((item) => _SidebarItem(
                              item: item,
                              isActive: location.startsWith(item.route),
                              onTap: () {
                                Navigator.pop(context);
                                context.go(item.route);
                              },
                            )),
                  ],
                  if (_hrNavItems.any((i) => _canShowItem(i, user))) ...[
                    _SectionDivider(label: 'RH & Paie'),
                    ..._hrNavItems
                        .where((i) => _canShowItem(i, user))
                        .map((item) => _SidebarItem(
                              item: item,
                              isActive: location.startsWith(item.route),
                              onTap: () {
                                Navigator.pop(context);
                                context.go(item.route);
                              },
                            )),
                  ],
                  if (isAdmin) ...[
                    _SectionDivider(label: 'Administration'),
                    ..._adminNavItems.map((item) => _SidebarItem(
                          item: item,
                          isActive: location.startsWith(item.route),
                          onTap: () {
                            Navigator.pop(context);
                            context.go(item.route);
                          },
                        )),
                  ],
                  _SectionDivider(label: 'Compte'),
                  ..._bottomNavItems
                      .where((i) => _canShowItem(i, user))
                      .map((item) => _SidebarItem(
                            item: item,
                            isActive: location.startsWith(item.route),
                            onTap: () {
                              Navigator.pop(context);
                              context.go(item.route);
                            },
                          )),
                ],
              ),
            ),
            ListTile(
              leading:
                  const Icon(Icons.logout, color: Color(0xFF8BA4BE)),
              title: const Text('Déconnexion',
                  style: TextStyle(color: Colors.white)),
              onTap: () => ref.read(authProvider.notifier).logout(),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// License widgets
// ═════════════════════════════════════════════════════════════════════════════

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
