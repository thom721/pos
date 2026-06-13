import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/providers/settings_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _taxCtrl;
  late final TextEditingController _footerCtrl;
  late final TextEditingController _rateUsdCtrl;
  late final TextEditingController _rateEurCtrl;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _taxCtrl = TextEditingController(text: s.taxRate.toString());
    _footerCtrl = TextEditingController(text: s.receiptFooter);
    _rateUsdCtrl = TextEditingController(text: s.rateUsd.toString());
    _rateEurCtrl = TextEditingController(text: s.rateEur.toString());
  }

  @override
  void dispose() {
    _taxCtrl.dispose();
    _footerCtrl.dispose();
    _rateUsdCtrl.dispose();
    _rateEurCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final current = ref.read(settingsProvider);
    await ref.read(settingsProvider.notifier).save(
          current.copyWith(
            taxRate: double.tryParse(_taxCtrl.text) ?? 0,
            receiptFooter: _footerCtrl.text.trim(),
            rateUsd: double.tryParse(_rateUsdCtrl.text) ?? 130.0,
            rateEur: double.tryParse(_rateEurCtrl.text) ?? 140.0,
          ),
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Paramètres enregistrés'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Type de commerce ─────────────────────────────────────────
            _SectionHeader(icon: Icons.category_rounded, title: 'Type de commerce'),
            const SizedBox(height: 16),
            _Card(
              child: Column(
                children: [
                  _SelectionTile(
                    value: 'commerce',
                    label: 'Commerce / Épicerie',
                    description: 'Vente de produits au détail',
                    icon: Icons.shopping_bag_rounded,
                    selected: settings.businessType == 'commerce',
                    onTap: () => notifier.save(
                        settings.copyWith(businessType: 'commerce')),
                  ),
                  const Divider(height: 1),
                  _SelectionTile(
                    value: 'restaurant',
                    label: 'Restaurant / Snack',
                    description: 'Vente de plats et boissons',
                    icon: Icons.restaurant_rounded,
                    selected: settings.businessType == 'restaurant',
                    onTap: () => notifier.save(
                        settings.copyWith(businessType: 'restaurant')),
                  ),
                  const Divider(height: 1),
                  _SelectionTile(
                    value: 'depot',
                    label: 'Dépôt / Grossiste',
                    description: 'Vente en gros et distribution',
                    icon: Icons.warehouse_rounded,
                    selected: settings.businessType == 'depot',
                    onTap: () => notifier.save(
                        settings.copyWith(businessType: 'depot')),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Devise ───────────────────────────────────────────────────
            _SectionHeader(icon: Icons.attach_money_rounded, title: 'Devise principale'),
            const SizedBox(height: 16),
            _Card(
              child: Column(
                children: [
                  _CurrencyTile(
                    currency: 'HTG',
                    symbol: 'HTG ',
                    label: 'Gourde haïtienne (HTG)',
                    selected: settings.currency == 'HTG',
                    onTap: () => notifier.save(
                        settings.copyWith(currency: 'HTG', currencySymbol: 'HTG ')),
                  ),
                  const Divider(height: 1),
                  _CurrencyTile(
                    currency: 'USD',
                    symbol: '\$ ',
                    label: 'Dollar américain (USD)',
                    selected: settings.currency == 'USD',
                    onTap: () => notifier.save(
                        settings.copyWith(currency: 'USD', currencySymbol: '\$ ')),
                  ),
                  const Divider(height: 1),
                  _CurrencyTile(
                    currency: 'EUR',
                    symbol: '€ ',
                    label: 'Euro (EUR)',
                    selected: settings.currency == 'EUR',
                    onTap: () => notifier.save(
                        settings.copyWith(currency: 'EUR', currencySymbol: '€ ')),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Taux du jour ─────────────────────────────────────────────
            _SectionHeader(icon: Icons.currency_exchange_rounded, title: 'Taux du jour'),
            const SizedBox(height: 8),
            Text('Utilisé pour les proformas en devise étrangère',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            _Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(
                            child: Text('\$',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                    fontSize: 16)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text('1 USD =',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w500)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _rateUsdCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                              suffixText: 'HTG',
                              isDense: true,
                            ),
                            validator: (v) {
                              final d = double.tryParse(v ?? '');
                              if (d == null || d <= 0) return 'Invalide';
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.info.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(
                            child: Text('€',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.info,
                                    fontSize: 16)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text('1 EUR =',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w500)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _rateEurCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                              suffixText: 'HTG',
                              isDense: true,
                            ),
                            validator: (v) {
                              final d = double.tryParse(v ?? '');
                              if (d == null || d <= 0) return 'Invalide';
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Fiscalité ────────────────────────────────────────────────
            _SectionHeader(icon: Icons.percent_rounded, title: 'Fiscalité'),
            const SizedBox(height: 16),
            _Card(
              child: Column(
                children: [
                  ListTile(
                    title: const Text('Activer la taxe',
                        style: TextStyle(fontSize: 14)),
                    subtitle: const Text('Affiche la taxe sur les reçus',
                        style: TextStyle(fontSize: 12)),
                    trailing: Switch(
                      value: settings.showTax,
                      thumbColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.selected)
                            ? Colors.white
                            : null,
                      ),
                      trackColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.selected)
                            ? AppColors.primary
                            : null,
                      ),
                      onChanged: (v) =>
                          notifier.save(settings.copyWith(showTax: v)),
                    ),
                  ),
                  if (settings.showTax) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: TextFormField(
                        controller: _taxCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Taux de taxe (%)',
                          prefixIcon: Icon(Icons.percent_rounded),
                          suffixText: '%',
                        ),
                        validator: (v) {
                          final d = double.tryParse(v ?? '');
                          if (d == null || d < 0 || d > 100) {
                            return 'Valeur invalide (0-100)';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Reçu ─────────────────────────────────────────────────────
            _SectionHeader(icon: Icons.receipt_rounded, title: 'Reçu de caisse'),
            const SizedBox(height: 16),
            _Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextFormField(
                  controller: _footerCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Message de pied de reçu',
                    hintText: 'Merci pour votre achat !',
                    prefixIcon: Icon(Icons.message_rounded),
                  ),
                ),
              ),
            ),
            // ── Système (Windows uniquement) ─────────────────────────────
            if (Platform.isWindows || Platform.isLinux) ...[
              const SizedBox(height: 24),
              _SectionHeader(icon: Icons.computer_rounded, title: 'Système'),
              const SizedBox(height: 16),
              _Card(child: const _StartupTile()),
              const SizedBox(height: 24),
            ],

            const SizedBox(height: 8),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_rounded),
                label: const Text('Enregistrer les paramètres'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ── Helper widgets ─────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: AppColors.divider),
      ),
      clipBehavior: Clip.hardEdge,
      child: child,
    );
  }
}

class _RadioDot extends StatelessWidget {
  final bool selected;
  const _RadioDot({required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.divider,
          width: 2,
        ),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary,
                ),
              ),
            )
          : null,
    );
  }
}

class _SelectionTile extends StatelessWidget {
  final String value;
  final String label;
  final String description;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SelectionTile({
    required this.value,
    required this.label,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (selected ? AppColors.primary : AppColors.textSecondary)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon,
                  size: 20,
                  color: selected
                      ? AppColors.primary
                      : AppColors.textSecondary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400)),
                  Text(description,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary)),
                ],
              ),
            ),
            _RadioDot(selected: selected),
          ],
        ),
      ),
    );
  }
}

