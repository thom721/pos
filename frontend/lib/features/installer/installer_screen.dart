import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_connect/core/constants.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═════════════════════════════════════════════════════════════════════════════
// Models
// ═════════════════════════════════════════════════════════════════════════════

enum InstallMode { server, client, both }
enum DbType { mysql, sqlite }

class InstallConfig {
  InstallMode mode;
  DbType dbType;
  // MySQL
  String dbHost;
  int dbPort;
  String dbName;
  String dbUser;
  String dbPassword;
  // SQLite
  String dbPath;
  // Server
  String serverHost;
  int serverPort;
  String serverUrl;
  // Cloud tenant credentials (replaces local admin creation)
  String cloudUrl;
  String tenantEmail;
  String tenantPassword;
  // Depot sélectionné lors de l'installation
  String selectedWarehouseId;
  String selectedWarehouseName;

  InstallConfig({
    this.serverUrl = '',
    this.mode = InstallMode.both,
    this.dbType = DbType.mysql,
    this.dbHost = '127.0.0.1',
    this.dbPort = 3307,
    this.dbName = 'pos_db',
    this.dbUser = 'pos_user',
    this.dbPassword = '',
    this.dbPath = './pos_data.db',
    this.serverHost = '0.0.0.0',
    this.serverPort = 9003,
    this.cloudUrl = '',
    this.tenantEmail = '',
    this.tenantPassword = '',
    this.selectedWarehouseId = '',
    this.selectedWarehouseName = '',
  });
}

// ═════════════════════════════════════════════════════════════════════════════
// State provider
// ═════════════════════════════════════════════════════════════════════════════

final _configProvider =
    StateProvider<InstallConfig>((ref) => InstallConfig());

// ═════════════════════════════════════════════════════════════════════════════
// Main installer screen
// ═════════════════════════════════════════════════════════════════════════════

class InstallerScreen extends ConsumerStatefulWidget {
  const InstallerScreen({super.key});

  @override
  ConsumerState<InstallerScreen> createState() => _InstallerScreenState();
}

class _InstallerScreenState extends ConsumerState<InstallerScreen> {
  int _step = 0;

  @override
  void initState() {
    super.initState();
    // Le wizard repart toujours du défaut compilé — SharedPreferences ignoré jusqu'à la fin
    dio.options.baseUrl = AppConstants.baseUrl;
  }

  final List<String> _steps = [
    'Bienvenue',
    'Mode',
    'Adresse serveur',
    'Connexion',
    'Base de données',
    'Compte cloud',
    'Installation',
    'Terminé',
  ];

  void _next() => setState(() => _step++);
  void _back() => setState(() => _step--);
  void _goTo(int s) => setState(() => _step = s);

