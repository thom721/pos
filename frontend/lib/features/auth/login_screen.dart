import 'dart:async' show unawaited;
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_connect/core/constants.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/api/local_https.dart';
import 'package:pos_connect/providers/auth_provider.dart';
import 'package:pos_connect/shared/widgets/pos_logo.dart';
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
  bool _autoDiscovering = false;
  bool _usingAutoDiscoveredServer = false;

  final _cloudFormKey = GlobalKey<FormState>();
  final _localFormKey = GlobalKey<FormState>();

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    // Android est cloud-only : pas de serveur local à charger.
    if (!kIsWeb && !_isAndroid) _initLocalServer();
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

  Future<void> _initLocalServer() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(AppConstants.serverUrlKey) ?? '';
    final ip  = prefs.getString(AppConstants.serverIpKey)  ?? '';
    // _extractIp() normalise une éventuelle ancienne valeur "http://ip:9003"
    // (format d'avant le passage au HTTPS obligatoire) en simple IP — sinon
    // elle réapparaît telle quelle dans le champ et _submitLocal() la
    // remange plus tard en pensant recevoir une IP nue.
    final display = (url.isNotEmpty && url != 'https://infini-post.local') ? _extractIp(url) : ip;
    if (display.isNotEmpty) {
      // Déjà configuré explicitement (IP manuelle ou URL) — respecter ce
      // choix, ne pas retenter l'auto-découverte à chaque lancement.
      setState(() => _serverCtrl.text = display);
      return;
    }
    if (url == 'https://infini-post.local') {
      // Mode auto-découverte déjà choisi précédemment (aucune IP mémorisée
      // volontairement, voir api_client.dart::initServerUrl) — la connexion
      // se refait via mDNS à chaque requête, déjà configurée par
      // initServerUrl() au démarrage de l'app. Juste refléter l'état dans l'UI.
      setState(() {
        _usingAutoDiscoveredServer = true;
        _serverCtrl.text = 'infini-post.local (détecté automatiquement)';
      });
      return;
    }

    // Premier lancement, rien de configuré : tenter la découverte
    // automatique via mDNS avant de forcer une saisie manuelle d'IP.
    if (!mounted) return;
    setState(() => _autoDiscovering = true);
    final found = await tryAutoDiscoverLocalServer();
    if (!mounted) return;
    if (found) {
      configureAutoDiscoveredHttps(dio);
      await prefs.setString(AppConstants.serverUrlKey, 'https://infini-post.local');
      await prefs.remove(AppConstants.serverIpKey);
      setState(() {
        _autoDiscovering = false;
        _usingAutoDiscoveredServer = true;
        _serverCtrl.text = 'infini-post.local (détecté automatiquement)';
      });
    } else {
      setState(() {
        _autoDiscovering = false;
        _showServerConfig = true;
      });
    }
  }

  Future<void> _submitCloud() async {
    if (!_cloudFormKey.currentState!.validate()) return;
    await ref.read(authProvider.notifier).cloudLogin(
      _emailCtrl.text.trim(),
      _cloudPassCtrl.text,
    );
  }

  Future<void> _showForgotPasswordDialog({String prefill = ''}) async {
    final emailCtrl = TextEditingController(text: prefill.trim());
    final codeCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    var step = 0; // 0 = saisie email, 1 = code + nouveau mot de passe
    var loading = false;
    String? error;
    String? info;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text('Mot de passe oublié'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (step == 0) ...[
                  const Text(
                    "Entrez l'email associé à votre compte — un code de "
                    'vérification à 6 chiffres vous sera envoyé.',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailCtrl,
                    autofocus: true,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                ] else ...[
                  Text(
                    info ?? 'Code envoyé à ${emailCtrl.text.trim()}',
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: codeCtrl,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                        labelText: 'Code reçu par email', counterText: ''),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: newPassCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Nouveau mot de passe'),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: loading
                  ? null
                  : () async {
                      if (step == 0) {
                        final email = emailCtrl.text.trim();
                        if (email.isEmpty) {
                          setDialogState(() => error = "L'email est requis");
                          return;
                        }
                        setDialogState(() { loading = true; error = null; });
                        try {
                          final res = await dio.post('/api/auth/forgot-password',
                              data: {'email': email});
                          setDialogState(() {
                            loading = false;
                            step = 1;
                            info = res.data['message'] as String?;
                          });
                        } catch (e) {
                          setDialogState(() {
                            loading = false;
                            error = extractAnyError(e);
                          });
                        }
                      } else {
                        if (codeCtrl.text.trim().isEmpty || newPassCtrl.text.isEmpty) {
                          setDialogState(() => error = 'Code et nouveau mot de passe requis');
                          return;
                        }
                        setDialogState(() { loading = true; error = null; });
                        try {
                          await dio.post('/api/auth/reset-password', data: {
                            'email': emailCtrl.text.trim(),
                            'code': codeCtrl.text.trim(),
                            'new_password': newPassCtrl.text,
                          });
                          if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('Mot de passe réinitialisé — vous pouvez vous connecter.'),
                              backgroundColor: AppColors.success,
                            ));
                          }
                        } catch (e) {
                          setDialogState(() {
                            loading = false;
                            error = extractAnyError(e);
                          });
                        }
                      }
                    },
              child: loading
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(step == 0 ? 'Envoyer le code' : 'Réinitialiser'),
            ),
          ],
        ),
      ),
    );
  }

  /// Ne garde que l'IP — retire un éventuel schéma ("http://"/"https://",
  /// résidu d'une ancienne valeur serverUrlKey enregistrée avant le passage
  /// au HTTPS obligatoire par saveLocalServer()) ET un éventuel ":port"
  /// (tapé par erreur, ou hérité du même ancien format "http://ip:9003").
  /// Sans le retrait du schéma, "http://127.0.0.1:9003" était coupé au
  /// premier ":" et donnait l'IP "http" — d'où un "Failed host lookup: http".
  /// Le port 9003 est le backend brut HTTP, jamais utilisé directement par
  /// le client : toute connexion passe par nginx en HTTPS (port 443) via
  /// saveLocalServer()/configureLocalHttps(), jamais par saveServerUrl().
  String _extractIp(String raw) {
    var s = raw.trim();
    final schemeIdx = s.indexOf('://');
    if (schemeIdx != -1) s = s.substring(schemeIdx + 3);
    final idx = s.indexOf(':');
    return idx == -1 ? s : s.substring(0, idx);
  }

  Future<void> _submitLocal() async {
    if (!_localFormKey.currentState!.validate()) return;
    // Serveur auto-découvert via mDNS : dio est déjà configuré
    // (configureAutoDiscoveredHttps) — ne pas l'écraser.
    if (!_usingAutoDiscoveredServer && _serverCtrl.text.trim().isNotEmpty) {
      final ip = _extractIp(_serverCtrl.text.trim());
      // TOUJOURS HTTPS + certificat épinglé (jamais saveServerUrl(), qui
      // pointerait en HTTP brut vers le port 9003 directement, hors nginx).
      await saveLocalServer(ip);
      // Best-effort : ajoute aussi l'entrée dans le fichier hosts de CETTE
      // machine (mDNS a échoué si on en est là) — non bloquant si pas de
      // droits admin, le pinning ci-dessus fait déjà fonctionner l'app.
      unawaited(tryAddHostsEntry(ip));
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
                      width: 130, height: 130,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFCC0000), width: 1),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: const PosLogo(width: 98),
                    ),
                    const SizedBox(height: 12),
                    const Text('Gérez votre business avec précision',
                        style: TextStyle(color: Color(0xFF8BA4BE), fontSize: 16)),
                    const SizedBox(height: 48),
                    ...[
                      ('Caisse rapide et intuitive', Icons.speed_rounded),
                      ('Gestion des stocks en temps réel', Icons.inventory_rounded),
                      ('Rapports et statistiques détaillés', Icons.bar_chart_rounded),
                      ('Multi-caisse & synchronisation cloud', Icons.sync_rounded),
                    ].map((f) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
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
                      if (kIsWeb) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => context.go('/'),
                            icon: const Icon(Icons.arrow_back_rounded, size: 16),
                            label: const Text('Accueil'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.textSecondary,
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (!isWide) ...[
                        Center(
                          child: Container(
                            width: 110, height: 110,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFFCC0000), width: 1),
                            ),
                            padding: const EdgeInsets.all(12),
                            child: const PosLogo(width: 86),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                      _buildErrorBanner(authState),
                      if (kIsWeb)  _buildCloudForm(authState),
                      if (!kIsWeb && _autoDiscovering) _buildAutoDiscoveringIndicator(),
                      if (!kIsWeb && !_autoDiscovering) _buildLocalForm(authState),
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
  // Android est exclusivement cloud-first : pas de serveur local, pas de toggle.
  // L'authentification utilise email + mot de passe → API cloud.

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
                      width: 110, height: 110,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFCC0000), width: 1),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: const PosLogo(width: 86),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Center(
                    child: Text('Connexion',
                        style: TextStyle(fontSize: 14,
                            color: AppColors.textSecondary)),
                  ),
                  const SizedBox(height: 32),
                  _buildErrorBanner(authState),
                  _buildCloudForm(authState),
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
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Email ou nom d\'utilisateur',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Requis';
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
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _showForgotPasswordDialog(prefill: _emailCtrl.text),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Mot de passe oublié ?',
                  style: TextStyle(fontSize: 13)),
            ),
          ),
          const SizedBox(height: 16),

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

          if (authState.loadingMessage != null) ...[
            const SizedBox(height: 10),
            Text(authState.loadingMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],

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

  // ── Auto-découverte du serveur local (mDNS) ───────────────────────────────────

  Widget _buildAutoDiscoveringIndicator() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28, height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          SizedBox(height: 16),
          Text('Recherche du serveur sur le réseau local…',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
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
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _showForgotPasswordDialog(),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Mot de passe oublié ?',
                  style: TextStyle(fontSize: 13)),
            ),
          ),
          const SizedBox(height: 4),

          GestureDetector(
            onTap: () => setState(() {
              _showServerConfig = !_showServerConfig;
              // Vider le texte d'affichage "détecté automatiquement" (pas
              // une IP valide) pour laisser un champ propre si l'utilisateur
              // veut basculer sur une adresse manuelle.
              if (_showServerConfig && _usingAutoDiscoveredServer) {
                _serverCtrl.clear();
              }
            }),
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
                labelText: 'Adresse IP du serveur',
                hintText: '192.168.0.104',
                prefixIcon: Icon(Icons.router_outlined),
                helperText: 'Connexion HTTPS sécurisée (port 443)',
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.:]')),
              ],
              onChanged: (_) => setState(() => _usingAutoDiscoveredServer = false),
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

          if (authState.loadingMessage != null) ...[
            const SizedBox(height: 10),
            Text(authState.loadingMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ],
      ),
    );
  }
}