class _StartupTile extends StatefulWidget {
  const _StartupTile();

  @override
  State<_StartupTile> createState() => _StartupTileState();
}

class _StartupTileState extends State<_StartupTile> {
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    launchAtStartup.isEnabled().then((v) {
      if (mounted) setState(() => _enabled = v);
    });
  }

  Future<void> _toggle(bool value) async {
    if (value) {
      await launchAtStartup.enable();
    } else {
      await launchAtStartup.disable();
    }
    if (mounted) setState(() => _enabled = value);
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.rocket_launch_rounded,
            size: 20, color: AppColors.primary),
      ),
      title: const Text('Démarrage automatique',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: const Text('Lancer POS Connect au démarrage de Windows',
          style: TextStyle(fontSize: 12)),
      trailing: _enabled == null
          ? const SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Switch(
              value: _enabled!,
              thumbColor: WidgetStateProperty.resolveWith(
                (s) => s.contains(WidgetState.selected) ? Colors.white : null,
              ),
              trackColor: WidgetStateProperty.resolveWith(
                (s) => s.contains(WidgetState.selected) ? AppColors.primary : null,
              ),
              onChanged: _toggle,
            ),
    );
  }
}

class _CurrencyTile extends StatelessWidget {
  final String currency;
  final String symbol;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CurrencyTile({
    required this.currency,
    required this.symbol,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : AppColors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  symbol.trim(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400)),
            ),
            _RadioDot(selected: selected),
          ],
        ),
      ),
    );
  }
}
