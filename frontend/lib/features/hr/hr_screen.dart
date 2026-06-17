import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/providers/auth_provider.dart';
import 'package:pos_connect/core/permissions.dart';

// ── Formatters ────────────────────────────────────────────────────────────────
final _money = NumberFormat('#,##0.00', 'fr');
String _fmt(dynamic v) => v == null ? '0.00' : _money.format(double.tryParse(v.toString()) ?? 0);

// ═════════════════════════════════════════════════════════════════════════════
// Main HR Screen
// ═════════════════════════════════════════════════════════════════════════════

class HrScreen extends ConsumerStatefulWidget {
  const HrScreen({super.key});

  @override
  ConsumerState<HrScreen> createState() => _HrScreenState();
}

class _HrScreenState extends ConsumerState<HrScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
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
        title: const Text('Ressources Humaines & Paie'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(icon: Icon(Icons.badge_outlined),       text: 'Employés'),
            Tab(icon: Icon(Icons.account_balance_outlined), text: 'Prêts'),
            Tab(icon: Icon(Icons.payments_outlined),    text: 'Paie'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _EmployeesTab(),
          _LoansTab(),
          _PayrollTab(),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Tab 1 — Employees
// ═════════════════════════════════════════════════════════════════════════════

class _EmployeesTab extends ConsumerStatefulWidget {
  const _EmployeesTab();

  @override
  ConsumerState<_EmployeesTab> createState() => _EmployeesTabState();
}

class _EmployeesTabState extends ConsumerState<_EmployeesTab> {
  List<dynamic> _employees = [];
  List<dynamic> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await Future.wait([
        dio.get('/api/hr/employees/'),
        dio.get('/api/users/'),
      ]);
      setState(() {
        _employees = res[0].data is List ? res[0].data : [];
        _users     = res[1].data is List ? res[1].data : [];
      });
    } catch (_) {} finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _canCreate => ref.read(authProvider).user?.hasPermission(Perm.employeesCreate) ?? false;

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: _canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _showDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Nouveau profil'),
            )
          : null,
      body: _employees.isEmpty
          ? const Center(child: Text('Aucun profil employé'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _employees.length,
              itemBuilder: (_, i) => _EmployeeCard(
                profile: _employees[i],
                onEdit: () => _showDialog(existing: _employees[i]),
              ),
            ),
    );
  }

  void _showDialog({Map<String, dynamic>? existing}) {
    showDialog(
      context: context,
      builder: (_) => _EmployeeDialog(
        existing: existing,
        users: _users,
        onSaved: _load,
      ),
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  final Map<String, dynamic> profile;
  final VoidCallback onEdit;

  const _EmployeeCard({required this.profile, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final active = profile['is_active'] as bool? ?? true;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: active ? AppColors.primary.withValues(alpha: 0.1) : Colors.grey.shade200,
          child: Icon(Icons.person_outline,
              color: active ? AppColors.primary : Colors.grey),
        ),
        title: Text(profile['full_name'] ?? profile['username'] ?? '—',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          [
            if (profile['position'] != null) profile['position'],
            if (profile['department'] != null) profile['department'],
          ].join(' · '),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${_fmt(profile['base_salary'])} HTG',
                style: const TextStyle(fontWeight: FontWeight.w600,
                    color: AppColors.primary)),
            const SizedBox(width: 8),
            IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: onEdit),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Tab 2 — Loans
// ═════════════════════════════════════════════════════════════════════════════

class _LoansTab extends ConsumerStatefulWidget {
  const _LoansTab();

  @override
  ConsumerState<_LoansTab> createState() => _LoansTabState();
}

class _LoansTabState extends ConsumerState<_LoansTab> {
  List<dynamic> _loans = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await dio.get('/api/hr/loans/');
      setState(() => _loans = res.data is List ? res.data : []);
    } catch (_) {} finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _canCreate => ref.read(authProvider).user?.hasPermission(Perm.loansCreate) ?? false;
  bool get _canApprove => ref.read(authProvider).user?.hasPermission(Perm.loansApprove) ?? false;

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: _canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _showDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Nouveau prêt'),
            )
          : null,
      body: _loans.isEmpty
          ? const Center(child: Text('Aucun prêt enregistré'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _loans.length,
              itemBuilder: (_, i) => _LoanCard(
                loan: _loans[i],
                canApprove: _canApprove,
                onRefresh: _load,
              ),
            ),
    );
  }

  void _showDialog() {
    showDialog(
      context: context,
      builder: (_) => _LoanDialog(onSaved: _load),
    );
  }
}

