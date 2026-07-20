import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/core/permissions.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/warehouse_model.dart';
import 'package:pos_connect/providers/auth_provider.dart';
import 'package:pos_connect/providers/settings_provider.dart';
import 'package:pos_connect/providers/warehouse_provider.dart';

// ── Providers ──────────────────────────────────────────────────────────────

final _usersProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) async {
    final res = await dio.get('/api/users/');
    return (res.data as List).cast<Map<String, dynamic>>();
  },
);

// ── Screen ─────────────────────────────────────────────────────────────────

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  bool get _canEditCompany =>
      ref.read(authProvider).user?.hasPermission(Perm.configUpdate) ?? false;

  bool get _isAdmin =>
      ref.read(authProvider).user?.isAdmin ?? false;

  int get _tabCount => 1 + (_canEditCompany ? 1 : 0) + (_isAdmin ? 1 : 0);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _tabCount, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: AppColors.surface,
          child: TabBar(
            controller: _tabs,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              const Tab(icon: Icon(Icons.person_rounded), text: 'Mon profil'),
              if (_canEditCompany)
                const Tab(icon: Icon(Icons.storefront_rounded), text: 'Entreprise'),
              if (_isAdmin)
                const Tab(
                    icon: Icon(Icons.manage_accounts_rounded),
                    text: 'Utilisateurs'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              const _ProfileForm(),
              if (_canEditCompany) const _CompanyForm(),
              if (_isAdmin) const _UsersManagement(),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Profile form ───────────────────────────────────────────────────────────

class _ProfileForm extends ConsumerStatefulWidget {
  const _ProfileForm();

  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fnameCtrl;
  late final TextEditingController _lnameCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _pwdCtrl;
  late final TextEditingController _pwdConfirmCtrl;
  bool _saving = false;
  bool _showPwd = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    _fnameCtrl = TextEditingController(text: user?.fname ?? '');
    _lnameCtrl = TextEditingController(text: user?.lname ?? '');
    _usernameCtrl = TextEditingController(text: user?.username ?? '');
    _pwdCtrl = TextEditingController();
    _pwdConfirmCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _fnameCtrl.dispose();
    _lnameCtrl.dispose();
    _usernameCtrl.dispose();
    _pwdCtrl.dispose();
    _pwdConfirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_pwdCtrl.text.isNotEmpty && _pwdCtrl.text != _pwdConfirmCtrl.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Les mots de passe ne correspondent pas'),
            backgroundColor: AppColors.error),
      );
      return;
    }
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;

    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{
        'id': userId,
        'fname': _fnameCtrl.text.trim(),
        'lname': _lnameCtrl.text.trim(),
        'username': _usernameCtrl.text.trim(),
        'phone': '',
        'address': '',
        'email': 'user@pos.local',
        'is_active': true,
        if (_pwdCtrl.text.isNotEmpty) 'password': _pwdCtrl.text,
      };
      await dio.put('/api/users/$userId', data: body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Profil mis à jour'),
              backgroundColor: AppColors.success),
        );
        _pwdCtrl.clear();
        _pwdConfirmCtrl.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erreur: $e'),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final initial = (user?.fname.isNotEmpty == true
            ? user!.fname[0]
            : user?.username.isNotEmpty == true
                ? user!.username[0]
                : 'U')
        .toUpperCase();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            // Avatar
            CircleAvatar(
              radius: 48,
              backgroundColor: AppColors.primary,
              child: Text(initial,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 8),
            Text(user?.fullName ?? '',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            Text('@${user?.username ?? ''}',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 14)),
            const SizedBox(height: 32),

            // Form
            _FormCard(
              title: 'Informations personnelles',
              icon: Icons.person_rounded,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _fnameCtrl,
                        decoration: const InputDecoration(labelText: 'Prénom'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Requis'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _lnameCtrl,
                        decoration: const InputDecoration(labelText: 'Nom'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Requis'
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _usernameCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Nom d\'utilisateur'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requis' : null,
                ),
              ],
            ),
            const SizedBox(height: 20),

            _FormCard(
              title: 'Changer le mot de passe',
              icon: Icons.lock_rounded,
              children: [
                TextFormField(
                  controller: _pwdCtrl,
                  obscureText: !_showPwd,
                  decoration: InputDecoration(
                    labelText: 'Nouveau mot de passe',
                    hintText: 'Laisser vide pour ne pas changer',
                    suffixIcon: IconButton(
                      icon: Icon(_showPwd
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded),
                      onPressed: () => setState(() => _showPwd = !_showPwd),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _pwdConfirmCtrl,
                  obscureText: !_showPwd,
                  decoration: const InputDecoration(
                      labelText: 'Confirmer le mot de passe'),
                ),
              ],
            ),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.save_rounded),
                label:
                    Text(_saving ? 'Enregistrement...' : 'Enregistrer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Company form ──────────────────────────────────────────────────────────

class _CompanyForm extends ConsumerStatefulWidget {
  const _CompanyForm();

  @override
  ConsumerState<_CompanyForm> createState() => _CompanyFormState();
}

class _CompanyFormState extends ConsumerState<_CompanyForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _footerCtrl;
  bool _saving = false;
  bool _uploadingLogo = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _nameCtrl    = TextEditingController(text: s.businessName);
    _emailCtrl   = TextEditingController(text: s.email);
    _phoneCtrl   = TextEditingController(text: s.phone);
    _addressCtrl = TextEditingController(text: s.address);
    _footerCtrl  = TextEditingController(text: s.receiptFooter);
  }

  /// Met à jour les contrôleurs quand la config change (changement de dépôt).
  void _applySettings(AppSettings s) {
    _nameCtrl.text    = s.businessName;
    _emailCtrl.text   = s.email;
    _phoneCtrl.text   = s.phone;
    _addressCtrl.text = s.address;
    _footerCtrl.text  = s.receiptFooter;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _footerCtrl.dispose();
    super.dispose();
  }

  Future<void> _uploadLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() => _uploadingLogo = true);
    try {
      final file = result.files.first;
      final FormData form;
      if (kIsWeb) {
        form = FormData.fromMap({
          'file': MultipartFile.fromBytes(file.bytes!, filename: file.name),
        });
      } else {
        form = FormData.fromMap({
          'file': await MultipartFile.fromFile(file.path!, filename: file.name),
        });
      }
      final res = await dio.post('/api/config/logo', data: form);
      final logoPath =
          (res.data as Map<String, dynamic>)['logo_path'] as String? ?? '';
      await ref.read(settingsProvider.notifier).save(
            ref.read(settingsProvider).copyWith(logoPath: logoPath),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Logo mis à jour'),
              backgroundColor: AppColors.success),
        );
      }
    } on DioException catch (e) {
      if (mounted) {
        final msg = (e.response?.data is Map)
            ? (e.response!.data['detail'] ?? 'Erreur upload').toString()
            : 'Erreur upload';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final current = ref.read(settingsProvider);
    await ref.read(settingsProvider.notifier).save(
          current.copyWith(
            businessName: _nameCtrl.text.trim(),
            email: _emailCtrl.text.trim(),
            phone: _phoneCtrl.text.trim(),
            address: _addressCtrl.text.trim(),
            receiptFooter: _footerCtrl.text.trim(),
          ),
        );
    setState(() => _saving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Informations entreprise mises à jour'),
            backgroundColor: AppColors.success),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Mettre à jour les contrôleurs quand le dépôt actif change
    ref.listen<AppSettings>(settingsProvider, (prev, next) {
      if (prev?.businessName != next.businessName ||
          prev?.address != next.address ||
          prev?.phone != next.phone) {
        _applySettings(next);
      }
    });

    final settings = ref.watch(settingsProvider);
    final warehouses = ref.watch(warehouseListProvider).valueOrNull ?? [];
    final activeWarehouse = ref.watch(activeWarehouseProvider);

    final typeLabel = switch (settings.businessType) {
      'restaurant' => 'Restaurant / Snack',
      'depot' => 'Dépôt / Grossiste',
      _ => 'Commerce / Épicerie',
    };
    final typeIcon = switch (settings.businessType) {
      'restaurant' => Icons.restaurant_rounded,
      'depot' => Icons.warehouse_rounded,
      _ => Icons.shopping_bag_rounded,
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Sélecteur de business ───────────────────────────────────
            if (warehouses.length > 1) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warehouse_outlined, size: 18, color: AppColors.primary),
                    const SizedBox(width: 10),
                    const Text('Business :', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<WarehouseModel>(
                          value: warehouses.firstWhere(
                            (w) => w.id == (activeWarehouse?.id ?? ''),
                            orElse: () => warehouses.firstWhere(
                              (w) => w.isDefault,
                              orElse: () => warehouses.first,
                            ),
                          ),
                          isDense: true,
                          isExpanded: true,
                          icon: const Icon(Icons.expand_more, size: 16, color: AppColors.textSecondary),
                          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                          items: warehouses.map((w) => DropdownMenuItem(
                            value: w,
                            child: Row(
                              children: [
                                Text(w.name, overflow: TextOverflow.ellipsis),
                                if (w.isDefault) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('défaut',
                                        style: TextStyle(fontSize: 10, color: AppColors.primary)),
                                  ),
                                ],
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
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Logo placeholder
            Center(
              child: Column(
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: settings.logoPath.isEmpty
                        ? Icon(typeIcon,
                            size: 40, color: AppColors.primary)
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.network(settings.logoPath,
                                fit: BoxFit.cover),
                          ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _uploadingLogo ? null : _uploadLogo,
                    icon: _uploadingLogo
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.upload_rounded, size: 16),
                    label: Text(
                        _uploadingLogo ? 'Envoi...' : 'Changer le logo',
                        style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Business type badge (read-only, redirect to settings)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(typeIcon, size: 18, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Type de commerce',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary)),
                        Text(typeLabel,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  Text('Modifier dans Paramètres',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.primary.withValues(alpha: 0.7))),
                ],
              ),
            ),
            const SizedBox(height: 20),

            _FormCard(
              title: 'Identité',
              icon: Icons.business_rounded,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nom du commerce',
                    prefixIcon: Icon(Icons.store_rounded),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requis' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email professionnel',
                    prefixIcon: Icon(Icons.email_rounded),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            _FormCard(
              title: 'Contact & Adresse',
              icon: Icons.location_on_rounded,
              children: [
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Téléphone',
                    prefixIcon: Icon(Icons.phone_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Adresse complète',
                    prefixIcon: Icon(Icons.map_rounded),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            _FormCard(
              title: 'Message reçu de caisse',
              icon: Icons.receipt_rounded,
              children: [
                TextFormField(
                  controller: _footerCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Pied de reçu',
                    hintText: 'Merci pour votre achat !',
                    prefixIcon: Icon(Icons.message_rounded),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.save_rounded),
                label: Text(_saving
                    ? 'Enregistrement...'
                    : 'Enregistrer'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ── Users management (admin only) ─────────────────────────────────────────

class _UsersManagement extends ConsumerWidget {
  const _UsersManagement();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(_usersProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              const Text('Utilisateurs',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () =>
                    _showUserDialog(context, ref, null),
                icon: const Icon(Icons.person_add_rounded, size: 16),
                label: const Text('Ajouter'),
              ),
            ],
          ),
        ),
        Expanded(
          child: usersAsync.when(
            data: (users) => ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              itemCount: users.length,
              separatorBuilder: (ctx, i) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) => _UserCard(
                user: users[i],
                onEdit: () => _showUserDialog(context, ref, users[i]),
                onDelete: () => _deleteUser(context, ref, users[i]['id']),
              ),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) => Center(
                child: Text('Erreur: $e',
                    style: const TextStyle(color: AppColors.error))),
          ),
        ),
      ],
    );
  }

  void _showUserDialog(BuildContext context, WidgetRef ref,
      Map<String, dynamic>? existing) {
    showDialog(
      context: context,
      builder: (ctx) => _UserDialog(
        existing: existing,
        onSaved: () => ref.invalidate(_usersProvider),
      ),
    );
  }

  Future<void> _deleteUser(
      BuildContext context, WidgetRef ref, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer l\'utilisateur'),
        content: const Text(
            'Cette action est irréversible. Confirmer ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await dio.delete('/api/users/$id');
      ref.invalidate(_usersProvider);
    }
  }
}

class _UserCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _UserCard(
      {required this.user, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final name =
        '${user['fname'] ?? ''} ${user['lname'] ?? ''}'.trim();
    final username = user['username'] ?? '';
    final roles = (user['roles'] as List?)?.join(', ') ?? '';
    final isActive = user['is_active'] as bool? ?? true;

    return Material(
      color: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        side: BorderSide(color: AppColors.divider),
      ),
      clipBehavior: Clip.hardEdge,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              isActive ? AppColors.primary : AppColors.textSecondary,
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : username[0].toUpperCase(),
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
        title: Text(name.isNotEmpty ? name : username,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text('@$username${roles.isNotEmpty ? ' · $roles' : ''}',
            style: const TextStyle(fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (isActive ? AppColors.success : AppColors.error)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                isActive ? 'Actif' : 'Inactif',
                style: TextStyle(
                    fontSize: 11,
                    color:
                        isActive ? AppColors.success : AppColors.error,
                    fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_rounded,
                  size: 18, color: AppColors.primary),
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_rounded,
                  size: 18, color: AppColors.error),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

// ── User create/edit dialog ────────────────────────────────────────────────

class _UserDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final VoidCallback onSaved;

  const _UserDialog({this.existing, required this.onSaved});

  @override
  State<_UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends State<_UserDialog> {
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

  static const _roles = [
    ('admin',         'Administrateur',       'Accès complet'),
    ('manager',       'Gérant',               'Tout sauf gestion utilisateurs'),
    ('cashier',       'Caissier',             'Ventes, clients, factures'),
    ('stock_manager', 'Responsable stock',    'Produits, achats, inventaire'),
  ];


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

    // Detect role from existing data
    final roles = (e?['roles'] as List?)?.map((r) => r.toString()).toList() ?? [];
    if (roles.contains('admin') || (e?['permissions'] as List?)?.contains('all') == true) {
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
    for (final c in [
      _fnameCtrl, _lnameCtrl, _usernameCtrl,
      _emailCtrl, _phoneCtrl, _addressCtrl, _pwdCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final body = {
        'fname': _fnameCtrl.text.trim(),
        'lname': _lnameCtrl.text.trim(),
        'username': _usernameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'password': _pwdCtrl.text.isNotEmpty ? _pwdCtrl.text : 'ChangeMe123!',
        'is_active': _isActive,
        'roles': [_selectedRole],
        'permissions': _selectedRole == 'admin' ? ['all'] : [_selectedRole],
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
          SnackBar(
              content: Text('Erreur: $e'),
              backgroundColor: AppColors.error),
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
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(_isEdit ? 'Modifier l\'utilisateur' : 'Nouvel utilisateur',
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _fnameCtrl,
                      decoration: const InputDecoration(labelText: 'Prénom'),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Requis' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _lnameCtrl,
                      decoration: const InputDecoration(labelText: 'Nom'),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Requis' : null,
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _usernameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Nom d\'utilisateur'),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Requis' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Requis' : null,
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _phoneCtrl,
                      decoration: const InputDecoration(labelText: 'Téléphone'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _pwdCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: _isEdit
                            ? 'Mot de passe (optionnel)'
                            : 'Mot de passe',
                        hintText: _isEdit ? 'Laisser vide' : null,
                      ),
                      validator: (v) => (!_isEdit && (v == null || v.isEmpty))
                          ? 'Requis'
                          : null,
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedRole,
                  decoration: const InputDecoration(
                    labelText: 'Rôle',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  items: _roles.map((r) {
                    final (value, label, subtitle) = r;
                    return DropdownMenuItem(
                      value: value,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(label, style: const TextStyle(fontSize: 14,
                              fontWeight: FontWeight.w500)),
                          Text(subtitle, style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _selectedRole = v!),
                ),
                const SizedBox(height: 12),
                _SwitchRow(
                  label: 'Compte actif',
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving
                        ? 'Enregistrement...'
                        : (_isEdit ? 'Mettre à jour' : 'Créer')),
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

// ── Helpers ────────────────────────────────────────────────────────────────

class _FormCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _FormCard(
      {required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final void Function(bool) onChanged;

  const _SwitchRow(
      {required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Switch(
          value: value,
          onChanged: onChanged,
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppColors.primary
                : null,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}