  Widget _buildStep() {
    final cfg = ref.watch(_configProvider);
    final needsServer =
        cfg.mode == InstallMode.server || cfg.mode == InstallMode.both;

    // Determine which steps to show based on mode
    switch (_step) {
      case 0:
        return _WelcomePage(onNext: _next);
      case 1:
        return _ModePage(onNext: _next, onBack: _back);
      case 2:
        return _ServerAddressPage(onNext: _next, onBack: _back);
      case 3:
        if (!needsServer) {
          // client-only : connexion locale au serveur configuré
          return _LocalLoginPage(onNext: _next, onBack: _back);
        }
        return _DbChoicePage(onNext: _next, onBack: _back);
      case 4:
        if (!needsServer) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _goTo(6));
          return const SizedBox.shrink();
        }
        return cfg.dbType == DbType.mysql
            ? _MysqlSetupPage(onNext: _next, onBack: _back)
            : _SqliteInfoPage(onNext: _next, onBack: _back);
      case 5:
        if (!needsServer) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _goTo(6));
          return const SizedBox.shrink();
        }
        return _TenantConnectPage(onNext: _next, onBack: _back);
      case 6:
        return _InstallationPage(
            onDone: _next, onBack: _back, needsServer: needsServer);
      case 7:
        return const _DonePage();
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          // Left sidebar — stepper
          Container(
            width: 220,
            color: AppColors.sidebar,
            child: Column(
              children: [
                Container(
                  height: 72,
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.point_of_sale,
                            color: Colors.white, size: 22),
                      ),
                      const SizedBox(height: 6),
                      const Text('POS Connect',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                const Divider(color: Color(0xFF2A3F55), height: 1),
                const SizedBox(height: 16),
                ..._steps.asMap().entries.map((e) {
                  final i = e.key;
                  final label = e.value;
                  final isActive = i == _step;
                  final isDone = i < _step;
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 3),
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: isDone
                                ? AppColors.success
                                : isActive
                                    ? AppColors.primary
                                    : const Color(0xFF2A3F55),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: isDone
                                ? const Icon(Icons.check,
                                    color: Colors.white, size: 14)
                                : Text('${i + 1}',
                                    style: TextStyle(
                                        color: isActive
                                            ? Colors.white
                                            : const Color(0xFF4A6278),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          label,
                          style: TextStyle(
                            color: isActive
                                ? Colors.white
                                : isDone
                                    ? AppColors.success
                                    : const Color(0xFF8BA4BE),
                            fontSize: 12,
                            fontWeight: isActive
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          // Right content
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: KeyedSubtree(
                key: ValueKey(_step),
                child: _buildStep(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Page 0 — Bienvenue
// ═════════════════════════════════════════════════════════════════════════════

class _WelcomePage extends StatelessWidget {
  final VoidCallback onNext;
  const _WelcomePage({required this.onNext});

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      title: 'Bienvenue dans POS Connect',
      subtitle: "Assistant d'installation",
      onNext: onNext,
      showBack: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cet assistant va vous guider pour installer et configurer '
            'POS Connect sur votre système.',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          _InfoCard(
            icon: Icons.info_outline_rounded,
            color: AppColors.primary,
            title: 'Avant de commencer',
            items: const [
              'Assurez-vous d\'avoir les droits administrateur sur ce système.',
              'Si vous installez le serveur avec MySQL, MySQL doit être installé '
                  'ou vous devrez l\'installer pendant le processus.',
              'Notez bien les identifiants du compte admin que vous allez créer.',
            ],
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Page 1b — Adresse du serveur (mode client uniquement)
// ═════════════════════════════════════════════════════════════════════════════

class _ServerAddressPage extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;
  const _ServerAddressPage({required this.onNext, required this.onBack});

  @override
  ConsumerState<_ServerAddressPage> createState() => _ServerAddressPageState();
}

class _ServerAddressPageState extends ConsumerState<_ServerAddressPage> {
  late TextEditingController _urlCtrl;
  bool _testing = false;
  String? _error;
  bool _ok = false;
  List<String> _localIps = [];

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(_configProvider);
    final isClient = cfg.mode == InstallMode.client;
    _urlCtrl = TextEditingController(
      // Client : utilise l'URL runtime (compilée ou sauvegardée)
      // Serveur/Both : localhost en attendant la détection de l'IP locale
      text: cfg.serverUrl.isNotEmpty
          ? cfg.serverUrl
          : isClient
              ? dio.options.baseUrl
              : 'http://localhost:9003',
    );
    _detectLocalIps();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _detectLocalIps() async {
    if (kIsWeb) return;
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      final ips = interfaces
          .expand((i) => i.addresses)
          .map((a) => a.address)
          .where((ip) => !ip.startsWith('127.'))
          .toList();
      if (!mounted) return;
      setState(() => _localIps = ips);
      // En mode serveur, on utilise automatiquement la première IP locale détectée
      final cfg = ref.read(_configProvider);
      if (cfg.mode != InstallMode.client && ips.isNotEmpty && cfg.serverUrl.isEmpty) {
        final detected = 'http://${ips.first}:9003';
        _urlCtrl.text = detected;
        ref.read(_configProvider.notifier).state = cfg..serverUrl = detected;
      }
    } catch (_) {}
  }

  Future<void> _test() async {
    final url = _urlCtrl.text.trim().replaceAll(RegExp(r'/+$'), '');
    if (url.isEmpty) return;
    final previousUrl = dio.options.baseUrl;
    setState(() { _testing = true; _error = null; _ok = false; });
    try {
      // Mise à jour en mémoire uniquement — SharedPreferences écrit à la fin du wizard
      dio.options.baseUrl = url;
      final res = await dio.get('/api/setup/health');
      final data = res.data as Map<String, dynamic>;
      if (data['status'] == 'ok') {
        final c = ref.read(_configProvider);
        ref.read(_configProvider.notifier).state = c..serverUrl = url;
        setState(() => _ok = true);
      }
    } catch (e) {
      dio.options.baseUrl = previousUrl; // restaure sans toucher SharedPreferences
      final msg = e is DioException ? extractErrorMessage(e) : e.toString();
      setState(() => _error = 'Impossible de joindre le serveur: $msg');
    } finally {
      setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(_configProvider);
    final isClient = cfg.mode == InstallMode.client;

    return _PageShell(
      title: 'Adresse du serveur',
      subtitle: isClient
          ? 'Indiquez où se trouve le serveur POS Connect'
          : 'Adresse de ce serveur sur le réseau',
      onNext: _ok ? widget.onNext : null,
      onBack: widget.onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isClient) ...[
            // Mode serveur / both : afficher les IPs locales
            const Text(
              'Les postes clients devront utiliser cette adresse pour se connecter.',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            if (_localIps.isNotEmpty)
              ..._localIps.map((ip) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.lan_rounded, color: AppColors.primary, size: 18),
                    const SizedBox(width: 10),
                    Text('http://$ip:9003',
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
              )),
            const SizedBox(height: 16),
            const Text(
              'Testez la connexion pour confirmer que le serveur est accessible.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
          ] else ...[
            const Text(
              'Entrez l\'adresse IP du serveur POS Connect sur votre réseau local.',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            _Field(
              ctrl: _urlCtrl,
              label: 'URL du serveur',
              hint: 'http://192.168.1.100:9003',
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 16),
          ],
          FilledButton.icon(
            onPressed: _testing ? null : _test,
            icon: _testing
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.wifi_find_rounded, size: 16),
            label: Text(_testing ? 'Test en cours...' : 'Tester la connexion'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!,
                    style: const TextStyle(color: AppColors.error, fontSize: 12))),
              ]),
            ),
          ],
          if (_ok) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(children: [
                Icon(Icons.check_circle_outline, color: AppColors.success, size: 18),
                SizedBox(width: 8),
                Text('Connexion établie !',
                    style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Page 1 — Mode d'installation
// ═════════════════════════════════════════════════════════════════════════════

class _ModePage extends ConsumerWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;
  const _ModePage({required this.onNext, required this.onBack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(_configProvider);

    return _PageShell(
      title: 'Mode d\'installation',
      subtitle: 'Choisissez comment déployer POS Connect',
      onNext: onNext,
      onBack: onBack,
      child: Column(
        children: [
          _ModeCard(
            icon: Icons.dns_rounded,
            color: const Color(0xFF7C3AED),
            title: 'Serveur uniquement',
            desc: 'Installe uniquement le backend API et la base de données. '
                'Idéal pour un serveur dédié auquel plusieurs postes se connectent.',
            selected: cfg.mode == InstallMode.server,
            onTap: () => ref.read(_configProvider.notifier).state =
                InstallConfig()..mode = InstallMode.server,
          ),
          const SizedBox(height: 12),
          _ModeCard(
            icon: Icons.laptop_rounded,
            color: const Color(0xFF059669),
            title: 'Client uniquement',
            desc: 'Installe uniquement l\'interface POS. '
                'Le client se connecte à un serveur POS Connect existant sur le réseau.',
            selected: cfg.mode == InstallMode.client,
            onTap: () => ref.read(_configProvider.notifier).state =
                InstallConfig()..mode = InstallMode.client,
          ),
          const SizedBox(height: 12),
          _ModeCard(
            icon: Icons.devices_rounded,
            color: const Color(0xFF0284C7),
            title: 'Client + Serveur (recommandé pour poste unique)',
            desc: 'Installe les deux sur cette machine. '
                'Parfait pour un seul poste ou pour tester le système.',
            selected: cfg.mode == InstallMode.both,
            onTap: () => ref.read(_configProvider.notifier).state =
                InstallConfig()..mode = InstallMode.both,
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Page 2 — Choix base de données
// ═════════════════════════════════════════════════════════════════════════════

class _DbChoicePage extends ConsumerWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;
  const _DbChoicePage({required this.onNext, required this.onBack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(_configProvider);

    return _PageShell(
      title: 'Base de données',
      subtitle: 'Choisissez le moteur de base de données',
      onNext: onNext,
      onBack: onBack,
      child: Column(
        children: [
          // MySQL card
          _DbCard(
            title: 'MySQL',
            icon: Icons.storage_rounded,
            color: const Color(0xFF0284C7),
            selected: cfg.dbType == DbType.mysql,
            onTap: () {
              final c = ref.read(_configProvider);
              ref.read(_configProvider.notifier).state =
                  c..dbType = DbType.mysql;
            },
            pros: const [
              'Multi-postes : plusieurs clients simultanés',
              'Haute performance pour volumes importants',
              'Sauvegarde et réplication avancées',
              'Standard industrie',
            ],
            cons: const [
              'Nécessite une installation séparée de MySQL',
              'Configuration plus complexe',
            ],
          ),
          const SizedBox(height: 16),
          // SQLite card
          _DbCard(
            title: 'SQLite',
            icon: Icons.folder_rounded,
            color: const Color(0xFF059669),
            selected: cfg.dbType == DbType.sqlite,
            onTap: () {
              final c = ref.read(_configProvider);
              ref.read(_configProvider.notifier).state =
                  c..dbType = DbType.sqlite;
            },
            pros: const [
              'Zéro configuration — prêt immédiatement',
              'La base = un seul fichier (backup simple)',
              'Aucune dépendance externe',
            ],
            cons: const [
              '⚠️  UN SEUL POSTE : pas d\'accès multi-clients réseau',
              'Performances limitées pour de gros volumes',
              'Migration vers MySQL possible mais manuelle',
            ],
            warning: cfg.dbType == DbType.sqlite
                ? '⚠️  Avec SQLite, le serveur ne peut être utilisé que depuis '
                    'ce poste. Si vous avez besoin d\'accès multi-postes, '
                    'choisissez MySQL.'
                : null,
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Page 3a — Configuration MySQL
// ═════════════════════════════════════════════════════════════════════════════

class _MysqlSetupPage extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;
  const _MysqlSetupPage({required this.onNext, required this.onBack});

  @override
  ConsumerState<_MysqlSetupPage> createState() => _MysqlSetupPageState();
}

class _MysqlSetupPageState extends ConsumerState<_MysqlSetupPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _host, _port, _name, _user, _pass;
  String? _error;
  bool _isAccessDenied = false;
  bool _fixingSocket = false;
  String? _mysqlInstructions;
  bool _testing = false;
  bool _tested = false;
  bool _installingMysql = false;
  String _installProgress = '';

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(_configProvider);
    _host = TextEditingController(text: cfg.dbHost);
    _port = TextEditingController(text: '${cfg.dbPort}');
    _name = TextEditingController(text: cfg.dbName);
    _user = TextEditingController(text: cfg.dbUser);
    _pass = TextEditingController(text: cfg.dbPassword);
    _detectMysql();
  }

  Future<void> _detectMysql() async {
    try {
      final res = await dio.get('/api/setup/detect-mysql');
      final data = res.data as Map<String, dynamic>;
      if (data['installed'] == false) {
        setState(() => _mysqlInstructions = data['instructions'] as String);
      } else {
        setState(() { _mysqlInstructions = null; _tested = false; });
      }
    } catch (_) {}
  }

  /// Lance l'installation automatique de MySQL via le PS1 (Windows uniquement)
  /// et poll le statut toutes les 3s sans relancer le wizard.
  Future<void> _autoInstallMysql() async {
    setState(() {
      _installingMysql = true;
      _installProgress = 'Démarrage de l\'installation MySQL...';
    });
    try {
      await dio.post('/api/setup/install-mysql');
    } catch (_) {}

    // Polling jusqu'à done ou error (max 10 min)
    for (int i = 0; i < 200; i++) {
      await Future.delayed(const Duration(seconds: 3));
      try {
        final res = await dio.get('/api/setup/install-mysql/status');
        final data = res.data as Map<String, dynamic>;
        final status = data['status'] as String? ?? 'running';

        if (!mounted) return;
        setState(() {
          _installProgress = switch (status) {
            'running' => i < 10
                ? 'Vérification des prérequis (Visual C++)...'
                : i < 30
                    ? 'Téléchargement / extraction MySQL...'
                    : i < 60
                        ? 'Initialisation de la base de données...'
                        : 'Configuration des services Windows...',
            'done'    => 'MySQL installé avec succès !',
            'error'   => 'Erreur lors de l\'installation.',
            _         => 'Installation en cours...',
          };
        });

        if (status == 'done') {
          if (!mounted) return;
          setState(() {
            _installingMysql = false;
            _mysqlInstructions = null;
          });
          await _detectMysql();
          return;
        }
        if (status == 'error') {
          setState(() {
            _installingMysql = false;
            _mysqlInstructions = 'Installation automatique échouée.\n'
                'Vérifiez C:\\ProgramData\\POS_Connect\\install.log\n\n'
                'Ou installez MySQL manuellement et relancez.';
          });
          return;
        }
      } catch (_) {}
    }
    if (mounted) setState(() { _installingMysql = false; });
  }

  Future<void> _autoFixWithSudo() async {
    final sudoPass = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Mot de passe système'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Entrez le mot de passe sudo de cet utilisateur '
                'pour configurer MySQL automatiquement.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Mot de passe sudo',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                onSubmitted: (_) => Navigator.pop(ctx, ctrl.text),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text),
                child: const Text('Corriger')),
          ],
        );
      },
    );
    if (sudoPass == null || sudoPass.isEmpty) return;

    setState(() { _fixingSocket = true; _error = null; });
    try {
      final dbUser = _user.text.trim();
      final dbPass = _pass.text;
      final sql =
          "ALTER USER '$dbUser'@'localhost' "
          "IDENTIFIED WITH mysql_native_password BY '$dbPass'; "
          "FLUSH PRIVILEGES;";
      final process = await Process.start(
        'sudo', ['-S', 'mysql', '-u', dbUser, '-e', sql],
      );
      process.stdin.writeln(sudoPass);
      await process.stdin.close();
      final exitCode = await process.exitCode;
      final stderr = await process.stderr.transform(utf8.decoder).join();
      if (exitCode == 0) {
        setState(() { _error = null; _isAccessDenied = false; });
        await _test();
      } else {
        setState(() => _error = stderr.isNotEmpty ? stderr : 'Échec — vérifiez votre mot de passe sudo.');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _fixingSocket = false);
    }
  }

  Future<void> _test() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _testing = true; _error = null; _isAccessDenied = false; });
    try {
      await dio.post('/api/setup/test-db', data: {
        'db_type': 'mysql',
        'host': _host.text.trim(),
        'port': int.parse(_port.text),
        'name': _name.text.trim(),
        'user': _user.text.trim(),
        'password': _pass.text,
      });
      final c = ref.read(_configProvider);
      ref.read(_configProvider.notifier).state = c
        ..dbHost = _host.text.trim()
        ..dbPort = int.parse(_port.text)
        ..dbName = _name.text.trim()
        ..dbUser = _user.text.trim()
        ..dbPassword = _pass.text;
      setState(() { _tested = true; });
    } catch (e) {
      final msg = e is DioException ? extractErrorMessage(e) : e.toString();
      final accessDenied = msg.contains('1045') || msg.toLowerCase().contains('access denied');
      final unknownDb = msg.contains('1049') || msg.toLowerCase().contains('unknown database');
      final display = unknownDb
          ? 'Base de données introuvable. Elle sera créée automatiquement à l\'étape suivante.'
          : msg;
      setState(() { _error = display; _isAccessDenied = accessDenied; });
    } finally {
      setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      title: 'Configuration MySQL',
      subtitle: 'Renseignez les informations de connexion',
      onNext: _tested ? widget.onNext : null,
      onBack: widget.onBack,
      nextLabel: 'Suivant',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_installingMysql) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    Icon(Icons.downloading_rounded, color: AppColors.primary, size: 18),
                    SizedBox(width: 8),
                    Text('Installation MySQL en cours...',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  ]),
                  const SizedBox(height: 10),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(_installProgress,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ]),
              ),
              const SizedBox(height: 16),
            ] else if (_mysqlInstructions != null) ...[
              _InfoCard(
                icon: Icons.warning_amber_rounded,
                color: AppColors.warning,
                title: 'MySQL non détecté sur ce système',
                body: _mysqlInstructions!,
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _autoInstallMysql,
                    icon: const Icon(Icons.install_desktop_rounded, size: 18),
                    label: const Text('Installer automatiquement'),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _detectMysql,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Vérifier'),
                ),
              ]),
              const SizedBox(height: 16),
            ],
            Row(children: [
              Expanded(
                flex: 3,
                child: _Field(ctrl: _host, label: 'Hôte',
                    hint: 'localhost',
                    validator: (v) => v!.isEmpty ? 'Requis' : null),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Field(ctrl: _port, label: 'Port',
                    hint: '3306', keyboardType: TextInputType.number,
                    validator: (v) =>
                        int.tryParse(v ?? '') == null ? 'Invalide' : null),
              ),
            ]),
            const SizedBox(height: 12),
            _Field(ctrl: _name, label: 'Nom de la base de données',
                hint: 'pos_db',
                validator: (v) => v!.isEmpty ? 'Requis' : null),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: _Field(ctrl: _user, label: 'Utilisateur',
                    hint: 'root',
                    validator: (v) => v!.isEmpty ? 'Requis' : null),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Field(ctrl: _pass, label: 'Mot de passe',
                    obscure: true),
              ),
            ]),
            const SizedBox(height: 20),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!,
                      style: const TextStyle(color: AppColors.error, fontSize: 12))),
                ]),
              ),
              if (_isAccessDenied) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                  ),
                  child: Platform.isWindows
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(children: [
                              Icon(Icons.lightbulb_outline, color: AppColors.warning, size: 16),
                              SizedBox(width: 6),
                              Text('Windows — créer l\'utilisateur MySQL',
                                  style: TextStyle(
                                      color: AppColors.warning,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13)),
                            ]),
                            const SizedBox(height: 8),
                            const Text(
                              'L\'utilisateur MySQL n\'existe pas encore ou n\'a pas accès depuis 127.0.0.1.\n'
                              'Cliquez sur le bouton ci-dessous pour le créer automatiquement via root.',
                              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E2A38),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'mysql -u root -P ${_port.text} -e "\n'
                                "CREATE USER IF NOT EXISTS '${_user.text}'@'127.0.0.1'\n"
                                "  IDENTIFIED BY '${_pass.text.replaceAll("'", "\\'")}'; \n"
                                "GRANT ALL ON ${_name.text}.* TO '${_user.text}'@'127.0.0.1';\n"
                                'FLUSH PRIVILEGES;"',
                                style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    color: Color(0xFF7DD3FC)),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.warning),
                                onPressed: _fixingSocket ? null : _test,
                                icon: _fixingSocket
                                    ? const SizedBox(width: 16, height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.auto_fix_high_rounded, size: 16),
                                label: const Text('Créer automatiquement'),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(children: [
                              Icon(Icons.lightbulb_outline, color: AppColors.warning, size: 16),
                              SizedBox(width: 6),
                              Text('Debian / Ubuntu — auth_socket',
                                  style: TextStyle(
                                      color: AppColors.warning,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13)),
                            ]),
                            const SizedBox(height: 8),
                            const Text(
                              'MySQL utilise "auth_socket" par défaut (pas de mot de passe).\n'
                              'Exécutez ces commandes sur le serveur puis réessayez :',
                              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E2A38),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'sudo mysql -u root\n'
                                "ALTER USER 'root'@'localhost' IDENTIFIED BY '${_pass.text}';\n"
                                'FLUSH PRIVILEGES;\n'
                                'exit',
                                style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    color: Color(0xFF7DD3FC)),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.warning),
                                onPressed: _fixingSocket ? null : _autoFixWithSudo,
                                icon: _fixingSocket
                                    ? const SizedBox(width: 16, height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.build_rounded, size: 16),
                                label: Text(_fixingSocket
                                    ? 'Configuration en cours...'
                                    : 'Corriger automatiquement (sudo)'),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ],
            if (_tested)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(children: [
                  Icon(Icons.check_circle_outline, color: AppColors.success,
                      size: 18),
                  SizedBox(width: 8),
                  Text('Connexion réussie !',
                      style: TextStyle(
                          color: AppColors.success, fontWeight: FontWeight.w600)),
                ]),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _testing ? null : _test,
              icon: _testing
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.cable_rounded, size: 16),
              label: Text(_testing ? 'Test en cours...' : 'Tester la connexion'),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Page 3b — Info SQLite
