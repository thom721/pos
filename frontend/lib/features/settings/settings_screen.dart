import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart' show DioException;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:pos_connect/core/constants.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart' show dio, extractErrorMessage;
import 'package:pos_connect/providers/settings_provider.dart';
import 'package:pos_connect/providers/sync_provider.dart';
import 'package:printing/printing.dart';

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

            // ── Imprimantes ───────────────────────────────────────────────
            if (!kIsWeb) ...[
              const SizedBox(height: 24),
              _SectionHeader(
                  icon: Icons.print_rounded, title: 'Imprimantes'),
              const SizedBox(height: 16),
              _PrinterConfigSection(settings: settings, notifier: notifier),
            ],

            // ── Système (Windows uniquement) ─────────────────────────────
            if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) ...[
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

// ── Printer configuration section ──────────────────────────────────────────

class _PrinterConfigSection extends StatefulWidget {
  final AppSettings settings;
  final SettingsNotifier notifier;

  const _PrinterConfigSection({
    required this.settings,
    required this.notifier,
  });

  @override
  State<_PrinterConfigSection> createState() => _PrinterConfigSectionState();
}

class _PrinterConfigSectionState extends State<_PrinterConfigSection> {
  List<Printer> _printers = [];
  bool _loadingPrinters = true;

  @override
  void initState() {
    super.initState();
    _loadPrinters();
  }

  Future<void> _loadPrinters() async {
    List<Printer> printers = [];
    try {
      printers = await Printing.listPrinters();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _printers = printers;
        _loadingPrinters = false;
      });
    }
  }

  // Finds the Printer whose url matches the stored name, or null.
  Printer? _findPrinter(String url) {
    if (url.isEmpty) return null;
    try {
      return _printers.firstWhere((p) => p.url == url);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingPrinters) {
      return _Card(
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('Détection des imprimantes...',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      );
    }

    if (_printers.isEmpty) {
      return _Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.print_disabled_rounded,
                    size: 20, color: AppColors.warning),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Aucune imprimante détectée sur cet appareil.',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 20),
                tooltip: 'Réessayer',
                onPressed: () {
                  setState(() => _loadingPrinters = true);
                  _loadPrinters();
                },
              ),
            ],
          ),
        ),
      );
    }

    final posPrinter = _findPrinter(widget.settings.posPrinterName);
    final docPrinter = _findPrinter(widget.settings.docPrinterName);

    return _Card(
      child: Column(
        children: [
          // ── Imprimante reçus caisse ─────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.receipt_long_rounded,
                      size: 18, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Imprimante reçus caisse',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      Text('Pour les tickets de caisse POS',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: _PrinterDropdown(
              printers: _printers,
              selected: posPrinter,
              onChanged: (p) => widget.notifier.save(
                  widget.settings.copyWith(posPrinterName: p?.url ?? '')),
            ),
          ),
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            title: const Text('Impression automatique à chaque vente',
                style: TextStyle(fontSize: 13)),
            trailing: Switch(
              value: widget.settings.posAutoPrint,
              thumbColor: WidgetStateProperty.resolveWith(
                (s) => s.contains(WidgetState.selected) ? Colors.white : null,
              ),
              trackColor: WidgetStateProperty.resolveWith(
                (s) => s.contains(WidgetState.selected)
                    ? AppColors.primary
                    : null,
              ),
              onChanged: (v) => widget.notifier
                  .save(widget.settings.copyWith(posAutoPrint: v)),
            ),
          ),

          const Divider(height: 1),

          // ── Imprimante documents ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.description_rounded,
                      size: 18, color: AppColors.info),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Imprimante documents',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      Text('Pour les factures, proformas et autres',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: _PrinterDropdown(
              printers: _printers,
              selected: docPrinter,
              onChanged: (p) => widget.notifier.save(
                  widget.settings.copyWith(docPrinterName: p?.url ?? '')),
            ),
          ),
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            title: const Text('Impression automatique à chaque document',
                style: TextStyle(fontSize: 13)),
            trailing: Switch(
              value: widget.settings.docAutoPrint,
              thumbColor: WidgetStateProperty.resolveWith(
                (s) => s.contains(WidgetState.selected) ? Colors.white : null,
              ),
              trackColor: WidgetStateProperty.resolveWith(
                (s) => s.contains(WidgetState.selected)
                    ? AppColors.info
                    : null,
              ),
              onChanged: (v) => widget.notifier
                  .save(widget.settings.copyWith(docAutoPrint: v)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Sans imprimante configurée, la boîte de dialogue système s\'affiche.',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  tooltip: 'Actualiser la liste',
                  onPressed: () {
                    setState(() => _loadingPrinters = true);
                    _loadPrinters();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrinterDropdown extends StatelessWidget {
  final List<Printer> printers;
  final Printer? selected;
  final ValueChanged<Printer?> onChanged;

  const _PrinterDropdown({
    required this.printers,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(
        isDense: true,
        prefixIcon: Icon(Icons.print_rounded, size: 18),
        contentPadding: EdgeInsets.fromLTRB(0, 8, 12, 8),
      ),
      child: DropdownButton<Printer?>(
        value: selected,
        isExpanded: true,
        underline: const SizedBox(),
        hint: const Text('Sélectionner une imprimante',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        items: [
          const DropdownMenuItem<Printer?>(
            value: null,
            child: Text('— Aucune (boîte de dialogue système) —',
                style:
                    TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ),
          ...printers.map((p) => DropdownMenuItem<Printer?>(
                value: p,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.name,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (p.isDefault) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('défaut',
                            style: TextStyle(
                                fontSize: 10, color: AppColors.primary)),
                      ),
                    ],
                  ],
                ),
              )),
        ],
        onChanged: onChanged,
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

// ── Sync section ──────────────────────────────────────────────────────────────

class _SyncSection extends ConsumerStatefulWidget {
  const _SyncSection();

  @override
  ConsumerState<_SyncSection> createState() => _SyncSectionState();
}

class _SyncSectionState extends ConsumerState<_SyncSection> {
  final _cloudUrlCtrl = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure  = true;
  bool _showForm = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // Pre-fill URL and email from current status (survives app updates)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final status = ref.read(syncStatusProvider);
      status.whenData((s) {
        final url   = s['cloud_url']         as String? ?? '';
        final email = s['cloud_owner_email'] as String? ?? '';
        // Pre-fill URL: prefer saved cloud_url, fall back to posconnect default
        if (_cloudUrlCtrl.text.isEmpty) {
          _cloudUrlCtrl.text = url.isNotEmpty ? url : AppConstants.cloudUrl;
        }
        if (email.isNotEmpty && _emailCtrl.text.isEmpty) _emailCtrl.text = email;
      });
    });
    // Refresh sync status every 30 s so the user sees live timestamps
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) { if (mounted) ref.invalidate(syncStatusProvider); },
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _cloudUrlCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _configure() async {
    final ok = await ref.read(syncProvider.notifier).configure(
      cloudUrl: _cloudUrlCtrl.text.trim(),
      email:    _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
    );
    if (!mounted) return;
    final s = ref.read(syncProvider);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? (s.lastResult ?? 'OK') : (s.error ?? 'Erreur')),
      backgroundColor: ok ? AppColors.success : AppColors.error,
    ));
    if (ok) setState(() => _showForm = false);
  }

  Future<void> _runSync() async {
    await ref.read(syncProvider.notifier).runSync();
    if (!mounted) return;
    ref.invalidate(pendingOfflineCountProvider);
    final s = ref.read(syncProvider);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(s.error ?? s.lastResult ?? 'Sync terminé'),
      backgroundColor: s.error != null ? AppColors.error : AppColors.success,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final syncState    = ref.watch(syncProvider);
    final statusAsync  = ref.watch(syncStatusProvider);
    final pendingAsync = ref.watch(pendingOfflineCountProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(icon: Icons.sync_rounded, title: 'Synchronisation cloud'),
        const SizedBox(height: 16),
        _Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Status ───────────────────────────────────────────────────
              statusAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Erreur: $e',
                    style: const TextStyle(color: AppColors.error, fontSize: 12)),
                data: (status) {
                  final configured = status['configured'] as bool? ?? false;
                  final cloudUrl   = status['cloud_url'] as String? ?? '';
                  final entities   = (status['entities'] as List?) ?? [];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(
                          configured ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                          size: 18,
                          color: configured ? AppColors.success : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            configured
                                ? 'Connecté à $cloudUrl'
                                : 'Non configuré — liez ce serveur à votre compte cloud',
                            style: TextStyle(
                              fontSize: 13,
                              color: configured ? AppColors.success : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ]),
                      if (configured && entities.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        ...entities.map((e) => _EntityRow(entity: e as Map<String, dynamic>)),
                      ],
                    ],
                  );
                },
              ),
              // ── Offline pending badge ─────────────────────────────────────
              if ((pendingAsync.value ?? 0) > 0) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.4)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.cloud_off_rounded,
                        size: 14, color: AppColors.warning),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${pendingAsync.value} opération${(pendingAsync.value ?? 0) > 1 ? 's' : ''} '
                        'en attente (hors-ligne) — envoyées au retour du réseau',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.warning),
                      ),
                    ),
                  ]),
                ),
              ],
              const SizedBox(height: 16),

              // ── Actions ──────────────────────────────────────────────────
              Row(children: [
                OutlinedButton.icon(
                  onPressed: () => setState(() => _showForm = !_showForm),
                  icon: const Icon(Icons.settings_ethernet_rounded, size: 16),
                  label: Text(_showForm ? 'Fermer' : 'Configurer'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: syncState.isRunning ? null : _runSync,
                  icon: syncState.isRunning
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.sync_rounded, size: 16),
                  label: const Text('Synchroniser'),
                ),
              ]),

              // ── Config form ───────────────────────────────────────────────
              if (_showForm) ...[
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
                Text('Connexion au serveur cloud',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 12),
                TextField(
                  controller: _cloudUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'URL du serveur cloud',
                    hintText: 'https://api.posconnect.ht',
                    prefixIcon: Icon(Icons.cloud_outlined),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email du compte cloud',
                    prefixIcon: Icon(Icons.email_outlined),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Mot de passe',
                    prefixIcon: const Icon(Icons.lock_outline),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: syncState.isConfiguring ? null : _configure,
                    child: syncState.isConfiguring
                        ? const SizedBox(
                            height: 16, width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Lier ce serveur au cloud'),
                  ),
                ),
              ],
            ],
          ),
          ),  // Padding
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _EntityRow extends StatelessWidget {
  final Map<String, dynamic> entity;
  const _EntityRow({required this.entity});

  @override
  Widget build(BuildContext context) {
    final type     = entity['entity_type'] as String? ?? '';
    final pushed   = entity['records_pushed'] as int? ?? 0;
    final pulled   = entity['records_pulled'] as int? ?? 0;
    final lastPush = entity['last_push_at'] as String?;
    final error    = entity['last_error'] as String?;

    String? fmtPush;
    if (lastPush != null) {
      try {
        fmtPush = DateFormat('dd/MM HH:mm').format(DateTime.parse(lastPush).toLocal());
      } catch (_) {}
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(width: 110, child: Text(type, style: const TextStyle(fontSize: 12))),
        Icon(
          error != null ? Icons.error_outline : Icons.check_circle_outline,
          size: 14,
          color: error != null ? AppColors.error : AppColors.success,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            error ?? '↑$pushed  ↓$pulled${fmtPush != null ? '  $fmtPush' : ''}',
            style: TextStyle(
              fontSize: 11,
              color: error != null ? AppColors.error : AppColors.textSecondary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }
}

// ── Billing URL section (local server only) ───────────────────────────────────

class _BillingUrlSection extends StatefulWidget {
  const _BillingUrlSection();

  @override
  State<_BillingUrlSection> createState() => _BillingUrlSectionState();
}

class _BillingUrlSectionState extends State<_BillingUrlSection> {
  final _urlCtrl = TextEditingController();
  bool _saving   = false;
  bool _saved    = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCurrent() async {
    try {
      final res  = await dio.get('/api/sync/status');
      final data = res.data as Map<String, dynamic>? ?? {};
      final billingUrl = data['billing_url'] as String? ?? '';
      final cloudUrl   = data['cloud_url']   as String? ?? '';
      // Use billing_url if set; fall back to cloud_url (they're the same for POS Connect)
      final effective  = billingUrl.isNotEmpty ? billingUrl : cloudUrl;
      if (effective.isNotEmpty && mounted) setState(() => _urlCtrl.text = effective);
    } catch (_) {}
  }

  Future<void> _save() async {
    final url = _urlCtrl.text.trim().replaceAll(RegExp(r'/+$'), '');
    if (url.isEmpty) return;
    setState(() { _saving = true; _error = null; _saved = false; });
    try {
      await dio.post('/api/sync/configure-billing', data: {'billing_url': url});
      if (mounted) setState(() { _saved = true; _saving = false; });
    } catch (e) {
      final msg = e is DioException ? extractErrorMessage(e) : e.toString();
      if (mounted) setState(() { _error = msg; _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          icon: Icons.receipt_long_rounded,
          title: 'Serveur de facturation',
        ),
        const SizedBox(height: 8),
        Text(
          'URL du serveur POS Connect SaaS utilisé pour vérifier les licences '
          'et proxifier les abonnements. Laisser vide si ce poste est le serveur cloud.',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        _Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _urlCtrl,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'URL du serveur de facturation',
                    hintText: 'https://pos.infini-software.cloud',
                    prefixIcon: Icon(Icons.cloud_outlined),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_rounded, size: 16),
                    label: Text(_saving ? 'Enregistrement...' : 'Enregistrer'),
                  ),
                ),
                if (_saved) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    const Icon(Icons.check_circle_outline, color: AppColors.success, size: 16),
                    const SizedBox(width: 6),
                    const Text('URL enregistrée avec succès.',
                        style: TextStyle(color: AppColors.success, fontSize: 12)),
                  ]),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    const Icon(Icons.error_outline, color: AppColors.error, size: 16),
                    const SizedBox(width: 6),
                    Expanded(child: Text(_error!,
                        style: const TextStyle(color: AppColors.error, fontSize: 12))),
                  ]),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
