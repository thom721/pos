import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pos_connect/core/date_utils.dart' show haitiNow;
import 'package:pos_connect/core/permissions.dart';
import 'package:pos_connect/core/responsive.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/providers/auth_provider.dart';
import 'package:pos_connect/providers/sale_provider.dart';
import 'package:pos_connect/providers/debt_provider.dart';
import 'package:pos_connect/providers/settings_provider.dart';
import 'package:pos_connect/shared/widgets/stat_card.dart';
import 'package:pos_connect/shared/widgets/status_badge.dart';

final _fmt = NumberFormat.currency(locale: 'fr_HT', symbol: 'HTG ', decimalDigits: 2);

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final isCashier = !(user?.hasPermission(Perm.reportsReadAll) ?? false);
    final salesAsync = ref.watch(dashboardSalesProvider(isCashier));
    final debtsAsync = ref.watch(debtsProvider);
    final businessType = ref.watch(settingsProvider).businessType;
    final isOrderBased = businessType == 'restaurant' || businessType == 'hotel';

    final pad = context.hPad;
    final isMobile = context.isMobile;

    final cashierRoute = isOrderBased ? '/restaurant/commandes' : '/pos';
    final cashierIcon = isOrderBased
        ? Icons.restaurant_rounded
        : Icons.point_of_sale_rounded;
    final cashierLabel = isOrderBased ? 'Commandes' : 'Ouvrir la caisse';

    return SingleChildScrollView(
      padding: EdgeInsets.all(pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Greeting — Row on desktop, Column on mobile
          if (isMobile) ...[
            Text('Bienvenue 👋',
                style: Theme.of(context).textTheme.displayMedium),
            const SizedBox(height: 2),
            Text(
              DateFormat('EEEE d MMMM yyyy', 'fr').format(haitiNow()),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            if (!kIsWeb)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => context.go(cashierRoute),
                  icon: Icon(cashierIcon, size: 18),
                  label: Text(cashierLabel),
                ),
              ),
          ] else
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Bienvenue 👋',
                        style: Theme.of(context).textTheme.displayMedium),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('EEEE d MMMM yyyy', 'fr').format(haitiNow()),
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
                const Spacer(),
                if (!kIsWeb)
                  ElevatedButton.icon(
                    onPressed: () => context.go(cashierRoute),
                    icon: Icon(cashierIcon, size: 18),
                    label: Text(cashierLabel),
                  ),
              ],
            ),
          const SizedBox(height: 24),

          // Stats cards
          salesAsync.when(
            skipLoadingOnRefresh: true,
            skipLoadingOnReload: true,
            data: (sales) {
              final totalRevenue =
                  sales.data.fold(0.0, (s, e) => s + e.finalAmount);
              final totalPaid =
                  sales.data.fold(0.0, (s, e) => s + e.paidAmount);
              final countSales = sales.meta.total;

              return _ResponsiveGrid(
                children: [
                  StatCard(
                    label: isCashier ? 'Mes ventes (aujourd\'hui)' : 'Ventes du jour',
                    value: countSales.toString(),
                    icon: Icons.receipt_long_rounded,
                    color: AppColors.primary,
                    subtitle: '${sales.data.length} récentes',
                  ),
                  StatCard(
                    label: 'Chiffre d\'affaires',
                    value: _fmt.format(totalRevenue),
                    icon: Icons.trending_up_rounded,
                    color: AppColors.accent,
                  ),
                  StatCard(
                    label: 'Montant encaissé',
                    value: _fmt.format(totalPaid),
                    icon: Icons.account_balance_wallet_rounded,
                    color: AppColors.info,
                  ),
                  StatCard(
                    label: 'Solde à recouvrer',
                    value: _fmt.format(totalRevenue - totalPaid),
                    icon: Icons.warning_amber_rounded,
                    color: AppColors.warning,
                  ),
                ],
              );
            },
            loading: () => const _StatsSkeletons(),
            error: (e, _) => _ErrorCard(message: 'Impossible de charger les données. Vérifiez votre connexion.'),
          ),
          const SizedBox(height: 28),

          // Quick actions
          Text('Actions rapides',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _QuickAction(
                icon: Icons.add_shopping_cart_rounded,
                label: isOrderBased ? 'Nouvelle commande' : 'Nouvelle vente',
                color: AppColors.primary,
                onTap: () => context.go(cashierRoute),
              ),
              _QuickAction(
                icon: Icons.people_alt_rounded,
                label: 'Clients',
                color: AppColors.info,
                onTap: () => context.go('/customers'),
              ),
              _QuickAction(
                icon: Icons.inventory_2_rounded,
                label: 'Produits',
                color: AppColors.accent,
                onTap: () => context.go('/products'),
              ),
              _QuickAction(
                icon: Icons.local_shipping_rounded,
                label: 'Nouvel achat',
                color: AppColors.warning,
                onTap: () => context.go('/purchases'),
              ),
              _QuickAction(
                icon: Icons.account_balance_wallet_rounded,
                label: 'Dettes',
                color: AppColors.error,
                onTap: () => context.go('/debts'),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Recent sales
          Row(
            children: [
              Text('Ventes récentes',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton(
                onPressed: () => context.go('/sales'),
                child: const Text('Voir tout →'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          salesAsync.when(
            skipLoadingOnRefresh: true,
            skipLoadingOnReload: true,
            data: (sales) => Card(
              child: Column(
                children: sales.data.take(5).map((sale) {
                  return Column(
                    children: [
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.receipt_rounded,
                              color: AppColors.primary, size: 20),
                        ),
                        title: Text(sale.reference,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Text(
                          sale.customerName ?? 'Client comptoir',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12),
                        ),
                        trailing: SizedBox(
                          height: 52,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(_fmt.format(sale.finalAmount),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700, fontSize: 14)),
                              const SizedBox(height: 2),
                              StatusBadge(status: sale.status),
                            ],
                          ),
                        ),
                      ),
                      if (sale != sales.data.take(5).last)
                        const Divider(height: 1),
                    ],
                  );
                }).toList(),
              ),
            ),
            loading: () => const Card(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
            error: (e, _) => _ErrorCard(message: 'Impossible de charger les ventes'),
          ),

          const SizedBox(height: 28),

          // Debts summary
          Row(
            children: [
              Text('Dettes récentes',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton(
                onPressed: () => context.go('/debts'),
                child: const Text('Voir tout →'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          debtsAsync.when(
            data: (debts) => Card(
              child: debts.data.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Text('Aucune dette enregistrée',
                            style: TextStyle(color: AppColors.textSecondary)),
                      ),
                    )
                  : Column(
                      children: debts.data.take(4).map((debt) {
                        return Column(
                          children: [
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.error.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  debt.partnerType == 'CUSTOMER'
                                      ? Icons.person_rounded
                                      : Icons.local_shipping_rounded,
                                  color: AppColors.error,
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                debt.partnerType == 'CUSTOMER'
                                    ? 'Client'
                                    : 'Fournisseur',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                              subtitle: Text(debt.referenceType,
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12)),
                              trailing: SizedBox(
                                height: 52,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(_fmt.format(debt.balance),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                            color: AppColors.error)),
                                    const SizedBox(height: 2),
                                    StatusBadge(status: debt.status),
                                  ],
                                ),
                              ),
                            ),
                            if (debt != debts.data.take(4).last)
                              const Divider(height: 1),
                          ],
                        );
                      }).toList(),
                    ),
            ),
            loading: () => const Card(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
            error: (e, _) =>
                _ErrorCard(message: 'Impossible de charger les dettes'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  const _ResponsiveGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    final width = context.screenWidth;
    final int cols;
    final double ratio;

    if (width >= AppBreakpoints.xl) {
      cols = 4;
      ratio = 2.2;
    } else if (width >= AppBreakpoints.md) {
      cols = 2;
      ratio = 2.0;
    } else {
      cols = 1;
      ratio = 3.2;
    }

    return GridView.count(
      crossAxisCount: cols,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: ratio,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: children,
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _StatsSkeletons extends StatelessWidget {
  const _StatsSkeletons();

  @override
  Widget build(BuildContext context) {
    final width = context.screenWidth;
    final cols = width >= AppBreakpoints.md ? 2 : 1;
    return GridView.count(
      crossAxisCount: cols,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: cols == 1 ? 3.2 : 2.0,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: List.generate(
        4,
        (_) => Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.error),
            const SizedBox(width: 8),
            Expanded(child: Text(message, style: const TextStyle(color: AppColors.error))),
          ],
        ),
      ),
    );
  }
}