class _LoanCard extends StatelessWidget {
  final Map<String, dynamic> loan;
  final bool canApprove;
  final VoidCallback onRefresh;

  const _LoanCard({required this.loan, required this.canApprove, required this.onRefresh});

  Color get _statusColor {
    return switch (loan['status']) {
      'active'    => AppColors.warning,
      'paid'      => AppColors.success,
      'cancelled' => AppColors.textSecondary,
      _           => AppColors.textSecondary,
    };
  }

  String get _statusLabel {
    return switch (loan['status']) {
      'active'    => 'Actif',
      'paid'      => 'Remboursé',
      'cancelled' => 'Annulé',
      _           => loan['status'] ?? '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final balance = double.tryParse(loan['balance']?.toString() ?? '0') ?? 0;
    final total   = double.tryParse(loan['total_amount']?.toString() ?? '0') ?? 0;
    final progress = total > 0 ? (total - balance) / total : 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(loan['reference'] ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w700,
                              fontSize: 13)),
                      Text(loan['employee_name'] ?? loan['employee_id'] ?? '—',
                          style: const TextStyle(fontSize: 12,
                              color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(_statusLabel,
                      style: TextStyle(color: _statusColor,
                          fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _InfoChip('Total',    '${_fmt(loan['total_amount'])} HTG'),
                _InfoChip('Solde',    '${_fmt(loan['balance'])} HTG'),
                _InfoChip('Mensualité', '${_fmt(loan['monthly_deduction'])} HTG'),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: AppColors.divider,
              valueColor: AlwaysStoppedAnimation(AppColors.primary),
              borderRadius: BorderRadius.circular(4),
            ),
            if (canApprove && loan['status'] == 'active' && loan['approved_by'] == null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.pending_outlined, size: 14, color: AppColors.warning),
                  const SizedBox(width: 4),
                  const Text('En attente d\'approbation',
                      style: TextStyle(fontSize: 11, color: AppColors.warning)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () async {
                      await dio.patch('/api/hr/loans/${loan['id']}/approve');
                      onRefresh();
                    },
                    icon: const Icon(Icons.check_circle_outline, size: 14),
                    label: const Text('Approuver'),
                    style: TextButton.styleFrom(foregroundColor: AppColors.success),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      await dio.patch('/api/hr/loans/${loan['id']}/cancel');
                      onRefresh();
                    },
                    icon: const Icon(Icons.cancel_outlined, size: 14),
                    label: const Text('Annuler'),
                    style: TextButton.styleFrom(foregroundColor: AppColors.error),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Tab 3 — Payroll
// ═════════════════════════════════════════════════════════════════════════════

class _PayrollTab extends ConsumerStatefulWidget {
  const _PayrollTab();

  @override
  ConsumerState<_PayrollTab> createState() => _PayrollTabState();
}

class _PayrollTabState extends ConsumerState<_PayrollTab> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await dio.get('/api/payroll/periods/');
      setState(() => _data = res.data is Map ? res.data as Map<String, dynamic> : null);
    } catch (_) {} finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _canCreate  => ref.read(authProvider).user?.hasPermission(Perm.payrollCreate)  ?? false;

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final periods = (_data?['data'] as List?) ?? [];
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: _canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _showCreateDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Nouvelle période'),
            )
          : null,
      body: periods.isEmpty
          ? const Center(child: Text('Aucune période de paie'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: periods.length,
              itemBuilder: (_, i) => _PayrollPeriodCard(
                period: periods[i],
                onRefresh: _load,
              ),
            ),
    );
  }

  void _showCreateDialog() {
    showDialog(
      context: context,
      builder: (_) => _PayrollPeriodDialog(onSaved: _load),
    );
  }
}

class _PayrollPeriodCard extends StatelessWidget {
  final Map<String, dynamic> period;
  final VoidCallback onRefresh;

  const _PayrollPeriodCard({required this.period, required this.onRefresh});

  Color get _statusColor => switch (period['status']) {
    'draft'      => AppColors.textSecondary,
    'processing' => AppColors.warning,
    'paid'       => AppColors.success,
    'cancelled'  => AppColors.error,
    _            => AppColors.textSecondary,
  };

