import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_connect/core/constants.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/providers/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  // Cloud fields
  final _emailCtrl     = TextEditingController();
  final _cloudPassCtrl = TextEditingController();

  // Local fields
  final _usernameCtrl  = TextEditingController();
  final _localPassCtrl = TextEditingController();
  final _serverCtrl    = TextEditingController();

  bool _obscureCloud = true;
  bool _obscureLocal = true;
  bool _showServerConfig = false;

  final _cloudFormKey = GlobalKey<FormState>();
  final _localFormKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() => setState(() {}));
    if (!kIsWeb) _loadSavedServer();
  }

  @override
  void dispose() {
    _tab.dispose();
    _emailCtrl.dispose();
    _cloudPassCtrl.dispose();
    _usernameCtrl.dispose();
    _localPassCtrl.dispose();
    _serverCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSavedServer() async {
    final prefs = await SharedPreferences.getInstance();
    final ip = prefs.getString(AppConstants.serverIpKey);
    if (ip != null && ip.isNotEmpty) {
      setState(() => _serverCtrl.text = ip);
    }
  }

  Future<void> _submitCloud() async {
    if (!_cloudFormKey.currentState!.validate()) return;
    await ref
        .read(authProvider.notifier)
        .cloudLogin(_emailCtrl.text.trim(), _cloudPassCtrl.text);
  }

  Future<void> _submitLocal() async {
    if (!_localFormKey.currentState!.validate()) return;
    await saveLocalServer(_serverCtrl.text.trim());
    await ref
        .read(authProvider.notifier)
        .login(_usernameCtrl.text.trim(), _localPassCtrl.text);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          // ── Left branding panel ──────────────────────────────────────────
          if (isWide)
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1B2A3B), Color(0xFF0D1E30)],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.point_of_sale,
                          color: Colors.white, size: 40),
                    ),
                    const SizedBox(height: 24),
                    const Text('POS Connect',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5)),
                    const SizedBox(height: 12),
                    const Text('Gérez votre commerce avec précision',
                        style: TextStyle(
                            color: Color(0xFF8BA4BE), fontSize: 16)),
                    const SizedBox(height: 48),
                    ...[
                      ('Caisse rapide et intuitive', Icons.speed_rounded),
                      ('Gestion des stocks en temps réel',
                          Icons.inventory_rounded),
                      ('Rapports et statistiques détaillés',
                          Icons.bar_chart_rounded),
                      ('Multi-caisse & synchronisation cloud',
                          Icons.sync_rounded),
                    ].map((f) => Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 48),
                          child: Row(children: [
                            Icon(f.$2, color: AppColors.accent, size: 18),
                            const SizedBox(width: 12),
                            Text(f.$1,
                                style: const TextStyle(
                                    color: Color(0xFFB8CCE0), fontSize: 14)),
                          ]),
                        )),
                  ],
                ),
              ),
            ),

          // ── Right form panel ─────────────────────────────────────────────
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(40),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Mobile logo
                      if (!isWide) ...[
                        Center(
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(Icons.point_of_sale,
                                color: Colors.white, size: 30),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Center(
                            child: Text('POS Connect',
                                style: TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w700))),
                        const SizedBox(height: 24),
                      ],

                      // ── Tabs (desktop only) ────────────────────────────
                      if (!kIsWeb) ...[
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.divider.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.all(4),
                          child: TabBar(
                            controller: _tab,
                            labelColor: AppColors.textPrimary,
                            unselectedLabelColor: AppColors.textSecondary,
                            indicator: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(7),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1))
                              ],
                            ),
                            indicatorSize: TabBarIndicatorSize.tab,
                            dividerColor: Colors.transparent,
                            tabs: const [
                              Tab(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.cloud_outlined, size: 16),
                                    SizedBox(width: 6),
                                    Text('Compte cloud',
                                        style: TextStyle(fontSize: 13)),
                                  ],
                                ),
                              ),
                              Tab(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.dns_outlined, size: 16),
                                    SizedBox(width: 6),
                                    Text('Serveur local',
                                        style: TextStyle(fontSize: 13)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                      ],

                      // ── Error banner ──────────────────────────────────
                      if (authState.error != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color:
                                    AppColors.error.withValues(alpha: 0.3)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.error_outline,
                                color: AppColors.error, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(authState.error!,
                                    style: const TextStyle(
                                        color: AppColors.error,
                                        fontSize: 13))),
                          ]),
                        ),
                      ],

                      // Web : toujours cloud
                      // Desktop : selon l'onglet sélectionné
                      if (kIsWeb || _tab.index == 0)
                        _buildCloudForm(authState),
                      if (!kIsWeb && _tab.index == 1)
                        _buildLocalForm(authState),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCloudForm(AuthState authState) {
    return Form(
      key: _cloudFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Connexion',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Accédez à votre espace POS Connect',
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 28),

          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Adresse email',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Requis';
              if (!v.contains('@')) return 'Email invalide';
              return null;
            },
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _cloudPassCtrl,
            obscureText: _obscureCloud,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submitCloud(),
            decoration: InputDecoration(
              labelText: 'Mot de passe',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(_obscureCloud
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () =>
                    setState(() => _obscureCloud = !_obscureCloud),
              ),
            ),
            validator: (v) =>
                v == null || v.isEmpty ? 'Requis' : null,
          ),
          const SizedBox(height: 24),

          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: authState.isLoading ? null : _submitCloud,
              child: authState.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Se connecter',
                      style: TextStyle(fontSize: 15)),
            ),
          ),
          const SizedBox(height: 20),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("Pas encore de compte ?",
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => context.push('/register'),
                child: const Text('Créer un compte',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                        decorationColor: AppColors.primary)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLocalForm(AuthState authState) {
    return Form(
      key: _localFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Connexion locale',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text("Connectez-vous à votre serveur sur le réseau local",
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 28),

          TextFormField(
            controller: _usernameCtrl,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: "Nom d'utilisateur",
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            validator: (v) =>
                v == null || v.isEmpty ? 'Requis' : null,
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _localPassCtrl,
            obscureText: _obscureLocal,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submitLocal(),
            decoration: InputDecoration(
              labelText: 'Mot de passe',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(_obscureLocal
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () =>
                    setState(() => _obscureLocal = !_obscureLocal),
              ),
            ),
            validator: (v) =>
                v == null || v.isEmpty ? 'Requis' : null,
          ),
          const SizedBox(height: 12),

          GestureDetector(
            onTap: () =>
                setState(() => _showServerConfig = !_showServerConfig),
            behavior: HitTestBehavior.opaque,
            child: Row(children: [
              const Icon(Icons.dns_outlined,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              const Text('Adresse IP du serveur',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(width: 4),
              Icon(
                  _showServerConfig
                      ? Icons.expand_less
                      : Icons.expand_more,
                  size: 16,
                  color: AppColors.textSecondary),
            ]),
          ),
          if (_showServerConfig) ...[
            const SizedBox(height: 10),
            TextFormField(
              controller: _serverCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Adresse IP du serveur',
                hintText: '192.168.0.104',
                prefixIcon: Icon(Icons.router_outlined),
                helperText: 'Ex: 192.168.0.104 — se connecte via https://infini-post.local',
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
              ],
            ),
          ],
          const SizedBox(height: 24),

          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: authState.isLoading ? null : _submitLocal,
              child: authState.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Se connecter',
                      style: TextStyle(fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}
