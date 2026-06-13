import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/core/permissions.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final _usersListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await dio.get('/users/');
  return (res.data as List).cast<Map<String, dynamic>>();
});

// ═════════════════════════════════════════════════════════════════════════════
// Roles metadata
// ═════════════════════════════════════════════════════════════════════════════

const _rolesMeta = [
  (
    id: 'admin',
    label: 'Administrateur',
    color: Color(0xFF7C3AED),
    icon: Icons.shield_rounded,
    desc: 'Accès total à toutes les fonctionnalités',
  ),
  (
    id: 'manager',
    label: 'Gérant',
    color: Color(0xFF0284C7),
    icon: Icons.manage_accounts_rounded,
    desc: 'Tout sauf créer/supprimer des utilisateurs',
  ),
  (
    id: 'cashier',
    label: 'Caissier',
    color: Color(0xFF059669),
    icon: Icons.point_of_sale_rounded,
    desc: 'Ventes, clients, paiements, factures',
  ),
  (
    id: 'stock_manager',
    label: 'Resp. Stock',
    color: Color(0xFFD97706),
    icon: Icons.warehouse_rounded,
    desc: 'Produits, achats, inventaire, fournisseurs',
  ),
];

// Permission groups for the matrix display
const _permMatrix = [
  (
    group: 'Ventes',
    perms: [
      (label: 'Créer',  perm: Perm.salesCreate),
      (label: 'Voir',   perm: Perm.salesRead),
      (label: 'Modifier',perm: Perm.salesUpdate),
      (label: 'Annuler',perm: Perm.salesCancel),
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

bool _roleHas(String roleId, String perm) {
  if (roleId == 'admin') return true;
  final perms = rolePermissions[roleId] ?? {};
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
      data: (users) => Column(
        children: [
          // Summary chips
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _SummaryChip('Total', users.length, Colors.blueGrey),
                  const SizedBox(width: 8),
                  ..._rolesMeta.map((r) {
                    final count = users.where((u) =>
                        ((u['roles'] as List?) ?? []).contains(r.id)).length;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _SummaryChip(r.label, count, r.color),
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
        ],
      ),
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
      await dio.delete('/users/$id');
      ref.invalidate(_usersListProvider);
    }
  }

  Future<void> _changeRole(BuildContext ctx, WidgetRef ref,
      Map<String, dynamic> user, String newRole) async {
    try {
      await dio.put('/users/${user['id']}', data: {
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

class _UserRow extends StatelessWidget {
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
    if (roles.contains('admin')) return 'admin';
    if (roles.contains('manager')) return 'manager';
    if (roles.contains('stock_manager')) return 'stock_manager';
    return 'cashier';
  }

  @override
  Widget build(BuildContext context) {
    final name = '${user['fname'] ?? ''} ${user['lname'] ?? ''}'.trim();
    final active = user['is_active'] as bool? ?? true;
    final meta = _rolesMeta.firstWhere((r) => r.id == _currentRole,
        orElse: () => _rolesMeta.last);

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
                  ? meta.color.withValues(alpha: 0.15)
                  : Colors.grey.shade200,
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                    color: active ? meta.color : Colors.grey,
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
                      style: const TextStyle(fontWeight: FontWeight.w600,
                          fontSize: 14)),
                  Text('@${user['username'] ?? ''}  ·  ${user['email'] ?? ''}',
                      style: const TextStyle(fontSize: 11,
                          color: AppColors.textSecondary)),
                ],
              ),
            ),

            // Role dropdown — inline change
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: meta.color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: meta.color.withValues(alpha: 0.3)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _currentRole,
                  isDense: true,
                  icon: Icon(Icons.arrow_drop_down, color: meta.color, size: 18),
                  style: TextStyle(color: meta.color, fontSize: 12,
                      fontWeight: FontWeight.w600),
                  items: _rolesMeta.map((r) => DropdownMenuItem(
                    value: r.id,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(r.icon, size: 14, color: r.color),
                        const SizedBox(width: 6),
                        Text(r.label, style: TextStyle(color: r.color,
                            fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  )).toList(),
                  onChanged: (v) {
                    if (v != null && v != _currentRole) onRoleChange(v);
                  },
                ),
              ),
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
                  style: TextStyle(fontSize: 10,
                      color: active ? AppColors.success : AppColors.error,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 4),

            // Actions
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 17,
                  color: AppColors.primary),
              tooltip: 'Modifier',
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 17,
                  color: AppColors.error),
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
// Tab 2 — Permissions Matrix
// ═════════════════════════════════════════════════════════════════════════════

class _PermissionsMatrixTab extends StatelessWidget {
  const _PermissionsMatrixTab();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Role cards summary
          const Text('Rôles disponibles',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Row(
            children: _rolesMeta
                .map((r) => Expanded(child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _RoleCard(role: r),
                    )))
                .toList(),
          ),

          const SizedBox(height: 24),
          const Text('Matrice des permissions',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('✓ = permission accordée par le rôle  ·  — = non accordée',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 12),

          _buildMatrix(),
        ],
      ),
    );
  }

  Widget _buildMatrix() {
    const roleIds = ['admin', 'manager', 'cashier', 'stock_manager'];

    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2.2),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(1),
        3: FlexColumnWidth(1),
        4: FlexColumnWidth(1),
      },
      border: TableBorder.all(color: AppColors.divider, width: 0.5,
          borderRadius: BorderRadius.circular(8)),
      children: [
        // Header row
        TableRow(
          decoration: const BoxDecoration(color: Color(0xFFF1F5F9)),
          children: [
            _TH('Permission', isFirst: true),
            ..._rolesMeta.map((r) => _TH(r.label, color: r.color)),
          ],
        ),

        // Data rows — grouped by section
        for (final group in _permMatrix) ...[
          // Group header
          TableRow(
            decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                child: Text(group.group,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.3)),
              ),
              ...List.generate(4, (_) => const SizedBox.shrink()),
            ],
          ),
          // Permission rows
          for (final p in group.perms)
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 5, 12, 5),
                  child: Text(p.label,
                      style: const TextStyle(fontSize: 12,
                          color: AppColors.textPrimary)),
                ),
                ...roleIds.map((rid) => _PermCell(
                    has: _roleHas(rid, p.perm),
                    color: _rolesMeta
                        .firstWhere((r) => r.id == rid)
                        .color)),
              ],
            ),
        ],
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  final ({String id, String label, Color color, IconData icon, String desc}) role;
  const _RoleCard({required this.role});

  @override
  Widget build(BuildContext context) {
    final permCount = role.id == 'admin'
        ? 'Toutes'
        : '${(rolePermissions[role.id] ?? {}).length} permissions';

    return Container(
      width: 180,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: role.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: role.color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: role.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(role.icon, color: role.color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(role.label,
                  style: TextStyle(fontWeight: FontWeight.w700,
                      fontSize: 13, color: role.color)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(role.desc,
              style: const TextStyle(fontSize: 11,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Text(permCount,
              style: TextStyle(fontSize: 11,
                  color: role.color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

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
              fontSize: 11, fontWeight: FontWeight.w700,
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
                width: 20, height: 20,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(Icons.check_rounded, size: 13, color: color),
              )
            : const Text('—',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// User form dialog (create / edit)
// ═════════════════════════════════════════════════════════════════════════════

class _UserFormDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final VoidCallback onSaved;
  const _UserFormDialog({this.existing, required this.onSaved});

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
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
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  static const _roles = [
    (id: 'admin',         label: 'Administrateur',    desc: 'Accès complet'),
    (id: 'manager',       label: 'Gérant',             desc: 'Tout sauf gestion utilisateurs'),
    (id: 'cashier',       label: 'Caissier',           desc: 'Ventes, clients, factures'),
    (id: 'stock_manager', label: 'Resp. Stock',        desc: 'Produits, achats, inventaire'),
  ];

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
    if (roles.contains('admin') ||
        ((e?['permissions'] as List?)?.contains('all') ?? false)) {
      _selectedRole = 'admin';
    } else if (roles.contains('manager')) {
      _selectedRole = 'manager';
    } else if (roles.contains('stock_manager')) {
      _selectedRole = 'stock_manager';
    } else {
      _selectedRole = 'cashier';
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
        'fname':       _fnameCtrl.text.trim(),
        'lname':       _lnameCtrl.text.trim(),
        'username':    _usernameCtrl.text.trim(),
        'email':       _emailCtrl.text.trim(),
        'phone':       _phoneCtrl.text.trim(),
        'address':     _addressCtrl.text.trim(),
        'password':    _pwdCtrl.text.isNotEmpty ? _pwdCtrl.text : 'ChangeMe123!',
        'is_active':   _isActive,
        'roles':       [_selectedRole],
        'permissions': _selectedRole == 'admin' ? ['all'] : [_selectedRole],
      };
      if (_isEdit) {
        await dio.put('/users/${widget.existing!['id']}',
            data: {'id': widget.existing!['id'], ...body});
      } else {
        await dio.post('/users', data: body);
      }
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedMeta = _rolesMeta.firstWhere(
        (r) => r.id == _selectedRole, orElse: () => _rolesMeta.last);

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
                  Expanded(
                    child: TextFormField(
                      controller: _fnameCtrl,
                      decoration: const InputDecoration(labelText: 'Prénom'),
                      validator: (v) => (v?.isEmpty ?? true) ? 'Requis' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _lnameCtrl,
                      decoration: const InputDecoration(labelText: 'Nom'),
                      validator: (v) => (v?.isEmpty ?? true) ? 'Requis' : null,
                    ),
                  ),
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
                  Expanded(
                    child: TextFormField(
                      controller: _phoneCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Téléphone',
                          prefixIcon: Icon(Icons.phone_outlined)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _pwdCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: _isEdit ? 'Mot de passe (optionnel)' : 'Mot de passe',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        hintText: _isEdit ? 'Laisser vide = inchangé' : null,
                      ),
                      validator: (v) =>
                          (!_isEdit && (v?.isEmpty ?? true)) ? 'Requis' : null,
                    ),
                  ),
                ]),
                const SizedBox(height: 20),

                // Role selection — visual cards
                const Text('Rôle',
                    style: TextStyle(fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: _roles.map((r) {
                    final meta = _rolesMeta.firstWhere((m) => m.id == r.id);
                    final selected = _selectedRole == r.id;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedRole = r.id),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected
                              ? meta.color.withValues(alpha: 0.12)
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: selected
                                ? meta.color
                                : AppColors.divider,
                            width: selected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(meta.icon, size: 15,
                                color: selected ? meta.color
                                    : AppColors.textSecondary),
                            const SizedBox(width: 6),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.label,
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: selected ? meta.color
                                            : AppColors.textPrimary)),
                                Text(r.desc,
                                    style: const TextStyle(fontSize: 10,
                                        color: AppColors.textSecondary)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),

                // Permissions preview for selected role
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: selectedMeta.color.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: selectedMeta.color.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(selectedMeta.icon, size: 14,
                            color: selectedMeta.color),
                        const SizedBox(width: 6),
                        Text('Permissions du rôle ${selectedMeta.label}',
                            style: TextStyle(fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: selectedMeta.color)),
                      ]),
                      const SizedBox(height: 8),
                      if (_selectedRole == 'admin')
                        const Text(
                            'Accès total — toutes les fonctionnalités',
                            style: TextStyle(fontSize: 11,
                                color: AppColors.textSecondary))
                      else
                        Wrap(
                          spacing: 4, runSpacing: 4,
                          children: _getKeyPerms(_selectedRole)
                              .map((p) => Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: selectedMeta.color
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(p,
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: selectedMeta.color)),
                                  ))
                              .toList(),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),
                Row(children: [
                  const Text('Compte actif',
                      style: TextStyle(fontSize: 13)),
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

  List<String> _getKeyPerms(String roleId) {
    final perms = rolePermissions[roleId] ?? {};
    final labels = <String>[];
    for (final group in _permMatrix) {
      for (final p in group.perms) {
        if (perms.contains(p.perm)) {
          labels.add('${group.group}: ${p.label}');
        }
      }
    }
    return labels.take(12).toList();
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