  String get _statusLabel => switch (period['status']) {
    'draft'      => 'Brouillon',
    'processing' => 'En cours',
    'paid'       => 'Payé',
    'cancelled'  => 'Annulé',
    _            => period['status'] ?? '',
  };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDetail(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(period['label'] ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        Text(period['reference'] ?? '',
                            style: const TextStyle(fontSize: 11,
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(_statusLabel,
                        style: TextStyle(color: _statusColor, fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _InfoChip('Brut',       '${_fmt(period['total_gross'])} HTG'),
                  _InfoChip('Déductions', '${_fmt(period['total_deductions'])} HTG'),
                  _InfoChip('Net',        '${_fmt(period['total_net'])} HTG',
                      highlight: true),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PayrollPeriodDetail(
        period: period,
        onRefresh: onRefresh,
      ),
    );
  }
}

// ── Payroll Period Detail Bottom Sheet ────────────────────────────────────────

class _PayrollPeriodDetail extends StatefulWidget {
  final Map<String, dynamic> period;
  final VoidCallback onRefresh;

  const _PayrollPeriodDetail({required this.period, required this.onRefresh});

  @override
  State<_PayrollPeriodDetail> createState() => _PayrollPeriodDetailState();
}

class _PayrollPeriodDetailState extends State<_PayrollPeriodDetail> {
  Map<String, dynamic>? _detail;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() => _loading = true);
    try {
      final res = await dio.get('/api/payroll/periods/${widget.period['id']}');
      setState(() => _detail = res.data as Map<String, dynamic>?);
    } catch (_) {} finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _action(String endpoint, String confirmMsg) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmer'),
        content: Text(confirmMsg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmer')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await dio.post(endpoint);
      widget.onRefresh();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.period['status'] ?? 'draft';
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Column(
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10),
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(widget.period['label'] ?? '',
                      style: const TextStyle(fontSize: 18,
                          fontWeight: FontWeight.w700)),
                ),
                if (status == 'draft')
                  ElevatedButton.icon(
                    onPressed: () => _action(
                      '/api/payroll/periods/${widget.period['id']}/process',
                      'Calculer les bulletins de salaire pour cette période ?',
                    ),
                    icon: const Icon(Icons.calculate_outlined, size: 16),
                    label: const Text('Calculer'),
                  ),
                if (status == 'processing') ...[
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _action(
                      '/api/payroll/periods/${widget.period['id']}/pay',
                      'Marquer toute la paie comme versée ? Les soldes des prêts seront mis à jour.',
                    ),
                    icon: const Icon(Icons.payments_outlined, size: 16),
                    label: const Text('Payer'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success),
                  ),
                ],
              ],
            ),
          ),
          // Summary row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _InfoChip('Brut', '${_fmt(widget.period['total_gross'])} HTG'),
                _InfoChip('Déductions', '${_fmt(widget.period['total_deductions'])} HTG'),
                _InfoChip('Net', '${_fmt(widget.period['total_net'])} HTG',
                    highlight: true),
              ],
            ),
          ),
          const Divider(height: 24),
          // Entries list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _buildEntries(),
          ),
        ],
      ),
    );
  }

  Widget _buildEntries() {
    final entries = (_detail?['entries'] as List?) ?? [];
    if (entries.isEmpty) return const Center(child: Text('Aucune ligne'));
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: entries.length,
      itemBuilder: (_, i) => _EntryCard(entry: entries[i]),
    );
  }
}

