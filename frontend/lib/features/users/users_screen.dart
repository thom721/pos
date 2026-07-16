import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/core/permissions.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/providers/warehouse_provider.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _usersListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await dio.get('/api/users/');
  return (res.data as List).cast<Map<String, dynamic>>();
});

/// Roles loaded from API — includes built-in and custom roles.
final _rolesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await dio.get('/api/roles');
  return (res.data as List).cast<Map<String, dynamic>>();
});

// Permission groups for the matrix display
const _permMatrix = [
  (
    group: 'Ventes',
    perms: [
      (label: 'Créer',    perm: Perm.salesCreate),
      (label: 'Voir',     perm: Perm.salesRead),
      (label: 'Modifier', perm: Perm.salesUpdate),
      (label: 'Annuler',  perm: Perm.salesCancel),
      (label: 'Remise',   perm: Perm.salesDiscount),
    ]
  ),
  (
    group: 'Achats',
    perms: [
      (label: 'Créer',    perm: Perm.purchasesCreate),
      (label: 'Voir',     perm: Perm.purchasesRead),
      (label: 'Recevoir', perm: Perm.purchasesReceive),
    ]
  ),
  (
    group: 'Produits',
    perms: [
      (label: 'Créer',    perm: Perm.productsCreate),
      (label: 'Voir',     perm: Perm.productsRead),
      (label: 'Modifier', perm: Perm.productsUpdate),
      (label: 'Supprimer',perm: Perm.productsDelete),
    ]
  ),
  (
    group: 'Clients',
    perms: [
      (label: 'Créer',    perm: Perm.customersCreate),
      (label: 'Voir',     perm: Perm.customersRead),
      (label: 'Modifier', perm: Perm.customersUpdate),
    ]
  ),
  (
    group: 'Fournisseurs',
    perms: [
      (label: 'Créer',    perm: Perm.suppliersCreate),
      (label: 'Voir',     perm: Perm.suppliersRead),
      (label: 'Modifier', perm: Perm.suppliersUpdate),
      (label: 'Supprimer',perm: Perm.suppliersDelete),
    ]
  ),
  (
    group: 'Paiements & Dettes',
    perms: [
      (label: 'Enregistrer paiement', perm: Perm.paymentsCreate),
      (label: 'Voir paiements',       perm: Perm.paymentsRead),
      (label: 'Voir dettes',          perm: Perm.debtsRead),
    ]
  ),
  (
    group: 'Retours',
    perms: [
      (label: 'Créer', perm: Perm.returnsCreate),
      (label: 'Voir',  perm: Perm.returnsRead),
    ]
  ),
  (
    group: 'Stock & Inventaire',
    perms: [
      (label: 'Voir mouvements', perm: Perm.stockRead),
      (label: 'Ajuster stock',   perm: Perm.stockAdjust),
      (label: 'Créer inventaire',perm: Perm.inventoryCreate),
      (label: 'Voir inventaire', perm: Perm.inventoryRead),
    ]
  ),
  (
    group: 'Factures & Proformas',
    perms: [
      (label: 'Factures (CRUD)',  perm: Perm.invoicesCreate),
      (label: 'Proformas (CRUD)', perm: Perm.proformasCreate),
    ]
  ),
  (
    group: 'Rapports',
    perms: [
      (label: 'Ses rapports',      perm: Perm.reportsRead),
      (label: 'Tous les rapports', perm: Perm.reportsReadAll),
    ]
  ),
  (
    group: 'Configuration',
    perms: [
      (label: 'Voir config',     perm: Perm.configRead),
      (label: 'Modifier config', perm: Perm.configUpdate),
    ]
  ),
  (
    group: 'Utilisateurs',
    perms: [
      (label: 'Créer',    perm: Perm.usersCreate),
      (label: 'Voir',     perm: Perm.usersRead),
      (label: 'Modifier', perm: Perm.usersUpdate),
      (label: 'Supprimer',perm: Perm.usersDelete),
    ]
  ),
  (
    group: 'RH & Paie',
    perms: [
      (label: 'Profils employés', perm: Perm.employeesRead),
      (label: 'Prêts',            perm: Perm.loansRead),
      (label: 'Approuver prêts',  perm: Perm.loansApprove),
      (label: 'Paie',             perm: Perm.payrollRead),
      (label: 'Traiter paie',     perm: Perm.payrollProcess),
      (label: 'Payer',            perm: Perm.payrollPay),
    ]
  ),
];