// ═════════════════════════════════════════════════════════════════════════════

class _SqliteInfoPage extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;
  const _SqliteInfoPage({required this.onNext, required this.onBack});

  @override
  ConsumerState<_SqliteInfoPage> createState() => _SqliteInfoPageState();
}

class _SqliteInfoPageState extends ConsumerState<_SqliteInfoPage> {
  late TextEditingController _pathCtrl;

  @override
  void initState() {
    super.initState();
    _pathCtrl = TextEditingController(
        text: ref.read(_configProvider).dbPath);
  }

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      title: 'Configuration SQLite',
      subtitle: 'Fichier de base de données local',
      onNext: () {
        final c = ref.read(_configProvider);
        ref.read(_configProvider.notifier).state =
            c..dbPath = _pathCtrl.text.trim().isEmpty
                ? './pos_data.db'
                : _pathCtrl.text.trim();
        widget.onNext();
      },
      onBack: widget.onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoCard(
            icon: Icons.warning_amber_rounded,
            color: AppColors.warning,
            title: 'Important — Limitations SQLite',
            items: const [
              '⚠️  Un seul poste à la fois : plusieurs clients réseau '
                  'simultanés peuvent causer des erreurs.',
              '⚠️  Si vous avez plusieurs caisses, utilisez MySQL.',
              '✅  Parfait pour tester ou un seul poste autonome.',
              '✅  Vous pouvez migrer vers MySQL plus tard depuis la console serveur.',
            ],
          ),
          const SizedBox(height: 20),
          _Field(
            ctrl: _pathCtrl,
            label: 'Emplacement du fichier SQLite',
            hint: './pos_data.db',
          ),
          const SizedBox(height: 8),
          const Text(
            'Laissez le chemin par défaut sauf si vous savez ce que vous faites.',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Page 4 — Connexion compte cloud
// ═════════════════════════════════════════════════════════════════════════════

// ═════════════════════════════════════════════════════════════════════════════
// Page 3 (client mode) — Connexion locale
// ═════════════════════════════════════════════════════════════════════════════

class _LocalLoginPage extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;
  const _LocalLoginPage({required this.onNext, required this.onBack});

  @override
  ConsumerState<_LocalLoginPage> createState() => _LocalLoginPageState();
}

class _LocalLoginPageState extends ConsumerState<_LocalLoginPage> {
  late TextEditingController _userCtrl;
  late TextEditingController _pwdCtrl;
  bool _obscure = true;
  bool _loading = false;
  bool _loggedIn = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _userCtrl = TextEditingController();
    _pwdCtrl  = TextEditingController();
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final username = _userCtrl.text.trim();
    final password = _pwdCtrl.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Remplissez les deux champs.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final res = await dio.post(
        '/api/auth/login',
        data: 'username=$username&password=$password',
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );
      final token = res.data['access_token'] as String?;
      if (token == null) throw Exception('Token absent de la réponse');

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.tokenKey, token);
      dio.options.headers['Authorization'] = 'Bearer $token';