class _EntryCard extends StatelessWidget {
  final Map<String, dynamic> entry;
  const _EntryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final loans = (entry['loan_deductions'] as List?) ?? [];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry['employee_name'] ?? entry['employee_id'] ?? '—',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text('Net: ${_fmt(entry['net_salary'])} HTG',
                    style: const TextStyle(fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _MiniChip('Brut', _fmt(entry['gross_salary'])),
                const SizedBox(width: 6),
                _MiniChip('Prêts', _fmt(entry['loan_deduction']),
                    color: AppColors.error),
                if ((double.tryParse(entry['other_deductions']?.toString() ?? '0') ?? 0) > 0) ...[
                  const SizedBox(width: 6),
                  _MiniChip('Autres', _fmt(entry['other_deductions']),
                      color: AppColors.warning),
                ],
              ],
            ),
            if (loans.isNotEmpty) ...[
              const SizedBox(height: 6),
              ...loans.map((ld) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    const Icon(Icons.arrow_right, size: 14,
                        color: AppColors.textSecondary),
                    Text('${ld['reference'] ?? 'Prêt'}: -${_fmt(ld['amount'])} HTG',
                        style: const TextStyle(fontSize: 11,
                            color: AppColors.textSecondary)),
                  ],
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Dialogs
// ═════════════════════════════════════════════════════════════════════════════

class _EmployeeDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final List<dynamic> users;
  final VoidCallback onSaved;

  const _EmployeeDialog({this.existing, required this.users, required this.onSaved});

  @override
  State<_EmployeeDialog> createState() => _EmployeeDialogState();
}

class _EmployeeDialogState extends State<_EmployeeDialog> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedUserId;
  final _posCtrl  = TextEditingController();
  final _deptCtrl = TextEditingController();
  final _salCtrl  = TextEditingController();
  String _salaryType = 'monthly';
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _selectedUserId = widget.existing!['user_id']?.toString();
      _posCtrl.text   = widget.existing!['position']   ?? '';
      _deptCtrl.text  = widget.existing!['department'] ?? '';
      _salCtrl.text   = widget.existing!['base_salary']?.toString() ?? '0';
      _salaryType     = widget.existing!['salary_type'] ?? 'monthly';
    }
  }

  @override
  void dispose() {
    _posCtrl.dispose(); _deptCtrl.dispose(); _salCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final body = {
        'user_id':     _selectedUserId,
        'position':    _posCtrl.text.trim(),
        'department':  _deptCtrl.text.trim(),
        'base_salary': double.tryParse(_salCtrl.text) ?? 0,
        'salary_type': _salaryType,
        'is_active':   true,
      };
      if (_isEdit) {
        await dio.put('/api/hr/employees/${widget.existing!['id']}', data: body);
      } else {
        await dio.post('/api/hr/employees/', data: body);
      }
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(_isEdit ? 'Modifier le profil' : 'Nouveau profil employé',
                      style: const TextStyle(fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context)),
                ]),
                const SizedBox(height: 16),
                if (!_isEdit)
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Utilisateur'),
                    items: widget.users.map<DropdownMenuItem<String>>((u) {
                      return DropdownMenuItem(
                        value: u['id']?.toString(),
                        child: Text('${u['fname']} ${u['lname']} (${u['username']})'),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => _selectedUserId = v),
                    validator: (v) => v == null ? 'Requis' : null,
                  ),
                if (!_isEdit) const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _posCtrl,
                      decoration: const InputDecoration(labelText: 'Poste'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _deptCtrl,
                      decoration: const InputDecoration(labelText: 'Département'),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _salCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Salaire de base (HTG)'),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Requis' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _salaryType,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: const [
                        DropdownMenuItem(value: 'monthly', child: Text('Mensuel')),
                        DropdownMenuItem(value: 'weekly',  child: Text('Hebdo')),
                        DropdownMenuItem(value: 'daily',   child: Text('Journalier')),
                      ],
                      onChanged: (v) => setState(() => _salaryType = v!),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity, height: 48,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Enregistrement...' : 'Enregistrer'),
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

// ── Loan Dialog ───────────────────────────────────────────────────────────────

class _LoanDialog extends StatefulWidget {
  final VoidCallback onSaved;
  const _LoanDialog({required this.onSaved});

  @override
  State<_LoanDialog> createState() => _LoanDialogState();
}

class _LoanDialogState extends State<_LoanDialog> {
  final _formKey = GlobalKey<FormState>();
  List<dynamic> _employees = [];
  String? _employeeId;
  String _loanType = 'loan';
  final _descCtrl    = TextEditingController();
  final _amountCtrl  = TextEditingController();
  final _monthlyCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    try {
      final res = await dio.get('/api/hr/employees/');
      setState(() => _employees = res.data is List ? res.data : []);
    } catch (_) {}
  }

  @override
  void dispose() {
    _descCtrl.dispose(); _amountCtrl.dispose(); _monthlyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await dio.post('/api/hr/loans/', data: {
        'employee_id':       _employeeId,
        'loan_type':         _loanType,
        'description':       _descCtrl.text.trim(),
        'total_amount':      double.parse(_amountCtrl.text),
        'monthly_deduction': double.parse(_monthlyCtrl.text),
      });
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  const Text('Nouveau prêt / achat à crédit',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context)),
                ]),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Employé'),
                  items: _employees.map<DropdownMenuItem<String>>((e) =>
                      DropdownMenuItem(
                        value: e['user_id']?.toString(),
                        child: Text(e['full_name'] ?? e['user_id'] ?? ''),
                      )).toList(),
                  onChanged: (v) => setState(() => _employeeId = v),
                  validator: (v) => v == null ? 'Requis' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _loanType,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(value: 'loan',            child: Text('Prêt en espèces')),
                    DropdownMenuItem(value: 'credit_purchase', child: Text('Achat à crédit')),
                  ],
                  onChanged: (v) => setState(() => _loanType = v!),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descCtrl,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _amountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Montant total (HTG)'),
                      validator: (v) => (v == null || v.isEmpty) ? 'Requis' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _monthlyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Déduction / période (HTG)'),
                      validator: (v) => (v == null || v.isEmpty) ? 'Requis' : null,
                    ),
                  ),
                ]),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity, height: 48,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Enregistrement...' : 'Enregistrer'),
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

