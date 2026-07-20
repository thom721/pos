import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/providers/auth_provider.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

class _AuditParams {
  final int page;
  final String? resourceType;
  final String? action;

  const _AuditParams({this.page = 1, this.resourceType, this.action});

  _AuditParams copyWith({int? page, String? resourceType, String? action}) =>
      _AuditParams(
        page: page ?? this.page,
        resourceType: resourceType,
        action: action,
      );
}

final _auditParamsProvider =
    StateProvider<_AuditParams>((_) => const _AuditParams());

final _auditProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, _AuditParams>(
  (ref, params) async {
    final query = <String, dynamic>{'page': params.page, 'limit': 50};
    if (params.resourceType != null) query['resource_type'] = params.resourceType;
    if (params.action != null) query['action'] = params.action;
    final res = await dio.get('/api/audit/', queryParameters: query);
    return Map<String, dynamic>.from(res.data as Map);
  },
);

final _openSessionsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) async {
    final res = await dio.get('/api/sessions/open-sessions');
    return (res.data as List).cast<Map<String, dynamic>>();
  },
);

// ── Screen ────────────────────────────────────────────────────────────────────

class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});

  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  String? _resourceType;
  String? _action;

  static const _resourceTypes = [
    'sale', 'product', 'user', 'stock', 'cashier_session',
    'purchase', 'inventory',
  ];

  static const _actions = [
    'CREATE', 'UPDATE', 'DELETE', 'CANCEL', 'OPEN', 'CLOSE', 'FORCE_CLOSE', 'LOGIN',
  ];

  void _update({String? resourceType, String? action, int page = 1}) {
    ref.read(_auditParamsProvider.notifier).state = _AuditParams(
      page: page,
      resourceType: resourceType,
      action: action,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final isAdmin = user?.isAdmin == true || user?.hasRole('manager') == true;

    if (!isAdmin) {
      return _buildJournal(context);
    }

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: AppColors.surface,
            child: const TabBar(
              tabs: [
                Tab(text: 'Journal'),
                Tab(text: 'Sessions actives'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildJournal(context),
                const _OpenSessionsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJournal(BuildContext context) {
    final params = ref.watch(_auditParamsProvider);
    final auditAsync = ref.watch(_auditProvider(params));

    return Column(
      children: [
        // ── Filters ──────────────────────────────────────────────────
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Filtrer :',
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
              DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _resourceType,
                  hint: const Text('Type', style: TextStyle(fontSize: 13)),
                  borderRadius: BorderRadius.circular(8),
                  isDense: true,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Tous les types')),
                    ..._resourceTypes.map((t) => DropdownMenuItem(
                        value: t, child: Text(_labelResource(t)))),
                  ],
                  onChanged: (v) {
                    setState(() => _resourceType = v);
                    _update(resourceType: v, action: _action);
                  },
                ),
              ),
              DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _action,
                  hint: const Text('Action', style: TextStyle(fontSize: 13)),
                  borderRadius: BorderRadius.circular(8),
                  isDense: true,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Toutes actions')),
                    ..._actions.map((a) => DropdownMenuItem(
                        value: a, child: Text(_labelAction(a)))),
                  ],
                  onChanged: (v) {
                    setState(() => _action = v);
                    _update(resourceType: _resourceType, action: v);
                  },
                ),
              ),
              if (_resourceType != null || _action != null)
                TextButton.icon(
                  onPressed: () {
                    setState(() { _resourceType = null; _action = null; });
                    _update();
                  },
                  icon: const Icon(Icons.clear_rounded, size: 14),
                  label: const Text('Effacer', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
            ],
          ),
        ),
        const Divider(height: 1),

        // ── List ─────────────────────────────────────────────────────
        Expanded(
          child: auditAsync.when(
            data: (data) {
              final items = (data['data'] as List?) ?? [];
              final total = (data['total'] as num?)?.toInt() ?? 0;
              final page = (data['page'] as num?)?.toInt() ?? 1;
              const limit = 50;
              final pages = (total / limit).ceil();

              if (items.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_rounded,
                          size: 48, color: AppColors.textSecondary),
                      SizedBox(height: 12),
                      Text('Aucune entrée',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        Text('$total entrée${total > 1 ? 's' : ''}',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary)),
                        const Spacer(),
                        if (pages > 1) ...[
                          IconButton(
                            icon: const Icon(Icons.chevron_left_rounded),
                            onPressed: page > 1
                                ? () => _update(
                                    resourceType: _resourceType,
                                    action: _action,
                                    page: page - 1)
                                : null,
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                          ),
                          Text('$page / $pages',
                              style: const TextStyle(fontSize: 12)),
                          IconButton(
                            icon: const Icon(Icons.chevron_right_rounded),
                            onPressed: page < pages
                                ? () => _update(
                                    resourceType: _resourceType,
                                    action: _action,
                                    page: page + 1)
                                : null,
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: items.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 16, endIndent: 16),
                      itemBuilder: (_, i) =>
                          _AuditRow(entry: items[i] as Map<String, dynamic>),
                    ),
                  ),
                ],
              );
            },
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text('Erreur: $e',
                  style: const TextStyle(color: AppColors.error)),
            ),
          ),
        ),
      ],
    );
  }

  String _labelResource(String t) => switch (t) {
        'sale'            => 'Vente',
        'product'         => 'Produit',
        'user'            => 'Utilisateur',
        'stock'           => 'Stock',
        'cashier_session' => 'Session caisse',
        'purchase'        => 'Achat',
        'inventory'       => 'Inventaire',
        _                 => t,
      };

  String _labelAction(String a) => switch (a) {
        'CREATE'      => 'Création',
        'UPDATE'      => 'Modification',
        'DELETE'      => 'Suppression',
        'CANCEL'      => 'Annulation',
        'OPEN'        => 'Ouverture',
        'CLOSE'       => 'Fermeture',
        'FORCE_CLOSE' => 'Fermeture forcée',
        'LOGIN'       => 'Connexion',
        _             => a,
      };
}