Color _hexColor(String? hex) {
  if (hex == null || hex.isEmpty) return Colors.blueGrey;
  try {
    return Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));
  } catch (_) {
    return Colors.blueGrey;
  }
}

IconData _roleIcon(String roleId) => switch (roleId) {
  'admin'         => Icons.shield_rounded,
  'manager'       => Icons.manage_accounts_rounded,
  'cashier'       => Icons.point_of_sale_rounded,
  'stock_manager' => Icons.warehouse_rounded,
  _               => Icons.badge_rounded,
};

bool _roleHasPerm(Map<String, dynamic> role, String perm) {
  if (role['name'] == 'admin') return true;
  final perms = (role['permissions'] as List?)?.map((e) => e.toString()).toSet() ?? <String>{};
  return perms.contains('all') || perms.contains(perm);
}

// ═════════════════════════════════════════════════════════════════════════════
// Screen
// ═════════════════════════════════════════════════════════════════════════════

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Utilisateurs & Permissions'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(icon: Icon(Icons.people_rounded),        text: 'Utilisateurs'),
            Tab(icon: Icon(Icons.security_rounded),      text: 'Rôles & Permissions'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _UsersTab(),
          _PermissionsMatrixTab(),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Tab 1 — Users list
// ═════════════════════════════════════════════════════════════════════════════

class _UsersTab extends ConsumerWidget {
  const _UsersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_usersListProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error:   (e, _) => Center(child: Text('Erreur: $e',
          style: const TextStyle(color: AppColors.error))),
      data: (users) {
        final rolesData = ref.watch(_rolesProvider).valueOrNull ?? [];
        return Column(children: [
          // Summary chips
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _SummaryChip('Total', users.length, Colors.blueGrey),
                  const SizedBox(width: 8),
                  ...rolesData.map((r) {
                    final rName = r['name'] as String;
                    final count = users.where((u) =>
                        ((u['roles'] as List?) ?? []).contains(rName)).length;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _SummaryChip(r['label'] as String, count,
                          _hexColor(r['color'] as String?)),
                    );
                  }),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          // Add button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: [
                const Text('Liste des utilisateurs',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => _showDialog(context, ref, null),
                  icon: const Icon(Icons.person_add_rounded, size: 16),
                  label: const Text('Ajouter'),
                ),
              ],
            ),
          ),
          // List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              itemCount: users.length,
              itemBuilder: (_, i) => _UserRow(
                user: users[i],
                onEdit:   () => _showDialog(context, ref, users[i]),
                onDelete: () => _delete(context, ref, users[i]['id']),
                onRoleChange: (newRole) =>
                    _changeRole(context, ref, users[i], newRole),
              ),
            ),
          ),
        ]);
      },
    );
  }

  void _showDialog(BuildContext ctx, WidgetRef ref, Map<String, dynamic>? u) {
    showDialog(
      context: ctx,
      builder: (_) => _UserFormDialog(
        existing: u,
        onSaved: () => ref.invalidate(_usersListProvider),
      ),
    );
  }

  Future<void> _delete(BuildContext ctx, WidgetRef ref, String id) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer l\'utilisateur'),
        content: const Text('Cette action est irréversible.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await dio.delete('/api/users/$id');
      ref.invalidate(_usersListProvider);
    }
  }

  Future<void> _changeRole(BuildContext ctx, WidgetRef ref,
      Map<String, dynamic> user, String newRole) async {
    try {
      await dio.put('/api/users/${user['id']}', data: {
        'id':          user['id'],
        'fname':       user['fname'],
        'lname':       user['lname'],
        'username':    user['username'],
        'email':       user['email'],
        'phone':       user['phone'] ?? '',
        'address':     user['address'] ?? '',
        'password':    user['password'],
        'is_active':   user['is_active'] ?? true,
        'roles':       [newRole],
        'permissions': newRole == 'admin' ? ['all'] : [newRole],
      });
      ref.invalidate(_usersListProvider);
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('Erreur: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }
}

// ── User row ──────────────────────────────────────────────────────────────────

class _UserRow extends ConsumerWidget {
  final Map<String, dynamic> user;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<String> onRoleChange;

  const _UserRow({
    required this.user,
    required this.onEdit,
    required this.onDelete,
    required this.onRoleChange,
  });

  String get _currentRole {
    final roles = (user['roles'] as List?) ?? [];
    return roles.isNotEmpty ? roles.first.toString() : 'cashier';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name   = '${user['fname'] ?? ''} ${user['lname'] ?? ''}'.trim();
    final active = user['is_active'] as bool? ?? true;
    final rolesAsync = ref.watch(_rolesProvider);

    final roleColor = rolesAsync.whenOrNull(
          data: (roles) {
            final match = roles.where((r) => r['name'] == _currentRole);
            return match.isNotEmpty
                ? _hexColor(match.first['color'] as String?)
                : null;
          },
        ) ??
        Colors.blueGrey;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 20,
              backgroundColor: active
                  ? roleColor.withValues(alpha: 0.15)
                  : Colors.grey.shade200,
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                    color: active ? roleColor : Colors.grey,
                    fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),

            // Name + username
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name.isNotEmpty ? name : user['username'] ?? '—',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  Text(
                      '@${user['username'] ?? ''}  ·  ${user['email'] ?? ''}',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),

            // Role dropdown — dynamic
            rolesAsync.when(
              loading: () => const SizedBox(
                  width: 100,
                  child: LinearProgressIndicator()),
              error: (_, __) => const SizedBox.shrink(),
              data: (roles) {
                final currentExists =
                    roles.any((r) => r['name'] == _currentRole);
                final effectiveRole =
                    currentExists ? _currentRole : roles.first['name'] as String;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: roleColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: roleColor.withValues(alpha: 0.3)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: effectiveRole,
                      isDense: true,
                      icon: Icon(Icons.arrow_drop_down,
                          color: roleColor, size: 18),
                      style: TextStyle(
                          color: roleColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                      items: roles
                          .map((r) => DropdownMenuItem<String>(
                                value: r['name'] as String,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(_roleIcon(r['name'] as String),
                                        size: 14,
                                        color: _hexColor(
                                            r['color'] as String?)),
                                    const SizedBox(width: 6),
                                    Text(r['label'] as String,
                                        style: TextStyle(
                                            color: _hexColor(
                                                r['color'] as String?),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null && v != effectiveRole) onRoleChange(v);
                      },
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 8),

            // Active badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: (active ? AppColors.success : AppColors.error)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(active ? 'Actif' : 'Inactif',
                  style: TextStyle(
                      fontSize: 10,
                      color: active ? AppColors.success : AppColors.error,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 4),

            // Actions
            IconButton(
              icon: const Icon(Icons.edit_outlined,
                  size: 17, color: AppColors.primary),
              tooltip: 'Modifier',
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 17, color: AppColors.error),
              tooltip: 'Supprimer',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Tab 2 — Roles & Permissions (dynamic, editable)
// ═════════════════════════════════════════════════════════════════════════════

class _PermissionsMatrixTab extends ConsumerWidget {
  const _PermissionsMatrixTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rolesAsync = ref.watch(_rolesProvider);

    return rolesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
          child: Text('Erreur: $e',
              style: const TextStyle(color: AppColors.error))),
      data: (roles) => _buildContent(context, ref, roles),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref,
      List<Map<String, dynamic>> roles) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Text('Rôles',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _showCreate(context, ref),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Nouveau rôle'),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Role cards
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: roles
                .map((r) => Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: r == roles.last ? 0 : 10,
                        ),
                        child: _RoleCard(
                          role: r,
                          onEdit: () => _showEdit(context, ref, r),
                          onDelete: (r['is_builtin'] as bool? ?? true)
                              ? null
                              : () => _deleteRole(context, ref, r['name'] as String),
                        ),
                      ),
                    ))
                .toList(),
          ),

          const SizedBox(height: 24),
          const Text('Matrice des permissions',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
              'Cliquez sur "Éditer" pour modifier les permissions d\'un rôle',
              style:
                  TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 12),

          _buildMatrix(roles),
        ],
      ),
    );
  }

  void _showCreate(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) =>
          _CreateRoleDialog(onCreated: () => ref.invalidate(_rolesProvider)),
    );
  }

  void _showEdit(BuildContext context, WidgetRef ref,
      Map<String, dynamic> role) {
    showDialog(
      context: context,
      builder: (_) => _RolePermissionsDialog(
          role: role, onSaved: () => ref.invalidate(_rolesProvider)),
    );
  }

  Future<void> _deleteRole(
      BuildContext context, WidgetRef ref, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer ce rôle ?'),
        content: const Text(
            'Les utilisateurs avec ce rôle perdront ses permissions spécifiques.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await dio.delete('/api/roles/$name');
      ref.invalidate(_rolesProvider);
    }
  }

  Widget _buildMatrix(List<Map<String, dynamic>> roles) {
    final colCount = roles.length;
    final columnWidths = <int, TableColumnWidth>{
      0: const FlexColumnWidth(2.5),
      for (int i = 1; i <= colCount; i++) i: const FlexColumnWidth(1),
    };
    return Table(
        columnWidths: columnWidths,
        border: TableBorder.all(
            color: AppColors.divider,
            width: 0.5,
            borderRadius: BorderRadius.circular(8)),
        children: [
          // Header
          TableRow(
            decoration: const BoxDecoration(color: Color(0xFFF1F5F9)),
            children: [
              _TH('Permission', isFirst: true),
              ...roles.map((r) => _TH(r['label'] as String,
                  color: _hexColor(r['color'] as String?))),
            ],
          ),

          // Permission rows
          for (final group in _permMatrix) ...[
            TableRow(
              decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                  child: Text(group.group,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.3)),
                ),
                ...List.generate(colCount, (_) => const SizedBox(height: 22)),
              ],
            ),
            for (final p in group.perms)
              TableRow(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 5, 12, 5),
                  child: Text(p.label,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textPrimary)),
                ),
                ...roles.map((r) => _PermCell(
                      has: _roleHasPerm(r, p.perm),
                      color: _hexColor(r['color'] as String?),
                    )),
              ]),
          ],
        ],
    );
  }
}