      setState(() => _loggedIn = true);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final msg = code == 401 || code == 403
          ? 'Identifiants incorrects'
          : e.response?.data?['detail']?.toString() ?? 'Erreur de connexion';
      setState(() => _error = msg);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final serverUrl = ref.watch(_configProvider).serverUrl;
    return _PageShell(
      title: 'Connexion au serveur',
      subtitle: 'Entrez vos identifiants POS Connect',
      onNext: _loggedIn ? widget.onNext : null,
      onBack: widget.onBack,
      nextLabel: 'Continuer',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
            ),
            child: Row(children: [
              const Icon(Icons.dns_rounded, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  serverUrl.isNotEmpty ? serverUrl : dio.options.baseUrl,
                  style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 13,
                    color: AppColors.primary, fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          _Field(
            ctrl: _userCtrl,
            label: "Nom d'utilisateur",
            hint: 'admin',
            validator: (v) => v!.isEmpty ? 'Requis' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _pwdCtrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Mot de passe',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(_obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onFieldSubmitted: (_) { if (!_loading) _login(); },
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _loading ? null : _login,
            icon: _loading
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.login_rounded, size: 16),
            label: Text(_loading ? 'Connexion...' : 'Se connecter'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!,
                    style: const TextStyle(color: AppColors.error, fontSize: 12))),
              ]),
            ),
          ],
          if (_loggedIn) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(children: [
                Icon(Icons.check_circle_outline, color: AppColors.success, size: 18),
                SizedBox(width: 8),
                Text('Connecté avec succès !',
                    style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

class _TenantConnectPage extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;
  const _TenantConnectPage({required this.onNext, required this.onBack});

  @override
  ConsumerState<_TenantConnectPage> createState() => _TenantConnectPageState();
}

class _TenantConnectPageState extends ConsumerState<_TenantConnectPage> {
  late TextEditingController _customUrl, _email, _pwd;
  bool _usePosConnectCloud = true;
  bool _obscure = true;
  bool _testing = false;
  bool _verified = false;
  String? _error;
  List<Map<String, dynamic>> _warehouses = [];
  String? _selectedWarehouseId;

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(_configProvider);
    final saved = cfg.cloudUrl;
    if (saved.isNotEmpty && saved != AppConstants.cloudUrl) {
      _usePosConnectCloud = false;
      _customUrl = TextEditingController(text: saved);
    } else {
      _usePosConnectCloud = true;
      // Pre-fill with the cloud URL so it's editable if the user needs to override it
      _customUrl = TextEditingController(text: AppConstants.cloudUrl);
    }
    _email = TextEditingController(text: cfg.tenantEmail);
    _pwd   = TextEditingController(text: cfg.tenantPassword);
  }

  @override
  void dispose() {
    _customUrl.dispose();
    _email.dispose();
    _pwd.dispose();
    super.dispose();
  }

  String get _effectiveUrl => _customUrl.text.trim().replaceAll(RegExp(r'/+$'), '');

  Future<void> _verify() async {
    final url   = _effectiveUrl;
    final email = _email.text.trim();
    final pwd   = _pwd.text;
    if (url.isEmpty || email.isEmpty || pwd.isEmpty) return;

    setState(() { _testing = true; _error = null; _verified = false; });

    final cloudDio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));

    try {
      // ── Step 1 : verify server identity (Ed25519) ────────────────────
      final nonce = _randomNonce();
      final idRes = await cloudDio.get(
        '$url/api/public/identity',
        queryParameters: {'nonce': nonce},
      );
      final sigB64 = idRes.data['signature'] as String?;
      if (sigB64 == null || idRes.data['app'] != 'pos-connect-saas') {
        setState(() => _error = 'Ce serveur n\'est pas un serveur POS Connect.');
        return;
      }

      final valid = await _verifySignature(nonce, sigB64);
      if (!valid) {
        setState(() => _error =
            'Signature invalide — ce serveur n\'est pas un serveur POS Connect authentique.');
        return;
      }

      // ── Step 2 : validate tenant credentials ─────────────────────────
      final tokenRes = await cloudDio.post(
        '$url/api/sync/token',
        data: {'owner_email': email, 'password': pwd},
      );
      final tokenBody = tokenRes.data as Map<String, dynamic>;

      // Parse warehouse list returned by the cloud
      final rawWarehouses = tokenBody['warehouses'] as List<dynamic>? ?? [];
      final warehouses = rawWarehouses
          .cast<Map<String, dynamic>>()
          .toList();

      // Auto-select if only one warehouse; require selection if multiple
      String? autoSelectedId;
      String autoSelectedName = '';
      if (warehouses.length == 1) {
        autoSelectedId   = warehouses.first['id'] as String?;
        autoSelectedName = warehouses.first['name'] as String? ?? '';
      } else if (warehouses.isEmpty) {
        // No warehouses on cloud yet — will be created/synced by server
        autoSelectedId   = null;
        autoSelectedName = '';
      }

      final c = ref.read(_configProvider);
      ref.read(_configProvider.notifier).state = c
        ..cloudUrl              = url
        ..tenantEmail           = email
        ..tenantPassword        = pwd
        ..selectedWarehouseId   = autoSelectedId ?? ''
        ..selectedWarehouseName = autoSelectedName;
      setState(() {
        _verified             = true;
        _warehouses           = warehouses;
        _selectedWarehouseId  = autoSelectedId;
      });

    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final msg  = code == 403 || code == 401
          ? 'Identifiants incorrects ou compte inactif'
          : e.response?.data?['detail']?.toString() ??
            'Impossible de joindre le serveur ($url)';
      setState(() => _error = msg);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _testing = false);
    }
  }

  void _switchMode(bool usePosConnect) {
    setState(() {
      _usePosConnectCloud = usePosConnect;
      if (usePosConnect) {
        _customUrl.text = AppConstants.cloudUrl;
      } else {
        _customUrl.text = '';
      }
      _verified            = false;
      _error               = null;
      _warehouses          = [];
      _selectedWarehouseId = null;
    });
  }

  String _randomNonce() {
    final rng = Random.secure();
    final bytes = List<int>.generate(12, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<bool> _verifySignature(String nonce, String signatureB64) async {
    try {
      final pubKeyBytes = base64.decode(AppConstants.identityPublicKeyB64);
      final sigBytes    = base64.decode(signatureB64);
      final message     = utf8.encode('pos-connect-saas:$nonce');

      final algorithm = Ed25519();
      final publicKey = SimplePublicKey(pubKeyBytes, type: KeyPairType.ed25519);
      return await algorithm.verify(
        message,
        signature: Signature(sigBytes, publicKey: publicKey),
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // "Suivant" nécessite : vérifié + dépôt choisi (ou pas de dépôts sur le cloud)
    final canProceed = _verified &&
        (_warehouses.isEmpty || _selectedWarehouseId != null);

    return _PageShell(
      title: 'Connexion au compte cloud',
      subtitle: 'Liez cette installation à votre compte POS Connect',
      onNext: canProceed ? widget.onNext : null,
      onBack: widget.onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Mode selector ─────────────────────────────────────────────
          _CloudModeCard(
            icon: Icons.cloud_rounded,
            color: AppColors.primary,
            title: 'Cloud POS Connect',
            badge: 'Recommandé',
            desc: 'Utilisez notre infrastructure cloud. Synchronisation, licences '
                'et sauvegardes gérés automatiquement.',
            selected: _usePosConnectCloud,
            onTap: () => _switchMode(true),
          ),
          const SizedBox(height: 10),
          _CloudModeCard(
            icon: Icons.dns_rounded,
            color: const Color(0xFF7C3AED),
            title: 'Mon propre serveur',
            desc: 'Vous hébergez votre propre instance POS Connect cloud. '
                'Renseignez son adresse.',
            selected: !_usePosConnectCloud,
            onTap: () => _switchMode(false),
          ),
          const SizedBox(height: 24),

          // ── URL row ───────────────────────────────────────────────────
          if (_usePosConnectCloud && _error == null) ...[
            // Auto-filled — non-editable until a connection error unlocks it
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
              ),
              child: Row(children: [
                const Icon(Icons.cloud_done_rounded, size: 16, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _customUrl.text,
                    style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 13,
                      color: AppColors.primary, fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(Icons.lock_outline_rounded, size: 14, color: AppColors.textSecondary),
              ]),
            ),
          ] else ...[
            _Field(
              ctrl: _customUrl,
              label: _usePosConnectCloud
                  ? 'URL du serveur POS Connect'
                  : 'URL du serveur cloud',
              hint: 'https://posconnect.ht',
              keyboardType: TextInputType.url,
            ),
            if (_usePosConnectCloud) ...[
              const SizedBox(height: 4),
              const Text(
                'URL déverrouillée après échec de connexion — corrigez si le domaine a changé.',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ],
          const SizedBox(height: 14),

          // ── Credentials ───────────────────────────────────────────────
          _Field(
            ctrl: _email,
            label: 'Email du compte',
            hint: 'votre@email.com',
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _pwd,
            obscureText: _obscure,
            onFieldSubmitted: (_) { if (!_testing) _verify(); },
            decoration: InputDecoration(
              labelText: 'Mot de passe',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(_obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Verify button ─────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _testing ? null : _verify,
              icon: _testing
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.verified_user_outlined, size: 16),
              label: Text(_testing ? 'Vérification...' : 'Vérifier la connexion'),
            ),
          ),

          // ── Feedback ──────────────────────────────────────────────────
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!,
                    style: const TextStyle(color: AppColors.error, fontSize: 12))),
              ]),
            ),
          ],
          if (_verified) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle_outline, color: AppColors.success, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Compte vérifié — ${_email.text}',
                    style: const TextStyle(
                        color: AppColors.success, fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            // ── Sélection du dépôt ───────────────────────────────────────
            _WarehousePickerSection(
              warehouses:           _warehouses,
              selectedWarehouseId:  _selectedWarehouseId,
              onSelected: (id, name) {
                final c = ref.read(_configProvider);
                ref.read(_configProvider.notifier).state = c
                  ..selectedWarehouseId   = id
                  ..selectedWarehouseName = name;
                setState(() => _selectedWarehouseId = id);
              },
            ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Page 5 — Installation
// ═════════════════════════════════════════════════════════════════════════════

class _InstallationPage extends ConsumerStatefulWidget {
  final VoidCallback onDone;
  final VoidCallback onBack;
  final bool needsServer;
  const _InstallationPage(
      {required this.onDone, required this.onBack, required this.needsServer});

  @override
  ConsumerState<_InstallationPage> createState() => _InstallationPageState();
}

class _InstallationPageState extends ConsumerState<_InstallationPage> {
  final List<_InstallStep> _steps = [];
  bool _running = false;
  bool _done = false;
  bool _failed = false;
  String? _failMsg;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    setState(() => _running = true);
    final cfg = ref.read(_configProvider);

    if (widget.needsServer) {
      await _step('Création de la base de données', () async {
        await dio.post('/api/setup/create-db', data: {
          'db_type': cfg.dbType == DbType.mysql ? 'mysql' : 'sqlite',
          'host': cfg.dbHost,
          'port': cfg.dbPort,
          'name': cfg.dbName,
          'user': cfg.dbUser,
          'password': cfg.dbPassword,
          'path': cfg.dbPath,
        });
      });
      if (_failed) return;

      await _step('Liaison au compte cloud', () async {
        final body = <String, dynamic>{
          'cloud_url':   cfg.cloudUrl,
          'email':       cfg.tenantEmail,
          'password':    cfg.tenantPassword,
          'db_type':     cfg.dbType == DbType.mysql ? 'mysql' : 'sqlite',
          'host':        cfg.dbHost,
          'port':        cfg.dbPort,
          'name':        cfg.dbName,
          'user':        cfg.dbUser,
          'db_password': cfg.dbPassword,
          'path':        cfg.dbPath,
          'server_host': cfg.serverHost,
          'server_port': cfg.serverPort,
        };
        if (cfg.selectedWarehouseId.isNotEmpty) {
          body['warehouse_id']   = cfg.selectedWarehouseId;
          body['warehouse_name'] = cfg.selectedWarehouseName;
        }
        await dio.post('/api/setup/connect-tenant', data: body);
      });
      if (_failed) return;

      await _step('Installation du service système', () async {
        final wrapperName = Platform.isWindows ? 'service_wrapper.exe' : './service_wrapper';
        final wrapperFile = File(wrapperName.replaceFirst('./', ''));
        // Skip silently if service_wrapper is absent (remote-only client)
        if (!wrapperFile.existsSync()) return;
        final result = await Process.run(wrapperName, ['install']);
        if (result.exitCode != 0) {
          throw Exception(result.stderr.toString());
        }
      });
    }

    if (!_failed) {
      // Persiste l'URL du serveur dans SharedPreferences une seule fois, à la fin
      await saveServerUrl(cfg.serverUrl.isNotEmpty ? cfg.serverUrl : dio.options.baseUrl);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppConstants.clientSetupDoneKey, true);
      setState(() { _done = true; _running = false; });
      await Future.delayed(const Duration(milliseconds: 500));
      widget.onDone();
    }
  }

  Future<void> _step(String label, Future<void> Function() fn) async {
    final step = _InstallStep(label: label);
    setState(() => _steps.add(step));
    try {
      await fn();
      setState(() => step.done = true);
    } catch (e) {
      setState(() {
        step.failed = true;
        _failed = true;
        _failMsg = e.toString();
        _running = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      title: 'Installation en cours',
      subtitle: _done
          ? 'Installation terminée avec succès !'
          : _failed
              ? 'Une erreur est survenue'
              : 'Veuillez patienter...',
      onNext: null,
      showBack: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._steps.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: s.done
                        ? const Icon(Icons.check_circle_rounded,
                            color: AppColors.success)
                        : s.failed
                            ? const Icon(Icons.error_rounded,
                                color: AppColors.error)
                            : const CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(s.label,
                      style: TextStyle(
                          fontSize: 14,
                          color: s.failed
                              ? AppColors.error
                              : AppColors.textPrimary,
                          fontWeight: s.done || s.failed
                              ? FontWeight.w600
                              : FontWeight.w400)),
                ]),
              )),
          if (_failMsg != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_failMsg!,
                  style: const TextStyle(
                      color: AppColors.error, fontSize: 12)),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _running ? null : () {
                setState(() {
                  _steps.clear();
                  _failed = false;
                  _failMsg = null;
                });
                _run();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
            ),
          ],
        ],
      ),
    );
  }
}

