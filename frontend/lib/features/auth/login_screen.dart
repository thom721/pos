import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
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

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl     = TextEditingController();
  final _cloudPassCtrl = TextEditingController();
  final _usernameCtrl  = TextEditingController();
  final _localPassCtrl = TextEditingController();
  final _serverCtrl    = TextEditingController();

  bool _obscureCloud = true;
  bool _obscureLocal = true;
  bool _showServerConfig = false;
  int  _androidMode = 0; // 0 = réseau local, 1 = cloud

  final _cloudFormKey = GlobalKey<FormState>();
  final _localFormKey = GlobalKey<FormState>();

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) _loadSavedServer();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _cloudPassCtrl.dispose();
    _usernameCtrl.dispose();
    _localPassCtrl.dispose();
    _serverCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSavedServer() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(AppConstants.serverUrlKey) ?? '';
    final ip  = prefs.getString(AppConstants.serverIpKey)  ?? '';
    final display = (url.isNotEmpty && url != 'https://infini-post.local') ? url : ip;
    if (display.isNotEmpty) {
      setState(() => _serverCtrl.text = display);
    } else if (_isAndroid) {
      setState(() => _showServerConfig = true);
    }
  }

  Future<void> _submitCloud() async {
    if (!_cloudFormKey.currentState!.validate()) return;
    await ref.read(authProvider.notifier).cloudLogin(
      _emailCtrl.text.trim(),
      _cloudPassCtrl.text,
    );
  }

  String _buildLocalUrl(String raw) {
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    return raw.contains(':') ? 'http://$raw' : 'http://$raw:9003';
  }

  Future<void> _submitLocal() async {
    if (!_localFormKey.currentState!.validate()) return;
    if (_serverCtrl.text.trim().isNotEmpty) {
      await saveServerUrl(_buildLocalUrl(_serverCtrl.text.trim()));
    }
    await ref.read(authProvider.notifier).login(
      _usernameCtrl.text.trim(),
      _localPassCtrl.text,
    );
  }

  // ── Error banner ────────────────────────────────────────────────────────────

  Widget _buildErrorBanner(AuthState authState) {
    if (authState.error == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline, color: AppColors.error, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(authState.error!,
              style: const TextStyle(color: AppColors.error, fontSize: 13)),
        ),
      ]),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    if (_isAndroid) return _buildAndroidLayout(authState);

    final isWide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
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
                      width: 72, height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.point_of_sale,
                          color: Colors.white, size: 40),
                    ),
                    const SizedBox(height: 24),
                    const Text('POS Connect',
                        style: TextStyle(color: Colors.white, fontSize: 32,
                            fontWeight: FontWeight.w700, letterSpacing: -0.5)),
                    const SizedBox(height: 12),
                    const Text('Gérez votre commerce avec précision',
                        style: TextStyle(color: Color(0xFF8BA4BE), fontSize: 16)),
                    const SizedBox(height: 48),
                    ...[
                      ('Caisse rapide et intuitive', Icons.speed_rounded),
                      ('Gestion des stocks en temps réel', Icons.inventory_rounded),
                      ('Rapports et statistiques détaillés', Icons.bar_chart_rounded),
                      ('Multi-caisse & synchronisation cloud', Icons.sync_rounded),
                    ].map((f) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 48),
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

          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(40),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!isWide) ...[
                        Center(
                          child: Container(
                            width: 56, height: 56,
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
                                  fontSize: 26, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(height: 24),
                      ],
                      _buildErrorBanner(authState),
                      if (kIsWeb)  _buildCloudForm(authState),
                      if (!kIsWeb) _buildLocalForm(authState),
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

  // ── Android layout ──────────────────────────────────────────────────────────

  Widget _buildAndroidLayout(AuthState authState) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(Icons.point_of_sale,
                          color: Colors.white, size: 36),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Center(
                    child: Text('POS Connect',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700,
                            letterSpacing: -0.3)),
                  ),
                  const SizedBox(height: 32),

                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(
                        value: 0,
                        label: Text('Réseau local'),
                        icon: Icon(Icons.wifi_rounded, size: 16),
                      ),
                      ButtonSegment(
                        value: 1,
                        label: Text('Cloud'),
                        icon: Icon(Icons.cloud_outlined, size: 16),
                      ),
                    ],
                    selected: {_androidMode},
                    onSelectionChanged: (s) =>
                        setState(() => _androidMode = s.first),
                  ),
                  const SizedBox(height: 28),

                  _buildErrorBanner(authState),

                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _androidMode == 0
                        ? _buildLocalForm(authState)
                        : _buildCloudForm(authState),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Cloud form ──────────────────────────────────────────────────────────────

  Widget _buildCloudForm(AuthState authState) {
    return Form(
      key: _cloudFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_isAndroid) ...[
            const Text('Connexion',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Accédez à votre espace POS Connect',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 28),
          ],

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
            validator: (v) => v == null || v.isEmpty ? 'Requis' : null,
          ),
          const SizedBox(height: 24),

          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: authState.isLoading ? null : _submitCloud,
              child: authState.isLoading
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Se connecter',
                      style: TextStyle(fontSize: 15)),
            ),
          ),

          if (!_isAndroid) ...[
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
                          color: AppColors.primary, fontSize: 13,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                          decorationColor: AppColors.primary)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Local form ──────────────────────────────────────────────────────────────

  Widget _buildLocalForm(AuthState authState) {
    return Form(
      key: _localFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_isAndroid) ...[
            const Text('Connexion locale',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text("Connectez-vous à votre serveur sur le réseau local",
                style: TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 28),
          ],

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
              Icon(
                Icons.dns_outlined,
                size: 14,
                color: _serverCtrl.text.isEmpty
                    ? AppColors.error
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _serverCtrl.text.isEmpty
                      ? 'Adresse du serveur requise'
                      : 'Serveur : ${_serverCtrl.text}',
                  style: TextStyle(
                    fontSize: 12,
                    color: _serverCtrl.text.isEmpty
                        ? AppColors.error
                        : AppColors.textSecondary,
                  ),
                ),
              ),
              Icon(
                _showServerConfig
                    ? Icons.expand_less
                    : Icons.expand_more,
                size: 16,
                color: AppColors.textSecondary,
              ),
            ]),
          ),
          if (_showServerConfig) ...[
            const SizedBox(height: 10),
            TextFormField(
              controller: _serverCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Adresse du serveur',
                hintText: '192.168.0.104 ou 192.168.0.104:9003',
                prefixIcon: Icon(Icons.router_outlined),
                helperText: 'IP seule → port 9003 par défaut',
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.:]')),
              ],
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: 24),

          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: authState.isLoading ? null : _submitLocal,
              child: authState.isLoading
                  ? const SizedBox(
                      width: 20, height: 20,
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