// ── Role card ─────────────────────────────────────────────────────────────────

class _RoleCard extends StatelessWidget {
  final Map<String, dynamic> role;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  const _RoleCard({
    required this.role,
    required this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final name    = role['name'] as String;
    final label   = role['label'] as String;
    final color   = _hexColor(role['color'] as String?);
    final perms   = (role['permissions'] as List?) ?? [];
    final isAdmin = name == 'admin';
    final count   = isAdmin ? 'Toutes' : '${perms.length} permissions';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(_roleIcon(name), color: color, size: 16),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: color)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(count,
              style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isAdmin ? null : onEdit,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.edit_rounded, size: 13),
                label: const Text('Éditer', style: TextStyle(fontSize: 11)),
              ),
            ),
            if (onDelete != null) ...[
              const SizedBox(width: 6),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline,
                    size: 16, color: AppColors.error),
                tooltip: 'Supprimer',
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
              ),
            ],
          ]),
        ],
      ),
    );
  }
}

// ── Table helpers ─────────────────────────────────────────────────────────────

class _TH extends StatelessWidget {
  final String text;
  final Color? color;
  final bool isFirst;
  const _TH(this.text, {this.color, this.isFirst = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: isFirst ? 12 : 16, vertical: 8),
      child: Text(text,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color ?? AppColors.textPrimary)),
    );
  }
}

