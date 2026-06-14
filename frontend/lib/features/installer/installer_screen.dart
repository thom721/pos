import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/core/constants.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart';

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
  // Admin account
  String adminFname;
  String adminLname;
  String adminUsername;
  String adminEmail;
  String adminPhone;
  String adminPassword;
  String serverUrl;

  InstallConfig({
    this.serverUrl = '',
    this.mode = InstallMode.both,
    this.dbType = DbType.mysql,
    this.dbHost = 'localhost',
    this.dbPort = 3306,
    this.dbName = 'pos_db',
    this.dbUser = 'root',
    this.dbPassword = '',
    this.dbPath = './pos_data.db',
    this.serverHost = '0.0.0.0',
    this.serverPort = 8002,
    this.adminFname = '',
    this.adminLname = '',
    this.adminUsername = '',
    this.adminEmail = '',
    this.adminPhone = '',
    this.adminPassword = '',
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

  final List<String> _steps = [
    'Bienvenue',
    'Mode',
    'Adresse serveur',
    'Base de données',
    'Connexion DB',
    'Compte admin',
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
          // client-only : sauter DB + admin
          WidgetsBinding.instance.addPostFrameCallback((_) => _goTo(6));
          return const SizedBox.shrink();
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
        return _AdminAccountPage(onNext: _next, onBack: _back);
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
    _urlCtrl = TextEditingController(
      text: cfg.serverUrl.isNotEmpty ? cfg.serverUrl : AppConstants.baseUrl,
    );
    _detectLocalIps();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _detectLocalIps() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      final ips = interfaces
          .expand((i) => i.addresses)
          .map((a) => a.address)
          .where((ip) => !ip.startsWith('127.'))
          .toList();
      if (mounted) setState(() => _localIps = ips);
    } catch (_) {}
  }

  Future<void> _test() async {
    final url = _urlCtrl.text.trim().replaceAll(RegExp(r'/+$'), '');
    if (url.isEmpty) return;
    setState(() { _testing = true; _error = null; _ok = false; });
    try {
      await saveServerUrl(url);
      final res = await dio.get('/api/setup/health');
      final data = res.data as Map<String, dynamic>;
      if (data['status'] == 'ok') {
        final c = ref.read(_configProvider);
        ref.read(_configProvider.notifier).state = c..serverUrl = url;
        setState(() => _ok = true);
      }
    } catch (e) {
      await saveServerUrl('');
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
                    Text('http://$ip:8002',
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
              hint: 'http://192.168.1.100:8002',
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
      }
    } catch (_) {}
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
            if (_mysqlInstructions != null) ...[
              _InfoCard(
                icon: Icons.warning_amber_rounded,
                color: AppColors.warning,
                title: 'MySQL non détecté sur ce système',
                body: _mysqlInstructions!,
              ),
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
                  child: Column(
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
// Page 4 — Compte administrateur
// ═════════════════════════════════════════════════════════════════════════════

class _AdminAccountPage extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;
  const _AdminAccountPage({required this.onNext, required this.onBack});

  @override
  ConsumerState<_AdminAccountPage> createState() => _AdminAccountPageState();
}

class _AdminAccountPageState extends ConsumerState<_AdminAccountPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _fname, _lname, _user, _email, _phone, _pwd, _pwd2;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _fname = TextEditingController();
    _lname = TextEditingController();
    _user  = TextEditingController();
    _email = TextEditingController();
    _phone = TextEditingController();
    _pwd   = TextEditingController();
    _pwd2  = TextEditingController();
  }

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      title: 'Compte administrateur',
      subtitle: 'Créez le premier compte avec tous les droits',
      onNext: () {
        if (!_formKey.currentState!.validate()) return;
        final c = ref.read(_configProvider);
        ref.read(_configProvider.notifier).state = c
          ..adminFname    = _fname.text.trim()
          ..adminLname    = _lname.text.trim()
          ..adminUsername = _user.text.trim()
          ..adminEmail    = _email.text.trim()
          ..adminPhone    = _phone.text.trim()
          ..adminPassword = _pwd.text;
        widget.onNext();
      },
      onBack: widget.onBack,
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Row(children: [
              Expanded(child: _Field(ctrl: _fname, label: 'Prénom',
                  validator: (v) => v!.isEmpty ? 'Requis' : null)),
              const SizedBox(width: 12),
              Expanded(child: _Field(ctrl: _lname, label: 'Nom',
                  validator: (v) => v!.isEmpty ? 'Requis' : null)),
            ]),
            const SizedBox(height: 12),
            _Field(ctrl: _user, label: "Nom d'utilisateur",
                hint: 'admin',
                validator: (v) => v!.isEmpty ? 'Requis' : null),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _Field(ctrl: _email, label: 'Email',
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => v!.contains('@') ? null : 'Email invalide')),
              const SizedBox(width: 12),
              Expanded(child: _Field(ctrl: _phone, label: 'Téléphone',
                  keyboardType: TextInputType.phone,
                  validator: (v) => v!.isEmpty ? 'Requis' : null)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextFormField(
                controller: _pwd,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Mot de passe',
                  suffixIcon: IconButton(
                    icon: Icon(_obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) => (v?.length ?? 0) < 8
                    ? 'Minimum 8 caractères'
                    : null,
              )),
              const SizedBox(width: 12),
              Expanded(child: TextFormField(
                controller: _pwd2,
                obscureText: _obscure,
                decoration: const InputDecoration(labelText: 'Confirmer'),
                validator: (v) =>
                    v != _pwd.text ? 'Ne correspond pas' : null,
              )),
            ]),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.2)),
              ),
              child: const Row(children: [
                Icon(Icons.shield_rounded, color: Color(0xFF7C3AED), size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ce compte aura tous les droits. Gardez ces identifiants '
                    'en lieu sûr — ils seront nécessaires pour gérer le serveur.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF7C3AED)),
                  ),
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

      await _step('Création du compte administrateur', () async {
        await dio.post('/api/setup/init', data: {
          'db_type': cfg.dbType == DbType.mysql ? 'mysql' : 'sqlite',
          'host': cfg.dbHost,
          'port': cfg.dbPort,
          'name': cfg.dbName,
          'user': cfg.dbUser,
          'password': cfg.dbPassword,
          'path': cfg.dbPath,
          'fname': cfg.adminFname,
          'lname': cfg.adminLname,
          'username': cfg.adminUsername,
          'email': cfg.adminEmail,
          'phone': cfg.adminPhone,
          'admin_password': cfg.adminPassword,
          'server_host': cfg.serverHost,
          'server_port': cfg.serverPort,
        });
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
                icon: Icons.person_rounded,
                label: 'Compte admin',
                value: cfg.adminUsername),
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
          ],
          const SizedBox(height: 20),
          if (needsServer)
            const _InfoCard(
              icon: Icons.lock_rounded,
              color: AppColors.primary,
              title: 'Accès à la console serveur',
              body:
                  'Pour gérer le serveur (démarrer/arrêter, changer de DB, voir les logs), '
                  'utilisez les identifiants du compte admin que vous venez de créer.',
            ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () {
                // Launch the POS app or close installer
                if (cfg.mode != InstallMode.server) {
                  // Open POS Connect client
                }
                // For server-only, just inform
              },
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