class _InstallStep {
  final String label;
  bool done = false;
  bool failed = false;
  _InstallStep({required this.label});
}

// ═════════════════════════════════════════════════════════════════════════════
// Page 6 — Terminé
// ═════════════════════════════════════════════════════════════════════════════

class _DonePage extends ConsumerWidget {
  const _DonePage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(_configProvider);
    final needsServer =
        cfg.mode == InstallMode.server || cfg.mode == InstallMode.both;

    return _PageShell(
      title: 'Installation terminée !',
      subtitle: 'POS Connect est prêt à l\'emploi',
      showBack: false,
      onNext: null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: AppColors.success, size: 40),
            ),
          ),
          const SizedBox(height: 24),
          if (needsServer) ...[
            _SummaryRow(
                icon: Icons.cloud_done_rounded,
                label: 'Compte cloud',
                value: cfg.tenantEmail),
            _SummaryRow(
                icon: Icons.storage_rounded,
                label: 'Base de données',
                value: cfg.dbType == DbType.mysql
                    ? 'MySQL (${cfg.dbHost}:${cfg.dbPort}/${cfg.dbName})'
                    : 'SQLite (${cfg.dbPath})'),
            _SummaryRow(
                icon: Icons.dns_rounded,
                label: 'Serveur API',
                value: 'http://${cfg.serverHost}:${cfg.serverPort}'),
            if (cfg.selectedWarehouseName.isNotEmpty)
              _SummaryRow(
                  icon: Icons.warehouse_rounded,
                  label: 'Dépôt',
                  value: cfg.selectedWarehouseName),
          ],
          const SizedBox(height: 20),
          if (needsServer)
            const _InfoCard(
              icon: Icons.sync_rounded,
              color: AppColors.primary,
              title: 'Synchronisation active',
              body:
                  'Ce serveur est lié à votre compte cloud. Vos données '
                  'se synchronisent automatiquement. Connectez-vous avec '
                  'vos identifiants cloud pour accéder à POS Connect.',
            ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () => context.go('/login'),
              icon: const Icon(Icons.launch_rounded),
              label: Text(cfg.mode == InstallMode.server
                  ? 'Fermer l\'installateur'
                  : 'Lancer POS Connect'),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Warehouse picker — affiché après vérification du tenant
// ═════════════════════════════════════════════════════════════════════════════

class _WarehousePickerSection extends StatelessWidget {
  final List<Map<String, dynamic>> warehouses;
  final String? selectedWarehouseId;
  final void Function(String id, String name) onSelected;

  const _WarehousePickerSection({
    required this.warehouses,
    required this.selectedWarehouseId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (warehouses.isEmpty) {
      // Pas encore de dépôts sur le cloud — le serveur local en créera un au démarrage
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        ),
        child: const Row(children: [
          Icon(Icons.warehouse_rounded, color: AppColors.primary, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Dépôt principal sera créé automatiquement sur ce serveur.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
        ]),
      );
    }

    if (warehouses.length == 1) {
      // Un seul dépôt — sélection automatique, juste l'afficher
      final name = warehouses.first['name'] as String? ?? '';
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.warehouse_rounded, color: AppColors.success, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Dépôt assigné à ce poste',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              Text(name,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: AppColors.success)),
            ]),
          ),
          const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
        ]),
      );
    }

    // Plusieurs dépôts — sélection obligatoire
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.warehouse_rounded, color: AppColors.primary, size: 16),
          const SizedBox(width: 8),
          const Text('Dépôt de ce poste',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('Obligatoire',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    color: AppColors.error)),
          ),
        ]),
        const SizedBox(height: 6),
        const Text(
          'Chaque poste est exclusivement lié à un dépôt. '
          'Ce choix ne pourra pas être modifié après installation.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        ...warehouses.map((wh) {
          final id       = wh['id'] as String? ?? '';
          final name     = wh['name'] as String? ?? '';
          final isDefault = wh['is_default'] as bool? ?? false;
          final selected = id == selectedWarehouseId;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () => onSelected(id, name),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary.withValues(alpha: 0.06)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.divider,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Row(children: [
                  Icon(Icons.warehouse_rounded,
                      color: selected ? AppColors.primary : AppColors.textSecondary,
                      size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(children: [
                      Text(name,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: selected ? AppColors.primary : AppColors.textPrimary)),
                      if (isDefault) ...[
                        const SizedBox(width: 8),
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
                  Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: selected ? AppColors.primary : AppColors.textSecondary,
                    size: 20,
                  ),
                ]),
              ),
            ),
          );
        }),
        if (selectedWarehouseId == null)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Sélectionnez un dépôt pour continuer.',
                style: TextStyle(fontSize: 11, color: AppColors.error)),
          ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Shared widgets
