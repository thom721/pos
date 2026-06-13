import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _serverCtrl = TextEditingController();
  bool _obscure = true;
  bool _showServerConfig = false;

  @override
  void initState() {
    super.initState();
    _loadSavedServerUrl();
  }

  Future<void> _loadSavedServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(AppConstants.serverUrlKey);
    if (saved != null && saved.isNotEmpty) {
      setState(() => _serverCtrl.text = saved);
    }
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _serverCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await saveServerUrl(_serverCtrl.text.trim());
    await ref
        .read(authProvider.notifier)
        .login(_usernameCtrl.text.trim(), _passwordCtrl.text);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          // Left panel (desktop only)
          if (MediaQuery.sizeOf(context).width >= 900)
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
                    const Text(
                      'POS Connect',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Gérez votre commerce avec précision',
                      style: TextStyle(
                          color: Color(0xFF8BA4BE), fontSize: 16),
                    ),
                    const SizedBox(height: 48),
                    // Features list
                    ...[
                      ('Caisse rapide et intuitive', Icons.speed_rounded),
                      ('Gestion des stocks en temps réel', Icons.inventory_rounded),
                      ('Rapports et statistiques détaillés', Icons.bar_chart_rounded),
                      ('Gestion clients & fournisseurs', Icons.people_rounded),
                    ].map((f) => Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 48),
                          child: Row(
                            children: [
                              Icon(f.$2,
                                  color: AppColors.accent, size: 18),
                              const SizedBox(width: 12),
                              Text(f.$1,
                                  style: const TextStyle(
                                      color: Color(0xFFB8CCE0),
                                      fontSize: 14)),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
            ),

          // Right panel — Login form
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(40),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Mobile logo
                      if (MediaQuery.sizeOf(context).width < 900) ...[
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
                        const SizedBox(height: 16),
                        const Center(
                          child: Text(
                            'POS Connect',
                            style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],

                      const Text(
                        'Connexion',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Entrez vos identifiants pour accéder à votre espace',
                        style: TextStyle(
                            fontSize: 14, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 36),

                      Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _usernameCtrl,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: "Nom d'utilisateur",
                                prefixIcon: Icon(Icons.person_outline_rounded),
                              ),
                              validator: (v) => v!.isEmpty ? 'Requis' : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _passwordCtrl,
                              obscureText: _obscure,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _submit(),
                              decoration: InputDecoration(
                                labelText: 'Mot de passe',
                                prefixIcon:
                                    const Icon(Icons.lock_outline_rounded),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscure
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined),
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                ),
                              ),
                              validator: (v) => v!.isEmpty ? 'Requis' : null,
                            ),
                            const SizedBox(height: 12),

                            // Advanced server config toggle
                            GestureDetector(
                              onTap: () => setState(
                                  () => _showServerConfig = !_showServerConfig),
                              behavior: HitTestBehavior.opaque,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.dns_outlined,
                                    size: 14,
                                    color: AppColors.textSecondary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Paramètres du serveur',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    _showServerConfig
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                    size: 16,
                                    color: AppColors.textSecondary,
                                  ),
                                ],
                              ),
                            ),
                            if (_showServerConfig) ...[
                              const SizedBox(height: 10),
                              TextFormField(
                                controller: _serverCtrl,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  labelText: 'Adresse du serveur',
                                  hintText: AppConstants.baseUrl,
                                  prefixIcon:
                                      const Icon(Icons.cloud_outlined),
                                  helperText:
                                      'Laisser vide pour utiliser la valeur par défaut',
                                ),
                              ),
                            ],

                            const SizedBox(height: 8),

                            // Error message
                            if (authState.error != null) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.error.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color:
                                          AppColors.error.withOpacity(0.3)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.error_outline,
                                        color: AppColors.error, size: 16),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        authState.error!,
                                        style: const TextStyle(
                                            color: AppColors.error,
                                            fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),

                            SizedBox(
                              height: 50,
                              child: ElevatedButton(
                                onPressed: authState.isLoading ? null : _submit,
                                child: authState.isLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Se connecter'),
                              ),
                            ),
                          ],
                        ),
                      ),
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
}
