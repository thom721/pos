import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/providers/admin_provider.dart';

// ── Data providers ──────────────────────────────────────────────────────────

final _statsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final d = await ref.watch(adminDioProvider.future);
  final res = await d.get('/api/admin/stats');
  return res.data as Map<String, dynamic>;
});

final _tenantsProvider =
    FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final d = await ref.watch(adminDioProvider.future);
  final res = await d.get('/api/admin/tenants');
  return res.data as List<dynamic>;
});

final _paymentsProvider =
    FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final d = await ref.watch(adminDioProvider.future);
  final res = await d.get('/api/admin/payments');
  return res.data as List<dynamic>;
});

final _platformConfigProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final d = await ref.watch(adminDioProvider.future);
  final res = await d.get('/api/admin/platform-config');
  return res.data as Map<String, dynamic>;
});

// ── Main screen ─────────────────────────────────────────────────────────────

class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adminState = ref.watch(adminProvider);

    if (!adminState.isAuthenticated) {
      return const _AdminLoginScreen();
    }

    return const _AdminDashboard();
  }
}

// ── Login screen ─────────────────────────────────────────────────────────────

class _AdminLoginScreen extends ConsumerStatefulWidget {
  const _AdminLoginScreen();

  @override
  ConsumerState<_AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends ConsumerState<_AdminLoginScreen> {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final ok = await ref.read(adminProvider.notifier).login(
      _emailCtrl.text.trim(),
      _passwordCtrl.text,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ref.read(adminProvider).error ?? 'Erreur de connexion'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.admin_panel_settings,
                      size: 48, color: AppColors.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Administration POS Connect',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Panneau super-admin — réservé au propriétaire de la plateforme',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email admin',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    onSubmitted: (_) => _login(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordCtrl,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'Mot de passe',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                            _obscure ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    onSubmitted: (_) => _login(),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: state.isLoading ? null : _login,
                    child: state.isLoading
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Se connecter'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Dashboard (tabbed) ───────────────────────────────────────────────────────

class _AdminDashboard extends ConsumerWidget {
  const _AdminDashboard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Admin POS Connect'),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Se déconnecter',
              onPressed: () => ref.read(adminProvider.notifier).logout(),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.store), text: 'Boutiques'),
              Tab(icon: Icon(Icons.payments), text: 'Paiements'),
              Tab(icon: Icon(Icons.settings), text: 'Paramètres'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _TenantsTab(),
            _PaymentsTab(),
            _PlatformConfigTab(),
          ],
        ),
      ),
    );
  }
}

// ── Tab 1 — Boutiques ────────────────────────────────────────────────────────

class _TenantsTab extends ConsumerWidget {
  const _TenantsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantsAsync = ref.watch(_tenantsProvider);

    return tenantsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        message: e.toString(),
        onRetry: () => ref.invalidate(_tenantsProvider),
      ),
      data: (tenants) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(_tenantsProvider),
        child: tenants.isEmpty
            ? const Center(child: Text('Aucune boutique trouvée'))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: tenants.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final t = tenants[i] as Map<String, dynamic>;
                  return _TenantCard(tenant: t);
                },
              ),
      ),
    );
  }
}

class _TenantCard extends ConsumerWidget {
  final Map<String, dynamic> tenant;
  const _TenantCard({required this.tenant});

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return AppColors.success;
      case 'trial':
        return Colors.amber;
      case 'suspended':
        return AppColors.error;
      case 'expired':
        return Colors.deepOrange;
      default:
        return AppColors.textSecondary;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'active':
        return 'Actif';
      case 'trial':
        return 'Essai';
      case 'suspended':
        return 'Suspendu';
      case 'expired':
        return 'Expiré';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = tenant['status'] as String? ?? 'trial';
    final daysLeft = tenant['days_left'] as int?;
    final paymentCount = tenant['payment_count'] as int? ?? 0;
    final createdAt = tenant['created_at'] as String?;
    final isActive = status == 'active';
    final maxCaisses       = tenant['max_caisses']    as int? ?? 1;
    final maxDepots        = tenant['max_depots']     as int? ?? 1;
    final registerCount    = tenant['register_count'] as int? ?? 0;
    final depotCount       = tenant['depot_count']    as int? ?? 0;
    final canManageTenants = tenant['can_manage_tenants'] as bool? ?? false;