// ═════════════════════════════════════════════════════════════════════════════

class _PageShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final VoidCallback? onNext;
  final VoidCallback? onBack;
  final bool showBack;
  final String nextLabel;

  const _PageShell({
    required this.title,
    required this.subtitle,
    required this.child,
    this.onNext,
    this.onBack,
    this.showBack = true,
    this.nextLabel = 'Suivant',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Container(
          width: double.infinity,
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(subtitle,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textSecondary)),
          ]),
        ),
        const Divider(height: 1),
        // Content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: child,
          ),
        ),
        // Footer
        const Divider(height: 1),
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          child: Row(
            children: [
              if (showBack && onBack != null)
                OutlinedButton.icon(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: const Text('Retour'),
                ),
              const Spacer(),
              if (onNext != null)
                FilledButton.icon(
                  onPressed: onNext,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: Text(nextLabel),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CloudModeCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? badge;
  final String desc;
  final bool selected;
  final VoidCallback onTap;

  const _CloudModeCard({
    required this.icon,
    required this.color,
    required this.title,
    this.badge,
    required this.desc,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.06) : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : AppColors.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: selected ? color : AppColors.textPrimary)),
                  if (badge != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(badge!,
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: color)),
                    ),
                  ],
                ]),
                const SizedBox(height: 3),
                Text(desc,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            selected
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_off_rounded,
            color: selected ? color : AppColors.textSecondary,
            size: 20,
          ),
        ]),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String desc;
  final bool selected;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.desc,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.06)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? color : AppColors.divider,
              width: selected ? 2 : 1),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: selected ? color : AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text(desc,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          )),
          if (selected)
            Icon(Icons.radio_button_checked_rounded, color: color),
        ]),
      ),
    );
  }
}

