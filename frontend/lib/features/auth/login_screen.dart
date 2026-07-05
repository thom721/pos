import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl     = TextEditingController();
  final _passwordCtrl  = TextEditingController();
  bool _obscure        = true;
  final _formKey       = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await ref
        .read(authProvider.notifier)
        .cloudLogin(_emailCtrl.text.trim(), _passwordCtrl.text);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          // ── Left branding panel (wide screens) ──────────────────────────
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
                        style: TextStyle(color: Color(0xFF8BA4BE), fontSize: 16)),
                    const SizedBox(height: 48),
                    ...[
                      ('Caisse rapide et intuitive', Icons.speed_rounded),
                      ('Gestion des stocks en temps réel', Icons.inventory_rounded),
                      ('Rapports et statistiques détaillés', Icons.bar_chart_rounded),
                      ('Multi-caisse & synchronisation cloud', Icons.sync_rounded),
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
                  child: Form(
                    key: _formKey,
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
                          const SizedBox(height: 32),
                        ],

                        const Text('Connexion',
                            style: TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        const Text('Accédez à votre espace POS Connect',
                            style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary)),
                        const SizedBox(height: 28),

                        // ── Error banner ──────────────────────────────────
                        if (authState.error != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: AppColors.error.withValues(alpha: 0.3)),
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

                        // ── Fields ────────────────────────────────────────
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
                          validator: (v) =>
                              v == null || v.isEmpty ? 'Requis' : null,
                        ),
                        const SizedBox(height: 24),

                        SizedBox(
                          height: 50,
                          child: FilledButton(
                            onPressed: authState.isLoading ? null : _submit,
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
                                    color: AppColors.textSecondary,
                                    fontSize: 13)),
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