// ── Payroll Period Dialog ─────────────────────────────────────────────────────

class _PayrollPeriodDialog extends StatefulWidget {
  final VoidCallback onSaved;
  const _PayrollPeriodDialog({required this.onSaved});

  @override
  State<_PayrollPeriodDialog> createState() => _PayrollPeriodDialogState();
}

class _PayrollPeriodDialogState extends State<_PayrollPeriodDialog> {
  final _formKey  = GlobalKey<FormState>();
  final _labelCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime? _start;
  DateTime? _end;
  DateTime? _payDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start   = DateTime(now.year, now.month, 1);
    _end     = DateTime(now.year, now.month + 1, 0);
    _payDate = DateTime(now.year, now.month + 1, 5);
    _labelCtrl.text =
        '${DateFormat('MMMM yyyy', 'fr').format(now)[0].toUpperCase()}'
        '${DateFormat('MMMM yyyy', 'fr').format(now).substring(1)}';
  }

  @override
  void dispose() {
    _labelCtrl.dispose(); _notesCtrl.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDate(DateTime initial) => showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2020),
    lastDate: DateTime(2030),
  );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await dio.post('/api/payroll/periods/', data: {
        'label':        _labelCtrl.text.trim(),
        'period_start': _start!.toIso8601String().split('T').first,
        'period_end':   _end!.toIso8601String().split('T').first,
        'pay_date':     _payDate!.toIso8601String().split('T').first,
        'notes':        _notesCtrl.text.trim(),
      });
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy');
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  const Text('Nouvelle période de paie',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context)),
                ]),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _labelCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Libellé (ex: Juin 2026)'),
                  validator: (v) => (v == null || v.isEmpty) ? 'Requis' : null,
                ),
                const SizedBox(height: 12),
                // Date pickers
                Row(children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final d = await _pickDate(_start!);
                        if (d != null) setState(() => _start = d);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Début période'),
                        child: Text(_start == null ? '—' : df.format(_start!)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final d = await _pickDate(_end!);
                        if (d != null) setState(() => _end = d);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Fin période'),
                        child: Text(_end == null ? '—' : df.format(_end!)),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final d = await _pickDate(_payDate!);
                    if (d != null) setState(() => _payDate = d);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                        labelText: 'Date de versement',
                        prefixIcon: Icon(Icons.calendar_month_outlined)),
                    child: Text(_payDate == null ? '—' : df.format(_payDate!)),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(labelText: 'Notes (optionnel)'),
                  maxLines: 2,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity, height: 48,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Création...' : 'Créer la période'),
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

// ═════════════════════════════════════════════════════════════════════════════
// Shared widgets
// ═════════════════════════════════════════════════════════════════════════════

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _InfoChip(this.label, this.value, {this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: highlight ? AppColors.primary : AppColors.textPrimary,
        )),
      ],
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _MiniChip(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (color ?? AppColors.textSecondary).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$label: $value HTG',
          style: TextStyle(fontSize: 10, color: color ?? AppColors.textSecondary,
              fontWeight: FontWeight.w500)),
    );
  }
}
