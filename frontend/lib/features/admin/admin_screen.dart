import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:pos_connect/core/date_utils.dart' show toHaitiTime;
import 'package:pos_connect/data/api/api_client.dart' show extractAnyError;
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
        message: extractAnyError(e),
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
        formattedDate = DateFormat('dd/MM/yyyy').format(toHaitiTime(DateTime.parse(createdAt)));
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
                IconButton(
                  onPressed: () => _showRegistersDialog(context, ref, tenant),
                  icon: const Icon(Icons.point_of_sale_rounded, size: 18),
                  tooltip: 'Gérer les caisses',
                  style: IconButton.styleFrom(
                    foregroundColor: registerCount > maxCaisses
                        ? AppColors.error
                        : AppColors.textSecondary,
                  ),
                ),
                IconButton(
                  onPressed: () => _showWarehousesDialog(context, ref, tenant),
                  icon: const Icon(Icons.store_rounded, size: 18),
                  tooltip: 'Gérer les dépôts',
                  style: IconButton.styleFrom(
                    foregroundColor: depotCount >= maxDepots
                        ? AppColors.warning
                        : AppColors.textSecondary,
                  ),
                ),
                IconButton(
                  onPressed: () => _showPurgeDialog(context, ref, tenant),
                  icon: const Icon(Icons.cleaning_services_rounded, size: 18),
                  tooltip: 'Supprimer les dépôts non réclamés',
                  style: IconButton.styleFrom(
                    foregroundColor: AppColors.warning,
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

  Future<void> _showWarehousesDialog(
      BuildContext context, WidgetRef ref, Map<String, dynamic> tenant) async {
    final tenantId = tenant['id'] as String;
    final name = tenant['business_name'] as String? ?? tenantId;

    await showDialog<void>(
      context: context,
      builder: (ctx) => _WarehousesDialog(
        tenantId: tenantId,
        tenantName: name,
      ),
    );
    ref.invalidate(_tenantsProvider);
  }

  Future<void> _showRegistersDialog(
      BuildContext context, WidgetRef ref, Map<String, dynamic> tenant) async {
    final tenantId = tenant['id'] as String;
    final name = tenant['business_name'] as String? ?? tenantId;

    await showDialog<void>(
      context: context,
      builder: (ctx) => _RegistersDialog(
        tenantId: tenantId,
        tenantName: name,
      ),
    );
    ref.invalidate(_tenantsProvider);
  }

  Future<void> _showPurgeDialog(
      BuildContext context, WidgetRef ref, Map<String, dynamic> tenant) async {
    final tenantId = tenant['id'] as String;
    final name = tenant['business_name'] as String? ?? tenantId;

    bool includeClaimed = false;
    final confirmCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
        final canConfirm = !includeClaimed || confirmCtrl.text.trim() == 'supprimer';
        return AlertDialog(
          title: const Text('Supprimer les dépôts'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Supprimer les dépôts non réclamés pour "$name" ?\n\n'
                'Ces dépôts correspondent à des installations partielles abandonnées.',
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: includeClaimed,
                contentPadding: EdgeInsets.zero,
                title: const Text('Inclure aussi les dépôts réclamés',
                    style: TextStyle(fontSize: 13)),
                subtitle: const Text(
                    'Supprime les dépôts d\'installations actives',
                    style: TextStyle(fontSize: 11)),
                activeColor: AppColors.error,
                onChanged: (v) => setState(() {
                  includeClaimed = v ?? false;
                  if (!includeClaimed) confirmCtrl.clear();
                }),
              ),
              if (includeClaimed) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: confirmCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Tapez "supprimer" pour confirmer',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: canConfirm ? () => Navigator.pop(ctx, true) : null,
              style: FilledButton.styleFrom(
                backgroundColor: includeClaimed ? AppColors.error : AppColors.warning,
              ),
              child: const Text('Supprimer'),
            ),
          ],
        );
      }),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      final d = await ref.read(adminDioProvider.future);
      final url = '/api/admin/tenants/$tenantId/warehouses/unclaimed'
          '${includeClaimed ? '?include_claimed=true' : ''}';
      final res = await d.delete(url);
      final deleted = (res.data as Map<String, dynamic>?)?['deleted'] ?? 0;
      ref.invalidate(_tenantsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$deleted dépôt${deleted != 1 ? 's' : ''} supprimé${deleted != 1 ? 's' : ''}'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
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
        message: extractAnyError(e),
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

class _PaymentRow extends ConsumerWidget {
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

  String _fmt(String? iso) {
    if (iso == null) return '';
    try {
      return DateFormat('dd/MM/yyyy HH:mm').format(toHaitiTime(DateTime.parse(iso)));
    } catch (_) {
      return '';
    }
  }

  Future<void> _confirmPending(BuildContext context, WidgetRef ref) async {
    final id = payment['id'] as String?;
    if (id == null) return;

    final months = await showDialog<int>(
      context: context,
      builder: (ctx) {
        int val = 1;
        return StatefulBuilder(builder: (ctx, setState) {
          return AlertDialog(
            title: const Text('Valider le paiement'),
            content: DropdownButtonFormField<int>(
              initialValue: val,
              decoration: const InputDecoration(labelText: 'Durée'),
              items: [1, 2, 3, 6, 12]
                  .map((m) => DropdownMenuItem(
                      value: m,
                      child: Text('$m mois')))
                  .toList(),
              onChanged: (v) => setState(() => val = v ?? 1),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Annuler')),
              ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, val),
                  child: const Text('Confirmer')),
            ],
          );
        });
      },
    );
    if (months == null || !context.mounted) return;

    try {
      final d = await ref.read(adminDioProvider.future);
      await d.patch('/api/admin/payments/$id/confirm', data: {'months': months});
      ref.invalidate(_paymentsProvider);
      ref.invalidate(_tenantsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Paiement validé — abonnement activé'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(extractAnyError(e)),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final method = payment['method'] as String? ?? 'manual';
    final status = payment['status'] as String? ?? 'paid';
    final amount = payment['amount'] as num? ?? 0;
    final currency = payment['currency'] as String? ?? '';
    final invoice = payment['invoice_number'] as String? ?? '';
    final businessName = payment['business_name'] as String? ?? '—';
    final description = payment['description'] as String?;
    final isPending = status == 'pending';

    // Pending → show created_at; paid → show paid_at
    final dateStr = isPending
        ? _fmt(payment['created_at'] as String?)
        : _fmt(payment['paid_at'] as String?);

    return Card(
      color: isPending
          ? Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.25)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StatusBadge(label: method.toUpperCase(), color: _methodColor(method)),
                const SizedBox(width: 8),
                if (isPending)
                  _StatusBadge(label: 'EN ATTENTE', color: Colors.orange),
                const Spacer(),
                Text(
                  '${amount.toStringAsFixed(0)} $currency',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold, color: AppColors.success),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(businessName,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            Text(invoice,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textSecondary)),
            if (description != null && description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(description,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.textSecondary)),
              ),
            if (dateStr.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  isPending ? 'Soumis le $dateStr' : 'Payé le $dateStr',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ),
            if (isPending) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('Valider le paiement'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                  onPressed: () => _confirmPending(context, ref),
                ),
              ),
            ],
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
  final _supportAddressCtrl    = TextEditingController();
  final _statBusinessesCtrl    = TextEditingController();
  final _statTransactionsCtrl  = TextEditingController();
  final _statUptimeCtrl        = TextEditingController();
  final _smtpHostCtrl          = TextEditingController();
  final _smtpPortCtrl          = TextEditingController();
  final _smtpUserCtrl          = TextEditingController();
  final _smtpPasswordCtrl      = TextEditingController();
  final _smtpFromCtrl          = TextEditingController();
  final _logoUrlCtrl           = TextEditingController();

  String _moncashMode = 'manual';
  String _natcashMode = 'manual';
  bool _loaded = false;

  // Pricing plans
  final List<_PlanEditors> _planEditors = [];
  bool _plansLoaded = false;

  void _populateFrom(Map<String, dynamic> cfg) {
    if (_loaded) return;
    _moncashCtrl.text           = cfg['moncash_number']?.toString()              ?? '';
    _natcashCtrl.text           = cfg['natcash_number']?.toString()              ?? '';
    _priceHtgCtrl.text          = cfg['monthly_price_htg']?.toString()          ?? '1500';
    _priceUsdCtrl.text          = cfg['monthly_price_usd']?.toString()          ?? '12';
    _extraCaisseHtgCtrl.text    = cfg['price_per_extra_caisse_htg']?.toString() ?? '500';
    _extraCaisseUsdCtrl.text    = cfg['price_per_extra_caisse_usd']?.toString() ?? '4';
    _extraDepotHtgCtrl.text     = cfg['price_per_extra_depot_htg']?.toString()  ?? '500';
    _extraDepotUsdCtrl.text     = cfg['price_per_extra_depot_usd']?.toString()  ?? '4';
    _stripePriceCtrl.text       = cfg['stripe_price_id']?.toString()            ?? '';
    _trialDaysCtrl.text         = cfg['trial_days']?.toString()                 ?? '30';
    _supportEmailCtrl.text      = cfg['support_email']?.toString()              ?? '';
    _supportWaCtrl.text         = cfg['support_whatsapp']?.toString()           ?? '';
    _supportAddressCtrl.text    = cfg['support_address']?.toString()            ?? '';
    _statBusinessesCtrl.text    = cfg['stat_businesses']?.toString()            ?? '500+';
    _statTransactionsCtrl.text  = cfg['stat_transactions_day']?.toString()      ?? '10k+';
    _statUptimeCtrl.text        = cfg['stat_uptime']?.toString()                ?? '99.9%';
    _smtpHostCtrl.text          = cfg['smtp_host']?.toString()                  ?? '';
    _smtpPortCtrl.text          = cfg['smtp_port']?.toString()                  ?? '587';
    _smtpUserCtrl.text          = cfg['smtp_user']?.toString()                  ?? '';
    _smtpPasswordCtrl.text      = cfg['smtp_password']?.toString()              ?? '';
    _smtpFromCtrl.text          = cfg['smtp_from']?.toString()                  ?? '';
    _logoUrlCtrl.text           = cfg['logo_url']?.toString()                  ?? '';
    _moncashMode = cfg['moncash_mode']?.toString() == 'api' ? 'api' : 'manual';
    _natcashMode = cfg['natcash_mode']?.toString() == 'api' ? 'api' : 'manual';
    _loaded = true;

    if (!_plansLoaded) {
      _plansLoaded = true;
      for (final e in _planEditors) { e.dispose(); }
      _planEditors.clear();
      List<dynamic> rawPlans = [];
      final rawJson = cfg['pricing_plans_json'];
      if (rawJson != null && rawJson.toString().isNotEmpty) {
        try { rawPlans = jsonDecode(rawJson.toString()) as List; } catch (_) {}
      }
      final source = rawPlans.isNotEmpty ? rawPlans : _defaultPlans;
      for (final plan in source) {
        final e = _PlanEditors();
        e.populate(plan as Map<String, dynamic>);
        _planEditors.add(e);
      }
    }
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
    _supportAddressCtrl.dispose();
    _statBusinessesCtrl.dispose();
    _statTransactionsCtrl.dispose();
    _statUptimeCtrl.dispose();
    _smtpHostCtrl.dispose();
    _smtpPortCtrl.dispose();
    _smtpUserCtrl.dispose();
    _smtpPasswordCtrl.dispose();
    _smtpFromCtrl.dispose();
    _logoUrlCtrl.dispose();
    for (final e in _planEditors) { e.dispose(); }
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
        'support_address':             _supportAddressCtrl.text.trim(),
        'stat_businesses':             _statBusinessesCtrl.text.trim(),
        'stat_transactions_day':       _statTransactionsCtrl.text.trim(),
        'stat_uptime':                 _statUptimeCtrl.text.trim(),
        'smtp_host':                   _smtpHostCtrl.text.trim(),
        'smtp_port':                   int.tryParse(_smtpPortCtrl.text) ?? 587,
        'smtp_user':                   _smtpUserCtrl.text.trim(),
        'smtp_password':               _smtpPasswordCtrl.text.trim(),
        'smtp_from':                   _smtpFromCtrl.text.trim(),
        'moncash_mode':                _moncashMode,
        'natcash_mode':                _natcashMode,
        'pricing_plans_json': jsonEncode(_planEditors.map((e) => e.toMap()).toList()),
        'logo_url': _logoUrlCtrl.text.trim().isEmpty ? null : _logoUrlCtrl.text.trim(),
      });
      setState(() { _loaded = false; _plansLoaded = false; });
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
        message: extractAnyError(e),
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
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _supportAddressCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Adresse physique'),
                  ),
                  const SizedBox(height: 24),
                  Text('Stats page d\'accueil',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: TextFormField(
                        controller: _statBusinessesCtrl,
                        decoration: const InputDecoration(labelText: 'Boutiques (ex: 500+)'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _statTransactionsCtrl,
                        decoration: const InputDecoration(labelText: 'Transactions/jour (ex: 10k+)'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _statUptimeCtrl,
                        decoration: const InputDecoration(labelText: 'Disponibilité (ex: 99.9%)'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 24),
                  Text('Configuration email (SMTP)',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _smtpHostCtrl,
                        decoration: const InputDecoration(labelText: 'Serveur SMTP'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _smtpPortCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Port'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _smtpUserCtrl,
                    decoration: const InputDecoration(labelText: 'Utilisateur SMTP'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _smtpPasswordCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Mot de passe SMTP',
                      helperText: 'Laissez vide pour conserver le mot de passe actuel',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _smtpFromCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Expéditeur (ex: noreply@mondomaine.com)'),
                  ),
                  const SizedBox(height: 24),
                  Text('Logo de la plateforme',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'URL de votre logo (PNG/SVG). Laissez vide pour utiliser le logo POS Connect par défaut.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _logoUrlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'URL du logo',
                      hintText: 'https://exemple.com/logo.png',
                      prefixIcon: Icon(Icons.image_outlined),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('Cards de tarification',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Laissez Prix HTG/USD vide pour utiliser les prix du plan Pro ci-dessus.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  ..._planEditors.asMap().entries.map((entry) {
                    final i = entry.key;
                    final e = entry.value;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(
                              child: Text(e.nameCtrl.text.isEmpty ? 'Card ${i + 1}' : e.nameCtrl.text,
                                  style: Theme.of(context).textTheme.titleMedium),
                            ),
                            const Text('Visible', style: TextStyle(fontSize: 12)),
                            Switch(
                              value: e.visible,
                              onChanged: (v) => setState(() => e.visible = v),
                            ),
                            const SizedBox(width: 8),
                            const Text('Mis en avant', style: TextStyle(fontSize: 12)),
                            Switch(
                              value: e.highlighted,
                              onChanged: (v) => setState(() => e.highlighted = v),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: AppColors.error),
                              tooltip: 'Supprimer cette card',
                              onPressed: () => setState(() {
                                e.dispose();
                                _planEditors.removeAt(i);
                              }),
                            ),
                          ]),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(
                              child: TextFormField(
                                controller: e.nameCtrl,
                                decoration: const InputDecoration(labelText: 'Nom'),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: e.subtitleCtrl,
                                decoration: const InputDecoration(labelText: 'Sous-titre'),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(
                              child: TextFormField(
                                controller: e.priceHtgCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Prix HTG',
                                  hintText: 'Vide = auto',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: e.priceUsdCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Prix USD',
                                  hintText: 'Vide = auto',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: e.periodCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Période',
                                  hintText: 'ex: par mois',
                                ),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 12),
                          Text('Fonctionnalités',
                              style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: e.features.asMap().entries.map((fe) => Chip(
                              label: Text(fe.value, style: const TextStyle(fontSize: 12)),
                              deleteIcon: const Icon(Icons.close, size: 14),
                              onDeleted: () => setState(() => e.features.removeAt(fe.key)),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                            )).toList(),
                          ),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(
                              child: TextFormField(
                                controller: e.featureAddCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Ajouter une fonctionnalité',
                                  isDense: true,
                                ),
                                onFieldSubmitted: (v) {
                                  final txt = v.trim();
                                  if (txt.isNotEmpty) {
                                    setState(() {
                                      e.features.add(txt);
                                      e.featureAddCtrl.clear();
                                    });
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () {
                                final txt = e.featureAddCtrl.text.trim();
                                if (txt.isNotEmpty) {
                                  setState(() {
                                    e.features.add(txt);
                                    e.featureAddCtrl.clear();
                                  });
                                }
                              },
                            ),
                          ]),
                        ]),
                      ),
                    );
                  }),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Ajouter une card'),
                    onPressed: () => setState(() {
                      final e = _PlanEditors();
                      e.id = 'plan_${_planEditors.length + 1}';
                      _planEditors.add(e);
                    }),
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

// ── Warehouses management dialog ─────────────────────────────────────────────

class _WarehousesDialog extends ConsumerStatefulWidget {
  final String tenantId;
  final String tenantName;

  const _WarehousesDialog({required this.tenantId, required this.tenantName});

  @override
  ConsumerState<_WarehousesDialog> createState() => _WarehousesDialogState();
}

class _WarehousesDialogState extends ConsumerState<_WarehousesDialog> {
  List<Map<String, dynamic>>? _warehouses;
  String? _error;
  bool _loading = true;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final d = await ref.read(adminDioProvider.future);
      final res = await d.get('/api/admin/tenants/${widget.tenantId}/warehouses');
      setState(() {
        _warehouses = List<Map<String, dynamic>>.from(res.data as List);
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = extractAnyError(e); _loading = false; });
    }
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '—';
    final rawDt = DateTime.tryParse(iso);
    if (rawDt == null) return '—';
    final dt = toHaitiTime(rawDt);
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _delete(String warehouseId, String warehouseName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer le dépôt'),
        content: Text(
          'Supprimer définitivement "$warehouseName" ?\n\n'
          'Les ventes, achats et mouvements liés à ce dépôt seront dissociés '
          '(warehouse_id mis à NULL).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy.add(warehouseId));
    try {
      final d = await ref.read(adminDioProvider.future);
      await d.delete('/api/admin/warehouses/$warehouseId');
      setState(() => _warehouses!.removeWhere((w) => w['id'] == warehouseId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('"$warehouseName" supprimé'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : ${extractAnyError(e)}'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(warehouseId));
    }
  }

  Future<void> _unclaim(String warehouseId, String warehouseName) async {
    setState(() => _busy.add(warehouseId));
    try {
      final d = await ref.read(adminDioProvider.future);
      await d.patch('/api/admin/warehouses/$warehouseId/unclaim');
      setState(() {
        _warehouses = _warehouses!.map((w) {
          if (w['id'] == warehouseId) return {...w, 'is_claimed': false};
          return w;
        }).toList();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('"$warehouseName" marqué non réclamé'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : ${extractAnyError(e)}'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(warehouseId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Dépôts — ${widget.tenantName}'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 520,
        child: _loading
            ? const Center(child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ))
            : _error != null
                ? Text('Erreur : $_error',
                    style: const TextStyle(color: AppColors.error))
                : (_warehouses == null || _warehouses!.isEmpty)
                    ? const Text('Aucun dépôt enregistré.')
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: _warehouses!.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final w = _warehouses![i];
                          final id         = w['id'] as String;
                          final name       = w['name'] as String? ?? id;
                          final isClaimed  = w['is_claimed'] as bool? ?? false;
                          final isActive   = w['is_active'] as bool? ?? true;
                          final isDefault  = w['is_default'] as bool? ?? false;
                          final createdAt  = _fmtDate(w['created_at'] as String?);
                          final isBusy     = _busy.contains(id);

                          return ListTile(
                            dense: true,
                            leading: Icon(
                              isDefault
                                  ? Icons.home_work_rounded
                                  : Icons.store_rounded,
                              color: isActive
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                              size: 20,
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(name,
                                      style: const TextStyle(fontSize: 13)),
                                ),
                                if (isDefault)
                                  _SmallBadge(
                                      label: 'Principal',
                                      color: AppColors.primary),
                                const SizedBox(width: 4),
                                _SmallBadge(
                                  label: isClaimed ? 'Réclamé' : 'Libre',
                                  color: isClaimed
                                      ? AppColors.success
                                      : AppColors.textSecondary,
                                ),
                              ],
                            ),
                            subtitle: Text(
                              'Créé le $createdAt'
                              '${!isActive ? '  •  Inactif' : ''}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: isBusy
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isClaimed)
                                        IconButton(
                                          icon: const Icon(
                                              Icons.link_off_rounded,
                                              size: 18),
                                          tooltip: 'Marquer non réclamé',
                                          color: AppColors.warning,
                                          onPressed: () =>
                                              _unclaim(id, name),
                                        ),
                                      IconButton(
                                        icon: const Icon(
                                            Icons.delete_outline_rounded,
                                            size: 18),
                                        tooltip: 'Supprimer ce dépôt',
                                        color: AppColors.error,
                                        onPressed: () => _delete(id, name),
                                      ),
                                    ],
                                  ),
                          );
                        },
                      ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : _load,
          child: const Text('Actualiser'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}

// ── Small badge helper ────────────────────────────────────────────────────────

class _SmallBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _SmallBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ── Registers management dialog ──────────────────────────────────────────────

class _RegistersDialog extends ConsumerStatefulWidget {
  final String tenantId;
  final String tenantName;

  const _RegistersDialog({required this.tenantId, required this.tenantName});

  @override
  ConsumerState<_RegistersDialog> createState() => _RegistersDialogState();
}

class _RegistersDialogState extends ConsumerState<_RegistersDialog> {
  List<Map<String, dynamic>>? _registers;
  String? _error;
  bool _loading = true;
  final Set<String> _toggling = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final d = await ref.read(adminDioProvider.future);
      final res = await d.get('/api/admin/tenants/${widget.tenantId}/registers');
      setState(() {
        _registers = List<Map<String, dynamic>>.from(res.data as List);
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = extractAnyError(e); _loading = false; });
    }
  }

  Future<void> _toggle(String registerId) async {
    setState(() => _toggling.add(registerId));
    try {
      final d = await ref.read(adminDioProvider.future);
      final res = await d.patch(
        '/api/admin/tenants/${widget.tenantId}/registers/$registerId',
      );
      final updated = res.data as Map<String, dynamic>;
      setState(() {
        _registers = _registers!.map((r) {
          if (r['id'] == registerId) return {...r, 'is_active': updated['is_active']};
          return r;
        }).toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      setState(() => _toggling.remove(registerId));
    }
  }

  String _formatDate(String? iso) {
    if (iso == null) return 'Jamais';
    final rawDt = DateTime.tryParse(iso);
    final dt = rawDt != null ? toHaitiTime(rawDt) : null;
    if (dt == null) return '—';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Caisses — ${widget.tenantName}'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 480,
        child: _loading
            ? const Center(child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ))
            : _error != null
                ? Text('Erreur : $_error',
                    style: const TextStyle(color: AppColors.error))
                : _registers == null || _registers!.isEmpty
                    ? const Text('Aucune caisse enregistrée.')
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: _registers!.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final r = _registers![i];
                          final id = r['id'] as String;
                          final isActive = r['is_active'] as bool? ?? true;
                          final hasSession = r['has_session'] as bool? ?? false;
                          final lastSeen = _formatDate(r['last_seen'] as String?);
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              Icons.point_of_sale_rounded,
                              color: isActive ? AppColors.success : AppColors.textSecondary,
                              size: 20,
                            ),
                            title: Text(r['name'] as String? ?? id,
                                style: const TextStyle(fontSize: 13)),
                            subtitle: Text(
                              'Dernière activité : $lastSeen'
                              '${hasSession ? '  •  Session ouverte' : ''}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: _toggling.contains(id)
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Switch(
                                    value: isActive,
                                    activeThumbColor: AppColors.success,
                                    onChanged: (_) => _toggle(id),
                                  ),
                          );
                        },
                      ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : _load,
          child: const Text('Actualiser'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}

// ── Pricing plan editor helpers ───────────────────────────────────────────────

class _PlanEditors {
  final nameCtrl       = TextEditingController();
  final subtitleCtrl   = TextEditingController();
  final periodCtrl     = TextEditingController();
  final priceHtgCtrl   = TextEditingController();
  final priceUsdCtrl   = TextEditingController();
  final featureAddCtrl = TextEditingController();
  String id = '';
  bool visible = true;
  bool highlighted = false;
  List<String> features = [];

  void populate(Map<String, dynamic> plan) {
    id            = plan['id']?.toString()        ?? '';
    nameCtrl.text = plan['name']?.toString()      ?? '';
    subtitleCtrl.text = plan['subtitle']?.toString() ?? '';
    periodCtrl.text   = plan['period']?.toString()   ?? '';
    priceHtgCtrl.text = plan['price_htg']?.toString() ?? '';
    priceUsdCtrl.text = plan['price_usd']?.toString() ?? '';
    visible     = plan['visible']     != false;
    highlighted = plan['highlighted'] == true;
    features    = (plan['features'] as List?)?.map((e) => e.toString()).toList() ?? [];
  }

  Map<String, dynamic> toMap() => {
    'id':          id,
    'name':        nameCtrl.text.trim(),
    'subtitle':    subtitleCtrl.text.trim(),
    'price_htg':   priceHtgCtrl.text.trim().isEmpty ? null : priceHtgCtrl.text.trim(),
    'price_usd':   priceUsdCtrl.text.trim().isEmpty ? null : priceUsdCtrl.text.trim(),
    'period':      periodCtrl.text.trim(),
    'highlighted': highlighted,
    'visible':     visible,
    'features':    features,
  };

  void dispose() {
    nameCtrl.dispose();
    subtitleCtrl.dispose();
    periodCtrl.dispose();
    priceHtgCtrl.dispose();
    priceUsdCtrl.dispose();
    featureAddCtrl.dispose();
  }
}

// Defaults shown when pricing_plans_json is null in DB
const _defaultPlans = [
  {
    'id': 'starter', 'visible': true, 'name': 'Starter',
    'subtitle': 'Pour découvrir', 'price_htg': 'Gratuit', 'price_usd': null,
    'period': '{trial_days} jours d\'essai', 'highlighted': false,
    'features': ['1 dépôt', '1 caisse', 'Ventes & encaissements', 'Gestion clients', 'Rapports de base', 'Support email', 'Aucune carte requise'],
  },
  {
    'id': 'pro', 'visible': true, 'name': 'Pro',
    'subtitle': 'Basé sur le nombre de caisses', 'price_htg': null, 'price_usd': null,
    'period': 'par mois · 1 dépôt', 'highlighted': true,
    'features': ['1 dépôt inclus', '3 caisses incluses', 'Mode restaurant', 'Sync cloud temps réel', 'Rapports avancés', 'Multi-plateformes', 'Support prioritaire'],
  },
  {
    'id': 'enterprise', 'visible': true, 'name': 'Enterprise',
    'subtitle': 'Pour les grandes enseignes', 'price_htg': 'Sur devis', 'price_usd': null,
    'period': '', 'highlighted': false,
    'features': ['Dépôts illimités', 'Caisses illimitées', 'API REST complète', 'White label', 'Formation sur site', 'Gestionnaire dédié', 'SLA 99.9%'],
  },
];
