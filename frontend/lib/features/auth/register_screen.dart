import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/repositories/auth_repository.dart';
import 'package:pos_connect/data/api/api_client.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _businessNameCtrl = TextEditingController();
  final _emailCtrl        = TextEditingController();
  final _phoneCtrl        = TextEditingController();
  final _passwordCtrl     = TextEditingController();
  final _confirmPassCtrl  = TextEditingController();

  bool _obscurePass    = true;
  bool _obscureConfirm = true;
  bool _loading        = false;
  bool _success        = false;
  String? _error;

  final _repo = AuthRepository();

  @override
  void dispose() {
    _businessNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() { _loading = true; _error = null; });

    try {
      await _repo.register(
        businessName: _businessNameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      );
      if (mounted) setState(() { _loading = false; _success = true; });
    } on DioException catch (e) {
      final msg = extractErrorMessage(e);
      if (mounted) setState(() { _loading = false; _error = msg; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Erreur inattendue. Réessayez.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          // ── Left branding panel ─────────────────────────────────────────
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
                    const Text('Démarrez votre essai gratuit de 30 jours',
                        style:
                            TextStyle(color: Color(0xFF8BA4BE), fontSize: 16)),
                    const SizedBox(height: 48),
                    ...[
                      ('Aucune carte requise pour l\'essai',
                          Icons.credit_card_off_outlined),
                      ('Multi-caisse inclus', Icons.point_of_sale_rounded),
                      ('Synchronisation cloud automatique',
                          Icons.cloud_sync_rounded),
                      ('Support Stripe, MonCash & NatCash',
                          Icons.payments_rounded),
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

          // ── Right form panel ────────────────────────────────────────────
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(40),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: _success ? _buildSuccess() : _buildForm(isWide),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Success state ─────────────────────────────────────────────────────────

  Widget _buildSuccess() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle_rounded,
              color: AppColors.success, size: 40),
        ),
        const SizedBox(height: 24),
        const Text('Compte créé avec succès !',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Text(
          'Bienvenue ! Votre boutique "${_businessNameCtrl.text.trim()}" '
          'est prête. Vous bénéficiez de 30 jours d\'essai gratuit.',
          style: const TextStyle(
              fontSize: 14, color: AppColors.textSecondary, height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: () => context.go('/login'),
          icon: const Icon(Icons.login_rounded, size: 18),
          label: const Text('Se connecter maintenant'),
          style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50)),
        ),
      ],
    );
  }

  // ── Registration form ─────────────────────────────────────────────────────

  Widget _buildForm(bool isWide) {
    return Form(
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
                        fontSize: 26, fontWeight: FontWeight.w700))),
            const SizedBox(height: 24),
          ],

          // Header
          const Text('Créer un compte',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Essai gratuit de 30 jours — sans carte bancaire',
              style: TextStyle(fontSize: 13, color: AppColors.success)),
          const SizedBox(height: 28),

          // Error
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline,
                    color: AppColors.error, size: 16),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(_error!,
                        style: const TextStyle(
                            color: AppColors.error, fontSize: 13))),
              ]),
            ),
          ],

          // Business name
          TextFormField(
            controller: _businessNameCtrl,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nom de la boutique',
              prefixIcon: Icon(Icons.store_outlined),
            ),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Requis' : null,
          ),
          const SizedBox(height: 16),

          // Email
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

          // Phone (optional)
          TextFormField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Téléphone (optionnel)',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          const SizedBox(height: 16),

          // Password
          TextFormField(
            controller: _passwordCtrl,
            obscureText: _obscurePass,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Mot de passe',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(_obscurePass
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () =>
                    setState(() => _obscurePass = !_obscurePass),
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Requis';
              if (v.length < 6) return 'Minimum 6 caractères';
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Confirm password
          TextFormField(
            controller: _confirmPassCtrl,
            obscureText: _obscureConfirm,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Confirmer le mot de passe',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(_obscureConfirm
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Requis';
              if (v != _passwordCtrl.text) return 'Les mots de passe ne correspondent pas';
              return null;
            },
          ),
          const SizedBox(height: 28),

          // Submit button
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Créer mon compte',
                      style: TextStyle(fontSize: 15)),
            ),
          ),
          const SizedBox(height: 20),

          // Login link
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Déjà un compte ?',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => context.go('/login'),
                child: const Text('Se connecter',
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
}