// ── Open sessions tab (admin only) ────────────────────────────────────────────

class _OpenSessionsTab extends ConsumerStatefulWidget {
  const _OpenSessionsTab();

  @override
  ConsumerState<_OpenSessionsTab> createState() => _OpenSessionsTabState();
}

class _OpenSessionsTabState extends ConsumerState<_OpenSessionsTab> {
  final Set<String> _closing = {};

  Future<void> _forceClose(Map<String, dynamic> session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Fermer la session ?'),
        content: Text(
          'Fermer la session de ${session['cashier_name']} '
          'sur ${session['register_name']} ?\n\n'
          'Le caissier sera déconnecté immédiatement.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Fermer de force'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final id = session['id'] as String;
    setState(() => _closing.add(id));

    try {
      await dio.post('/api/sessions/$id/force-close');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session fermée')),
      );
      // Refresh both the sessions list and the audit journal
      ref.invalidate(_openSessionsProvider);
      ref.invalidate(_auditProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur : $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _closing.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(_openSessionsProvider);
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'fr');

    return sessionsAsync.when(
      data: (sessions) {
        if (sessions.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.point_of_sale_rounded,
                    size: 48, color: AppColors.textSecondary),
                const SizedBox(height: 12),
                const Text('Aucune session ouverte',
                    style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          );
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Text(
                    '${sessions.length} session${sessions.length > 1 ? 's' : ''} ouverte${sessions.length > 1 ? 's' : ''}',
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    tooltip: 'Actualiser',
                    onPressed: () => ref.invalidate(_openSessionsProvider),
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: sessions.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 16, endIndent: 16),
                itemBuilder: (_, i) {
                  final s = sessions[i];
                  final id = s['id'] as String;
                  final openedAt = s['opened_at'] != null
                      ? DateTime.tryParse(s['opened_at'].toString())?.toLocal()
                      : null;
                  final isClosing = _closing.contains(id);

                  return ListTile(
                    dense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.lock_open_rounded,
                          color: AppColors.accent, size: 18),
                    ),
                    title: Text(
                      s['cashier_name'] as String? ?? '—',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s['register_name'] as String? ?? '—',
                          style: const TextStyle(fontSize: 11),
                        ),
                        if (openedAt != null)
                          Text(
                            'Ouvert le ${dateFmt.format(openedAt)}',
                            style: const TextStyle(
                                fontSize: 10, color: AppColors.textSecondary),
                          ),
                      ],
                    ),
                    trailing: isClosing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.error,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              textStyle: const TextStyle(fontSize: 12),
                            ),
                            onPressed: () => _forceClose(s),
                            child: const Text('Fermer'),
                          ),
                  );
                },
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Erreur : $e',
            style: const TextStyle(color: AppColors.error)),
      ),
    );
  }
}

