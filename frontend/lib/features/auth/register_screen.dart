import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/repositories/auth_repository.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/providers/pricing_provider.dart';
import 'package:pos_connect/shared/widgets/pos_logo.dart';

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
  bool _termsAccepted  = false;
  String? _error;

  final _repo = AuthRepository();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showIntroModal());
  }

  void _showIntroModal() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: Icon(Icons.admin_panel_settings_rounded,
                        color: Colors.amber.shade800, size: 28),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text('Compte Administrateur',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                ]),
                const SizedBox(height: 20),
                const Text(
                  'Ce compte sera l\'administrateur principal de votre système POS Connect. '
                  'Il vous permettra de gérer vos caisses, dépôts et utilisateurs.',
                  style: TextStyle(fontSize: 14, color: Color(0xFF4A5568), height: 1.5),
                ),
                const SizedBox(height: 16),
                _ModalBullet(Icons.security_rounded, Colors.red.shade400,
                    'Conservez vos identifiants en lieu sûr — ne les partagez pas.'),
                const SizedBox(height: 10),
                _ModalBullet(Icons.store_rounded, AppColors.primary,
                    'Vous aurez 1 dépôt (magasin) et 1 caisse par défaut à l\'ouverture.'),
                const SizedBox(height: 10),
                _ModalBullet(Icons.expand_rounded, AppColors.success,
                    'Vous pourrez agrandir votre espace selon les conditions d\'Infini Software.'),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('J\'ai compris, continuer',
                        style: TextStyle(fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

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
    final pricing = ref.watch(pricingProvider);
    final trialDays = pricing.valueOrNull?.trialDays ?? 30;
    final trialLabel = 'Essai gratuit $trialDays jours';

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
                    const PosLogo(width: 180),
                    const SizedBox(height: 24),
                    const Text('POS Connect',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5)),
                    const SizedBox(height: 12),
                    Text('Démarrez votre $trialLabel',
                        style: const TextStyle(
                            color: Color(0xFF8BA4BE), fontSize: 16)),
                    const SizedBox(height: 48),
                    ...[
                      ('Multi-dépôts : business, resto, club…',
                          Icons.store_rounded),
                      ('Vendez depuis votre téléphone ou tablette',
                          Icons.phone_android_rounded),
                      ('Émettez des reçus en un clic',
                          Icons.receipt_long_rounded),
                      ('Synchronisation cloud automatique',
                          Icons.cloud_sync_rounded),
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
                  child: _success ? _buildSuccess(trialDays) : _buildForm(isWide, trialDays),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Success state ─────────────────────────────────────────────────────────

  Widget _buildSuccess(int trialDays) {
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
          'est prête. Vous bénéficiez de $trialDays jours d\'essai gratuit.',
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

  Widget _buildForm(bool isWide, int trialDays) {
    return Form(
      key: _formKey,
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
          Text('Essai gratuit de $trialDays jours — sans carte bancaire',
              style: const TextStyle(fontSize: 13, color: AppColors.success)),
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
          const SizedBox(height: 20),

          // Privacy policy checkbox
          InkWell(
            onTap: () => setState(() => _termsAccepted = !_termsAccepted),
            borderRadius: BorderRadius.circular(8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Checkbox(
                value: _termsAccepted,
                onChanged: (v) => setState(() => _termsAccepted = v ?? false),
                activeColor: AppColors.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    children: [
                      const TextSpan(text: 'J\'ai lu et j\'accepte la '),
                      TextSpan(
                        text: 'politique de confidentialité',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                          decorationColor: AppColors.primary,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () => context.go('/privacy'),
                      ),
                    ],
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // Submit button
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _loading || !_termsAccepted ? null : _submit,
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

class _ModalBullet extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _ModalBullet(this.icon, this.color, this.text);

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 16),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(text,
            style: const TextStyle(
                fontSize: 13, color: Color(0xFF4A5568), height: 1.5)),
      ),
    ],
  );
}