    String? formattedDate;
    if (createdAt != null) {
      try {
        formattedDate = DateFormat('dd/MM/yyyy').format(DateTime.parse(createdAt));
      } catch (_) {}
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tenant['business_name'] as String? ?? '—',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _StatusBadge(
                  label: _statusLabel(status),
                  color: _statusColor(status),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              tenant['owner_email'] as String? ?? '',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (status == 'trial' && daysLeft != null) ...[
                  Icon(Icons.timer_outlined,
                      size: 14,
                      color: daysLeft < 5 ? AppColors.error : AppColors.warning),
                  const SizedBox(width: 4),
                  Text(
                    '$daysLeft j restants',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: daysLeft < 5
                              ? AppColors.error
                              : AppColors.warning,
                        ),
                  ),
                  const SizedBox(width: 16),
                ],
                Icon(Icons.receipt_outlined,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  '$paymentCount paiement${paymentCount != 1 ? 's' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                if (formattedDate != null)
                  Text(
                    formattedDate,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.point_of_sale_rounded,
                    size: 13, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  '$registerCount / $maxCaisses caisse${maxCaisses > 1 ? 's' : ''}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: registerCount >= maxCaisses
                            ? AppColors.warning
                            : AppColors.textSecondary,
                      ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.store_rounded,
                    size: 13, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  '$depotCount / $maxDepots dépôt${maxDepots > 1 ? 's' : ''}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: depotCount >= maxDepots
                            ? AppColors.warning
                            : AppColors.textSecondary,
                      ),
                ),
                const SizedBox(width: 12),
                if (canManageTenants) ...[
                  Icon(Icons.supervisor_account_rounded,
                      size: 13, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Text(
                    'Peut gérer des tenants',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.primary),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                // Status change dropdown
                Expanded(
                  child: _StatusDropdown(
                    currentStatus: status,
                    tenantId: tenant['id'] as String,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _showEditDialog(context, ref, tenant),
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  tooltip: 'Modifier caisses / permissions',
                  style: IconButton.styleFrom(
                    foregroundColor: AppColors.primary,
                  ),
                ),
                if (!isActive)
                  OutlinedButton.icon(
                    onPressed: () => _showActivateDialog(context, ref, tenant),
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('Activer'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.success,
                      side: const BorderSide(color: AppColors.success),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showActivateDialog(
      BuildContext context, WidgetRef ref, Map<String, dynamic> tenant) async {
    final amountCtrl = TextEditingController(text: '1500');
    String currency = 'HTG';
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
        return AlertDialog(
          title: Text('Activer ${tenant['business_name']}'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Montant'),
                  validator: (v) =>
                      (v == null || double.tryParse(v) == null)
                          ? 'Montant invalide'
                          : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: currency,
                  decoration: const InputDecoration(labelText: 'Devise'),
                  items: const [
                    DropdownMenuItem(value: 'HTG', child: Text('HTG')),
                    DropdownMenuItem(value: 'USD', child: Text('USD')),
                  ],
                  onChanged: (v) => setState(() => currency = v ?? 'HTG'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(ctx);
                try {
                  final d = await ref.read(adminDioProvider.future);
                  await d.post(
                    '/api/admin/tenants/${tenant['id']}/activate',
                    data: {
                      'amount': double.parse(amountCtrl.text),
                      'currency': currency,
                    },
                  );
                  ref.invalidate(_tenantsProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Boutique activée avec succès'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Erreur: $e'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                }
              },
              child: const Text('Confirmer'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _showEditDialog(
      BuildContext context, WidgetRef ref, Map<String, dynamic> tenant) async {
    final maxCaisseCtrl = TextEditingController(
        text: (tenant['max_caisses'] as int? ?? 1).toString());
    final maxDepotCtrl = TextEditingController(
        text: (tenant['max_depots'] as int? ?? 1).toString());
    bool canManage = tenant['can_manage_tenants'] as bool? ?? false;
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
        return AlertDialog(
          title: Text('Modifier ${tenant['business_name']}'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: maxCaisseCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de caisses max',
                    prefixIcon: Icon(Icons.point_of_sale_rounded),
                  ),
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    return (n == null || n < 1) ? 'Minimum 1' : null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: maxDepotCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de dépôts max',
                    prefixIcon: Icon(Icons.store_rounded),
                  ),
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    return (n == null || n < 1) ? 'Minimum 1' : null;
                  },
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Peut gérer des tenants',
                      style: TextStyle(fontSize: 14)),
                  subtitle: const Text('Accès multi-tenant',
                      style: TextStyle(fontSize: 12)),
                  value: canManage,
                  onChanged: (v) => setState(() => canManage = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(ctx);
                try {
                  final d = await ref.read(adminDioProvider.future);
                  await d.patch(
                    '/api/admin/tenants/${tenant['id']}',
                    data: {
                      'max_caisses': int.parse(maxCaisseCtrl.text),
                      'max_depots':  int.parse(maxDepotCtrl.text),
                      'can_manage_tenants': canManage,
                    },
                  );
                  ref.invalidate(_tenantsProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Modifié avec succès'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Erreur: $e'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                }
              },
              child: const Text('Sauvegarder'),
            ),
          ],
        );
      }),
    );
  }
}

class _StatusDropdown extends ConsumerWidget {
  final String currentStatus;
  final String tenantId;

  const _StatusDropdown({
    required this.currentStatus,
    required this.tenantId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DropdownButtonFormField<String>(
      initialValue: currentStatus == 'local' ? null : currentStatus,
      decoration: const InputDecoration(
        labelText: 'Statut',
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        isDense: true,
      ),
      items: const [
        DropdownMenuItem(value: 'trial', child: Text('Essai')),
        DropdownMenuItem(value: 'active', child: Text('Actif')),
        DropdownMenuItem(value: 'suspended', child: Text('Suspendu')),
        DropdownMenuItem(value: 'expired', child: Text('Expiré')),
      ],
      onChanged: (newStatus) async {
        if (newStatus == null || newStatus == currentStatus) return;
        try {
          final d = await ref.read(adminDioProvider.future);
          await d.patch(
            '/api/admin/tenants/$tenantId',
            data: {'status': newStatus},
          );
          ref.invalidate(_tenantsProvider);
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Erreur: $e'),
                backgroundColor: AppColors.error,
              ),
            );
          }
        }
      },
    );
  }
}

// ── Tab 2 — Paiements ────────────────────────────────────────────────────────

class _PaymentsTab extends ConsumerWidget {
  const _PaymentsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentsAsync = ref.watch(_paymentsProvider);
    final statsAsync = ref.watch(_statsProvider);

    return paymentsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        message: e.toString(),
        onRetry: () => ref.invalidate(_paymentsProvider),
      ),
      data: (payments) => Column(
        children: [
          // Stats bar
          statsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const SizedBox.shrink(),
            data: (stats) => _StatsBar(stats: stats, paymentCount: payments.length),
          ),
          Expanded(
            child: payments.isEmpty
                ? const Center(child: Text('Aucun paiement trouvé'))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: payments.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, i) {
                      final p = payments[i] as Map<String, dynamic>;
                      return _PaymentRow(payment: p);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _StatsBar extends StatelessWidget {
  final Map<String, dynamic> stats;
  final int paymentCount;

  const _StatsBar({required this.stats, required this.paymentCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _StatChip(
              label: 'Paiements',
              value: paymentCount.toString(),
              color: AppColors.primary),
          const SizedBox(width: 8),
          _StatChip(
            label: 'MRR USD',
            value: '\$${(stats['mrr_usd'] as num? ?? 0).toStringAsFixed(0)}',
            color: AppColors.success,
          ),
          const SizedBox(width: 8),
          _StatChip(
            label: 'MRR HTG',
            value: '${(stats['mrr_htg'] as num? ?? 0).toStringAsFixed(0)} HTG',
            color: AppColors.accent,
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: color, fontSize: 14)),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final Map<String, dynamic> payment;
  const _PaymentRow({required this.payment});

  Color _methodColor(String method) {
    switch (method) {
      case 'stripe':
        return const Color(0xFF6772E5);
      case 'moncash':
        return AppColors.error;
      case 'natcash':
        return AppColors.info;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final method = payment['method'] as String? ?? 'manual';
    final amount = payment['amount'] as num? ?? 0;
    final currency = payment['currency'] as String? ?? '';
    final invoice = payment['invoice_number'] as String? ?? '';
    final businessName = payment['business_name'] as String? ?? '—';
    final paidAt = payment['paid_at'] as String?;

    String? formattedDate;
    if (paidAt != null) {
      try {
        formattedDate =
            DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(paidAt));
      } catch (_) {}
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _StatusBadge(
                label: method.toUpperCase(), color: _methodColor(method)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(businessName,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600)),
                  Text(invoice,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${amount.toStringAsFixed(0)} $currency',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold, color: AppColors.success),
                ),
                if (formattedDate != null)
                  Text(formattedDate,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tab 3 — Paramètres plateforme ────────────────────────────────────────────

class _PlatformConfigTab extends ConsumerStatefulWidget {
  const _PlatformConfigTab();

  @override
  ConsumerState<_PlatformConfigTab> createState() => _PlatformConfigTabState();
}

class _PlatformConfigTabState extends ConsumerState<_PlatformConfigTab> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  final _moncashCtrl           = TextEditingController();
  final _natcashCtrl           = TextEditingController();
  final _priceHtgCtrl          = TextEditingController();
  final _priceUsdCtrl          = TextEditingController();
  final _extraCaisseHtgCtrl    = TextEditingController();
  final _extraCaisseUsdCtrl    = TextEditingController();
  final _extraDepotHtgCtrl     = TextEditingController();
  final _extraDepotUsdCtrl     = TextEditingController();
  final _stripePriceCtrl       = TextEditingController();
  final _trialDaysCtrl         = TextEditingController();
  final _supportEmailCtrl      = TextEditingController();
  final _supportWaCtrl         = TextEditingController();

  String _moncashMode = 'manual';
  String _natcashMode = 'manual';
  bool _loaded = false;

  void _populateFrom(Map<String, dynamic> cfg) {
    if (_loaded) return;
    _moncashCtrl.text        = cfg['moncash_number']?.toString()              ?? '';
    _natcashCtrl.text        = cfg['natcash_number']?.toString()              ?? '';
    _priceHtgCtrl.text       = cfg['monthly_price_htg']?.toString()          ?? '1500';
    _priceUsdCtrl.text       = cfg['monthly_price_usd']?.toString()          ?? '12';
    _extraCaisseHtgCtrl.text = cfg['price_per_extra_caisse_htg']?.toString() ?? '500';
    _extraCaisseUsdCtrl.text = cfg['price_per_extra_caisse_usd']?.toString() ?? '4';
    _extraDepotHtgCtrl.text  = cfg['price_per_extra_depot_htg']?.toString()  ?? '500';
    _extraDepotUsdCtrl.text  = cfg['price_per_extra_depot_usd']?.toString()  ?? '4';
    _stripePriceCtrl.text    = cfg['stripe_price_id']?.toString()            ?? '';
    _trialDaysCtrl.text      = cfg['trial_days']?.toString()                 ?? '30';
    _supportEmailCtrl.text   = cfg['support_email']?.toString()              ?? '';
    _supportWaCtrl.text      = cfg['support_whatsapp']?.toString()           ?? '';
    _moncashMode = cfg['moncash_mode']?.toString() == 'api' ? 'api' : 'manual';
    _natcashMode = cfg['natcash_mode']?.toString() == 'api' ? 'api' : 'manual';
    _loaded = true;
  }

  @override
  void dispose() {
    _moncashCtrl.dispose();
    _natcashCtrl.dispose();
    _priceHtgCtrl.dispose();
    _priceUsdCtrl.dispose();
    _extraCaisseHtgCtrl.dispose();
    _extraCaisseUsdCtrl.dispose();
    _extraDepotHtgCtrl.dispose();
    _extraDepotUsdCtrl.dispose();
    _stripePriceCtrl.dispose();
    _trialDaysCtrl.dispose();
    _supportEmailCtrl.dispose();
    _supportWaCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final d = await ref.read(adminDioProvider.future);
      await d.put('/api/admin/platform-config', data: {
        'moncash_number':              _moncashCtrl.text.trim(),
        'natcash_number':              _natcashCtrl.text.trim(),
        'monthly_price_htg':           double.tryParse(_priceHtgCtrl.text) ?? 1500,
        'monthly_price_usd':           double.tryParse(_priceUsdCtrl.text) ?? 12,
        'price_per_extra_caisse_htg':  double.tryParse(_extraCaisseHtgCtrl.text) ?? 500,
        'price_per_extra_caisse_usd':  double.tryParse(_extraCaisseUsdCtrl.text) ?? 4,
        'price_per_extra_depot_htg':   double.tryParse(_extraDepotHtgCtrl.text)  ?? 500,
        'price_per_extra_depot_usd':   double.tryParse(_extraDepotUsdCtrl.text)  ?? 4,
        'stripe_price_id':             _stripePriceCtrl.text.trim(),
        'trial_days':                  int.tryParse(_trialDaysCtrl.text) ?? 30,
        'support_email':               _supportEmailCtrl.text.trim(),
        'support_whatsapp':            _supportWaCtrl.text.trim(),
        'moncash_mode':                _moncashMode,
        'natcash_mode':                _natcashMode,
      });
      setState(() => _loaded = false); // reset so controllers repopulate on next rebuild
      ref.invalidate(_platformConfigProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Paramètres sauvegardés'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(_platformConfigProvider);

    return configAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        message: e.toString(),
        onRetry: () {
          _loaded = false;
          ref.invalidate(_platformConfigProvider);
        },
      ),
      data: (cfg) {
        _populateFrom(cfg);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Paiements mobile money',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _moncashCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Numéro MonCash'),
                  ),
                  const SizedBox(height: 8),
                  _ModeSelector(
                    label: 'Mode MonCash',
                    value: _moncashMode,
                    onChanged: (v) => setState(() => _moncashMode = v),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _natcashCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Numéro NatCash'),
                  ),
                  const SizedBox(height: 8),
                  _ModeSelector(
                    label: 'Mode NatCash',
                    value: _natcashMode,
                    onChanged: (v) => setState(() => _natcashMode = v),
                  ),
                  const SizedBox(height: 24),
                  Text('Tarification',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _priceHtgCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Prix mensuel (HTG)'),
                          validator: (v) =>
                              double.tryParse(v ?? '') == null
                                  ? 'Invalide'
                                  : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _priceUsdCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Prix mensuel (USD)'),
                          validator: (v) =>
                              double.tryParse(v ?? '') == null
                                  ? 'Invalide'
                                  : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _extraCaisseHtgCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Prix / caisse supp. (HTG)'),
                          validator: (v) =>
                              double.tryParse(v ?? '') == null ? 'Invalide' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _extraCaisseUsdCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Prix / caisse supp. (USD)'),
                          validator: (v) =>
                              double.tryParse(v ?? '') == null ? 'Invalide' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _extraDepotHtgCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Prix / dépôt supp. (HTG)'),
                          validator: (v) =>
                              double.tryParse(v ?? '') == null ? 'Invalide' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _extraDepotUsdCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Prix / dépôt supp. (USD)'),
                          validator: (v) =>
                              double.tryParse(v ?? '') == null ? 'Invalide' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _stripePriceCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Stripe Price ID'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _trialDaysCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: "Durée d'essai (jours)"),
                    validator: (v) =>
                        int.tryParse(v ?? '') == null ? 'Invalide' : null,
                  ),
                  const SizedBox(height: 24),
                  Text('Support',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _supportEmailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration:
                        const InputDecoration(labelText: 'Email support'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _supportWaCtrl,
                    decoration:
                        const InputDecoration(labelText: 'WhatsApp support'),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Sauvegarder'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _ModeSelector extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  const _ModeSelector({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.textSecondary)),
        const SizedBox(width: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'manual',
              icon: Icon(Icons.person_outline, size: 16),
              label: Text('Manuel'),
            ),
            ButtonSegment(
              value: 'api',
              icon: Icon(Icons.api_outlined, size: 16),
              label: Text('API (auto)'),
            ),
          ],
          selected: {value},
          onSelectionChanged: (s) => onChanged(s.first),
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: AppColors.primary.withValues(alpha: 0.12),
            selectedForegroundColor: AppColors.primary,
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppColors.error),
          const SizedBox(height: 12),
          Text('Erreur de chargement',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(message,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }
}
