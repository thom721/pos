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

  int get _tabCount => 1 + (_canEditCompany ? 1 : 0);

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
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              const _ProfileForm(),
              if (_canEditCompany) const _CompanyForm(),
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
      // warehouse_id explicite — sinon le serveur retombe sur le dépôt par
      // défaut de l'utilisateur (_wh_id), qui peut différer du business
      // actuellement sélectionné à l'écran : le logo se sauvegarde bien
      // quelque part, mais pas forcément sur la ligne AppConfig affichée ici.
      final warehouseId = ref.read(activeWarehouseProvider)?.id;
      final queryParams = warehouseId != null ? '?warehouse_id=$warehouseId' : '';
      final res = await dio.post('/api/config/logo$queryParams', data: form);
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
      'business' => 'Dépôt / Grossiste',
      _ => 'Commerce / Épicerie',
    };
    final typeIcon = switch (settings.businessType) {
      'restaurant' => Icons.restaurant_rounded,
      'business' => Icons.warehouse_rounded,
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
                            // logoPath est un chemin relatif (/static/logos/xyz.png) —
                            // Image.network exige une URL absolue, contrairement à
                            // Dio qui la résout via son baseUrl (voir LogoCacheService).
                            child: Image.network(
                                '${dio.options.baseUrl}${settings.logoPath}',
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    Icon(typeIcon, size: 40, color: AppColors.primary)),
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