class _PermCell extends StatelessWidget {
  final bool has;
  final Color color;
  const _PermCell({required this.has, required this.color});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: has
            ? Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(Icons.check_rounded, size: 13, color: color),
              )
            : const Text('—',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Role edit dialog — permissions checkboxes
// ═════════════════════════════════════════════════════════════════════════════

class _RolePermissionsDialog extends StatefulWidget {
  final Map<String, dynamic> role;
  final VoidCallback onSaved;
  const _RolePermissionsDialog({required this.role, required this.onSaved});

  @override
  State<_RolePermissionsDialog> createState() =>
      _RolePermissionsDialogState();
}

class _RolePermissionsDialogState extends State<_RolePermissionsDialog> {
  late Set<String> _selected;
  late final TextEditingController _labelCtrl;
  bool _saving = false;

  bool get _isBuiltin => widget.role['is_builtin'] as bool? ?? true;

  @override
  void initState() {
    super.initState();
    final perms = (widget.role['permissions'] as List?)
            ?.map((e) => e.toString())
            .toSet() ??
        <String>{};
    _selected = Set.from(perms);
    _labelCtrl =
        TextEditingController(text: widget.role['label'] as String? ?? '');
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{'permissions': _selected.toList()};
      if (!_isBuiltin) body['label'] = _labelCtrl.text.trim();
      await dio.put('/api/roles/${widget.role['name']}', data: body);
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erreur: ${extractErrorMessage(e as dynamic)}'),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _hexColor(widget.role['color'] as String?);
    final label = widget.role['label'] as String;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 700),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                border: Border(
                    bottom: BorderSide(
                        color: color.withValues(alpha: 0.2))),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(children: [
                Icon(_roleIcon(widget.role['name'] as String),
                    color: color, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Permissions — $label',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: color)),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ]),
            ),

            // Label field (custom roles only)
            if (!_isBuiltin)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: TextFormField(
                  controller: _labelCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Nom affiché du rôle', isDense: true),
                ),
              ),

            // Permissions list
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                children: [
                  for (final group in _permMatrix) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                      child: Text(group.group,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: color,
                              letterSpacing: 0.3)),
                    ),
                    for (final p in group.perms)
                      CheckboxListTile(
                        value: _selected.contains(p.perm),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected.add(p.perm);
                          } else {
                            _selected.remove(p.perm);
                          }
                        }),
                        title: Text(p.label,
                            style: const TextStyle(fontSize: 13)),
                        subtitle: Text(p.perm,
                            style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondary)),
                        dense: true,
                        activeColor: color,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                  ],
                ],
              ),
            ),

            // Footer
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              child: Row(children: [
                Text('${_selected.length} permissions sélectionnées',
                    style: TextStyle(
                        fontSize: 12, color: color,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Annuler')),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('Enregistrer'),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Create custom role dialog
// ═════════════════════════════════════════════════════════════════════════════

const _kColorPalette = [
  '#7C3AED', '#0284C7', '#059669', '#D97706',
  '#DC2626', '#DB2777', '#0891B2', '#65A30D',
];

class _CreateRoleDialog extends StatefulWidget {
  final VoidCallback onCreated;
  const _CreateRoleDialog({required this.onCreated});

  @override
  State<_CreateRoleDialog> createState() => _CreateRoleDialogState();
}

class _CreateRoleDialogState extends State<_CreateRoleDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl  = TextEditingController();
  final _labelCtrl = TextEditingController();
  String _color = _kColorPalette[0];
  final Set<String> _selected = {};
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });
    try {
      await dio.post('/api/roles', data: {
        'name':        _nameCtrl.text.trim(),
        'label':       _labelCtrl.text.trim(),
        'color':       _color,
        'permissions': _selected.toList(),
      });
      widget.onCreated();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = extractErrorMessage(e as dynamic);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _hexColor(_color);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                border: const Border(
                    bottom: BorderSide(color: AppColors.divider)),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(children: [
                const Icon(Icons.add_circle_outline_rounded,
                    color: AppColors.primary, size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Nouveau rôle personnalisé',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ]),
            ),

            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Row(children: [
                      Expanded(
                        child: TextFormField(
                          controller: _labelCtrl,
                          decoration: const InputDecoration(
                              labelText: 'Nom affiché *', isDense: true),
                          validator: (v) =>
                              (v?.isEmpty ?? true) ? 'Requis' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Identifiant *',
                            isDense: true,
                            hintText: 'ex: supervisor',
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Requis';
                            if (!RegExp(r'^[a-z_]+$').hasMatch(v.trim())) {
                              return 'Minuscules et _ uniquement';
                            }
                            return null;
                          },
                        ),
                      ),
                    ]),
                    const SizedBox(height: 14),

                    // Color picker
                    const Text('Couleur',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: _kColorPalette.map((hex) {
                        final c = _hexColor(hex);
                        return GestureDetector(
                          onTap: () => setState(() => _color = hex),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _color == hex
                                    ? Colors.white
                                    : Colors.transparent,
                                width: 3,
                              ),
                              boxShadow: _color == hex
                                  ? [BoxShadow(color: c, blurRadius: 6)]
                                  : null,
                            ),
                            child: _color == hex
                                ? const Icon(Icons.check_rounded,
                                    color: Colors.white, size: 14)
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // Permissions
                    Text('Permissions — ${_selected.length} sélectionnées',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: color)),
                    const SizedBox(height: 4),
                    for (final group in _permMatrix) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 10, 0, 4),
                        child: Text(group.group,
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                                letterSpacing: 0.3)),
                      ),
                      for (final p in group.perms)
                        CheckboxListTile(
                          value: _selected.contains(p.perm),
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _selected.add(p.perm);
                            } else {
                              _selected.remove(p.perm);
                            }
                          }),
                          title: Text(p.label,
                              style: const TextStyle(fontSize: 13)),
                          subtitle: Text(p.perm,
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textSecondary)),
                          dense: true,
                          activeColor: color,
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                    ],

                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(_error!,
                            style: const TextStyle(
                                color: AppColors.error, fontSize: 13)),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              child: Row(children: [
                const Spacer(),
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Annuler')),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('Créer le rôle'),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// User form dialog (create / edit)
// ═════════════════════════════════════════════════════════════════════════════

class _UserFormDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic>? existing;
  final VoidCallback onSaved;
  const _UserFormDialog({this.existing, required this.onSaved});

  @override
  ConsumerState<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends ConsumerState<_UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fnameCtrl;
  late final TextEditingController _lnameCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _pwdCtrl;
  bool _isActive = true;
  String _selectedRole = 'cashier';
  List<String> _selectedWarehouseIds = [];
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _fnameCtrl    = TextEditingController(text: e?['fname']    ?? '');
    _lnameCtrl    = TextEditingController(text: e?['lname']    ?? '');
    _usernameCtrl = TextEditingController(text: e?['username'] ?? '');
    _emailCtrl    = TextEditingController(text: e?['email']    ?? '');
    _phoneCtrl    = TextEditingController(text: e?['phone']    ?? '');
    _addressCtrl  = TextEditingController(text: e?['address']  ?? '');
    _pwdCtrl      = TextEditingController();
    _isActive     = e?['is_active'] as bool? ?? true;

    final roles = (e?['roles'] as List?)?.map((r) => r.toString()).toList() ?? [];
    if (roles.isNotEmpty) {
      _selectedRole = roles.first;
    } else if ((e?['permissions'] as List?)?.contains('all') ?? false) {
      _selectedRole = 'admin';
    }

    // Charger les dépôts déjà assignés (warehouse_id est un tableau JSON)
    final raw = e?['warehouse_id'];
    if (raw is List) {
      _selectedWarehouseIds = raw.map((v) => v.toString()).toList();
    }
  }

  @override
  void dispose() {
    for (final c in [_fnameCtrl, _lnameCtrl, _usernameCtrl, _emailCtrl,
                     _phoneCtrl, _addressCtrl, _pwdCtrl]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final body = {
        'fname':        _fnameCtrl.text.trim(),
        'lname':        _lnameCtrl.text.trim(),
        'username':     _usernameCtrl.text.trim(),
        'email':        _emailCtrl.text.trim(),
        'phone':        _phoneCtrl.text.trim(),
        'address':      _addressCtrl.text.trim(),
        'password':     _pwdCtrl.text.isNotEmpty ? _pwdCtrl.text : 'ChangeMe123!',
        'is_active':    _isActive,
        'roles':        [_selectedRole],
        'permissions':  _selectedRole == 'admin' ? ['all'] : [_selectedRole],
        // null = accès à tous les dépôts ; liste vide envoyée comme null aussi
        'warehouse_id': _selectedWarehouseIds.isEmpty ? null : _selectedWarehouseIds,
      };
      if (_isEdit) {
        await dio.put('/api/users/${widget.existing!['id']}',
            data: {'id': widget.existing!['id'], ...body});
      } else {
        await dio.post('/api/users', data: body);
      }
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: ${extractErrorMessage(e as dynamic)}'),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rolesAsync = ref.watch(_rolesProvider);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(children: [
                  Text(_isEdit ? 'Modifier l\'utilisateur' : 'Nouvel utilisateur',
                      style: const TextStyle(fontSize: 17,
                          fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context)),
                ]),
                const SizedBox(height: 20),

                // Name row
                Row(children: [
                  Expanded(child: TextFormField(
                    controller: _fnameCtrl,
                    decoration: const InputDecoration(labelText: 'Prénom'),
                    validator: (v) => (v?.isEmpty ?? true) ? 'Requis' : null,
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(
                    controller: _lnameCtrl,
                    decoration: const InputDecoration(labelText: 'Nom'),
                    validator: (v) => (v?.isEmpty ?? true) ? 'Requis' : null,
                  )),
                ]),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _usernameCtrl,
                  decoration: const InputDecoration(
                      labelText: "Nom d'utilisateur",
                      prefixIcon: Icon(Icons.alternate_email_rounded)),
                  validator: (v) => (v?.isEmpty ?? true) ? 'Requis' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined)),
                  validator: (v) => (v?.isEmpty ?? true) ? 'Requis' : null,
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: TextFormField(
                    controller: _phoneCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Téléphone',
                        prefixIcon: Icon(Icons.phone_outlined)),
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(
                    controller: _pwdCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: _isEdit ? 'Mot de passe (optionnel)' : 'Mot de passe',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      hintText: _isEdit ? 'Laisser vide = inchangé' : null,
                    ),
                    validator: (v) =>
                        (!_isEdit && (v?.isEmpty ?? true)) ? 'Requis' : null,
                  )),
                ]),
                const SizedBox(height: 20),

                // Role selection — dynamic from API
                const Text('Rôle',
                    style: TextStyle(fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                rolesAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const Text('Impossible de charger les rôles'),
                  data: (roles) => _buildRolePicker(roles),
                ),

                const SizedBox(height: 20),

                // ── Restriction de dépôts ────────────────────────────────
                _WarehouseAccessSection(
                  selectedIds: _selectedWarehouseIds,
                  onChanged: (ids) => setState(() => _selectedWarehouseIds = ids),
                ),

                const SizedBox(height: 12),
                Row(children: [
                  const Text('Compte actif', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 8),
                  Switch.adaptive(
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v),
                  ),
                ]),

                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity, height: 48,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving
                        ? 'Enregistrement...'
                        : (_isEdit ? 'Mettre à jour' : 'Créer l\'utilisateur')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRolePicker(List<Map<String, dynamic>> roles) {
    // Ensure selected role exists in loaded list
    final names = roles.map((r) => r['name'] as String).toSet();
    if (!names.contains(_selectedRole)) {
      _selectedRole = names.firstWhere(
          (n) => n == 'cashier', orElse: () => names.first);
    }

    final selected = roles.firstWhere(
        (r) => r['name'] == _selectedRole,
        orElse: () => roles.first);
    final selColor = _hexColor(selected['color'] as String?);
    final selPerms = (selected['permissions'] as List?) ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8, runSpacing: 8,
          children: roles.map((r) {
            final rColor = _hexColor(r['color'] as String?);
            final rName  = r['name'] as String;
            final isSelected = _selectedRole == rName;
            return GestureDetector(
              onTap: () => setState(() => _selectedRole = rName),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? rColor.withValues(alpha: 0.12)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? rColor : AppColors.divider,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_roleIcon(rName), size: 15,
                      color: isSelected ? rColor : AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(r['label'] as String,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? rColor : AppColors.textPrimary)),
                ]),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        // Permission preview
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selColor.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selColor.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(_roleIcon(_selectedRole), size: 14, color: selColor),
                const SizedBox(width: 6),
                Text('Permissions du rôle ${selected['label']}',
                    style: TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w600, color: selColor)),
              ]),
              const SizedBox(height: 8),
              if (selPerms.contains('all'))
                const Text('Accès total — toutes les fonctionnalités',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary))
              else
                Wrap(
                  spacing: 4, runSpacing: 4,
                  children: _resolvePermLabels(selPerms.cast<String>())
                      .take(12)
                      .map((p) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: selColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(p,
                                style: TextStyle(
                                    fontSize: 10, color: selColor)),
                          ))
                      .toList(),
                ),
            ],
          ),
        ),
      ],
    );
  }

  List<String> _resolvePermLabels(List<String> perms) {
    final labels = <String>[];
    for (final group in _permMatrix) {
      for (final p in group.perms) {
        if (perms.contains(p.perm)) labels.add('${group.group}: ${p.label}');
      }
    }
    return labels;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Sélecteur multi-dépôts pour le formulaire utilisateur
// ═════════════════════════════════════════════════════════════════════════════

class _WarehouseAccessSection extends ConsumerWidget {
  final List<String> selectedIds;
  final ValueChanged<List<String>> onChanged;

  const _WarehouseAccessSection({
    required this.selectedIds,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(warehouseListProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.warehouse_rounded, size: 15, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          const Text('Accès aux dépôts',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
        ]),
        const SizedBox(height: 4),
        const Text(
          'Vide = accès à tous les dépôts. '
          'Cochez pour restreindre à des dépôts spécifiques '
          '(dérogation temporaire possible en cochant plusieurs).',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        async.when(
          loading: () => const LinearProgressIndicator(),
          error:   (_, __) => const SizedBox.shrink(),
          data: (warehouses) {
            if (warehouses.isEmpty) return const SizedBox.shrink();
            return Column(
              children: warehouses.map((wh) {
                final id       = wh.id;
                final name     = wh.name;
                final checked  = selectedIds.contains(id);
                return InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    final next = List<String>.from(selectedIds);
                    if (checked) { next.remove(id); } else { next.add(id); }
                    onChanged(next);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Checkbox(
                        value: checked,
                        visualDensity: VisualDensity.compact,
                        onChanged: (_) {
                          final next = List<String>.from(selectedIds);
                          if (checked) { next.remove(id); } else { next.add(id); }
                          onChanged(next);
                        },
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.warehouse_rounded,
                          size: 15,
                          color: checked ? AppColors.primary : AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Text(name,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: checked ? FontWeight.w600 : FontWeight.w400,
                              color: checked ? AppColors.primary : AppColors.textPrimary)),
                      if (wh.isDefault) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('Principal',
                              style: TextStyle(fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary)),
                        ),
                      ],
                    ]),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Helpers
// ═════════════════════════════════════════════════════════════════════════════

class _SummaryChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _SummaryChip(this.label, this.count, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$count',
              style: TextStyle(color: color, fontWeight: FontWeight.w700,
                  fontSize: 14)),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}