// ── Single audit row ──────────────────────────────────────────────────────────

class _AuditRow extends StatelessWidget {
  final Map<String, dynamic> entry;
  const _AuditRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final action       = entry['action'] as String? ?? '';
    final resourceType = entry['resource_type'] as String? ?? '';
    final resourceId   = entry['resource_id'] as String?;
    final userName     = entry['user_name'] as String? ?? 'Système';
    final detail       = entry['detail'] as String?;
    final createdAt    = entry['created_at'] != null
        ? DateTime.tryParse(entry['created_at'].toString())?.toLocal()
        : null;
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'fr');

    return ListTile(
      dense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: _actionColor(action).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(_actionIcon(action),
            color: _actionColor(action), size: 18),
      ),
      title: Row(
        children: [
          _Chip(label: _labelAction(action), color: _actionColor(action)),
          const SizedBox(width: 6),
          _Chip(label: _labelResource(resourceType),
              color: AppColors.textSecondary),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(userName,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w500)),
          if (resourceId != null)
            Text('ID: $resourceId',
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textSecondary),
                overflow: TextOverflow.ellipsis),
          if (detail != null && detail.isNotEmpty)
            Text(detail,
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
        ],
      ),
      trailing: createdAt != null
          ? Text(dateFmt.format(createdAt),
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textSecondary))
          : null,
    );
  }

  Color _actionColor(String a) => switch (a) {
        'CREATE'      => AppColors.accent,
        'UPDATE'      => AppColors.info,
        'DELETE'      => AppColors.error,
        'CANCEL'      => AppColors.error,
        'OPEN'        => AppColors.accent,
        'CLOSE'       => AppColors.warning,
        'FORCE_CLOSE' => AppColors.error,
        _             => AppColors.textSecondary,
      };

  IconData _actionIcon(String a) => switch (a) {
        'CREATE'      => Icons.add_circle_outline_rounded,
        'UPDATE'      => Icons.edit_rounded,
        'DELETE'      => Icons.delete_outline_rounded,
        'CANCEL'      => Icons.cancel_outlined,
        'OPEN'        => Icons.lock_open_rounded,
        'CLOSE'       => Icons.lock_rounded,
        'FORCE_CLOSE' => Icons.lock_person_rounded,
        'LOGIN'       => Icons.login_rounded,
        _             => Icons.info_outline_rounded,
      };

  String _labelAction(String a) => switch (a) {
        'CREATE'      => 'Création',
        'UPDATE'      => 'Modification',
        'DELETE'      => 'Suppression',
        'CANCEL'      => 'Annulation',
        'OPEN'        => 'Ouverture',
        'CLOSE'       => 'Fermeture',
        'FORCE_CLOSE' => 'Fermeture forcée',
        'LOGIN'       => 'Connexion',
        _             => a,
      };

  String _labelResource(String t) => switch (t) {
        'sale'            => 'Vente',
        'product'         => 'Produit',
        'user'            => 'Utilisateur',
        'stock'           => 'Stock',
        'cashier_session' => 'Session caisse',
        'purchase'        => 'Achat',
        'inventory'       => 'Inventaire',
        _                 => t,
      };
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10, color: color, fontWeight: FontWeight.w600)),
      );
}