class _DbCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final List<String> pros;
  final List<String> cons;
  final String? warning;

  const _DbCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
    required this.pros,
    required this.cons,
    this.warning,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.05)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? color : AppColors.divider,
              width: selected ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: selected ? color : AppColors.textPrimary)),
              const Spacer(),
              if (selected)
                Icon(Icons.check_circle_rounded, color: color, size: 20),
            ]),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('✅ Avantages',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 12)),
                  const SizedBox(height: 4),
                  ...pros.map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text('• $p',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                  )),
                ],
              )),
              const SizedBox(width: 16),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('❌ Inconvénients',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 12)),
                  const SizedBox(height: 4),
                  ...cons.map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text('• $c',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                  )),
                ],
              )),
            ]),
            if (warning != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(warning!,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.warning,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final List<String>? items;
  final String? body;

  const _InfoCard({
    required this.icon,
    required this.color,
    required this.title,
    this.items,
    this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 8),
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13, color: color)),
          ]),
          const SizedBox(height: 8),
          if (body != null)
            Text(body!,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          if (items != null)
            ...items!.map((item) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('• $item',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                )),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final bool obscure;
  final String? Function(String?)? validator;

  const _Field({
    required this.ctrl,
    required this.label,
    this.hint,
    this.keyboardType,
    this.obscure = false,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(labelText: label, hintText: hint),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _SummaryRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 8),
        Text('$label : ',
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13)),
        Text(value,
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSecondary)),
      ]),
    );
  }
}
