import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _billingStatusProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final res = await dio.get('/api/billing/status');
  return res.data as Map<String, dynamic>;
});

final _billingPaymentsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final res = await dio.get('/api/billing/payments');
  return (res.data as List).cast<Map<String, dynamic>>();
});

final _billingConfigProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final res = await dio.get('/api/billing/config');
  return res.data as Map<String, dynamic>;
});

// ── Screen ────────────────────────────────────────────────────────────────────

class BillingScreen extends ConsumerWidget {
  const BillingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(_billingStatusProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Abonnement',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Gérez votre plan et vos paiements',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          const SizedBox(height: 28),
          status.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _ErrorCard(message: e.toString()),
            data: (data) => _BillingContent(data: data),
          ),
        ],
      ),
    );
  }
}

// ── PDF receipt generator ─────────────────────────────────────────────────────

Future<void> _printBillingInvoice(
    Map<String, dynamic> payment, Map<String, dynamic> statusData) async {
  final doc = pw.Document();
  final fmt = DateFormat('dd/MM/yyyy');
  final fmtFull = DateFormat('dd MMMM yyyy', 'fr_FR');

  final invoiceNum  = payment['invoice_number'] as String? ?? '';
  final method      = payment['method'] as String? ?? '';
  final amount      = payment['amount'] as double? ?? 0.0;
  final currency    = payment['currency'] as String? ?? 'USD';
  final description = payment['description'] as String? ?? 'Abonnement POS Connect';
  final paidAt      = payment['paid_at'] != null
      ? DateTime.tryParse(payment['paid_at'] as String)
      : null;
  final periodStart = payment['period_start'] != null
      ? DateTime.tryParse(payment['period_start'] as String)
      : null;
  final periodEnd   = payment['period_end'] != null
      ? DateTime.tryParse(payment['period_end'] as String)
      : null;

  final business = statusData['business_name'] as String? ?? '';
  final email    = statusData['owner_email'] as String? ?? '';

  final methodLabel = switch (method) {
    'stripe'   => 'Carte bancaire (Stripe)',
    'moncash'  => 'MonCash',
    'natcash'  => 'NatCash',
    'manual'   => 'Activation manuelle',
    _          => method,
  };

  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(40),
    build: (pw.Context ctx) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Header
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('POS Connect',
                  style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text('Plateforme de gestion commerciale',
                  style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey600)),
            ]),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text('REÇU DE PAIEMENT',
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blueGrey800)),
              pw.SizedBox(height: 4),
              pw.Text(invoiceNum,
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue700)),
            ]),
          ],
        ),
        pw.Divider(color: PdfColors.grey300, thickness: 1, height: 32),

        // Client info
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('FACTURÉ À',
                    style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey600, letterSpacing: 1)),
                pw.SizedBox(height: 6),
                pw.Text(business,
                    style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                if (email.isNotEmpty)
                  pw.Text(email,
                      style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
              ],
            )),
            pw.Expanded(child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('DATE DE PAIEMENT',
                    style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey600, letterSpacing: 1)),
                pw.SizedBox(height: 6),
                pw.Text(paidAt != null ? fmtFull.format(paidAt.toLocal()) : '—',
                    style: const pw.TextStyle(fontSize: 12)),
                if (periodStart != null && periodEnd != null) ...[
                  pw.SizedBox(height: 4),
                  pw.Text('Période : ${fmt.format(periodStart.toLocal())} — ${fmt.format(periodEnd.toLocal())}',
                      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                ],
              ],
            )),
          ],
        ),
        pw.SizedBox(height: 32),

        // Table
        pw.Container(
          decoration: pw.BoxDecoration(
            color: PdfColors.blueGrey50,
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Padding(
            padding: const pw.EdgeInsets.all(16),
            child: pw.Column(children: [
              pw.Row(children: [
                pw.Expanded(flex: 5,
                    child: pw.Text('DESCRIPTION',
                        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey600, letterSpacing: 0.8))),
                pw.Text('MÉTHODE',
                    style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey600, letterSpacing: 0.8)),
                pw.SizedBox(width: 40),
                pw.Text('MONTANT',
                    style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey600, letterSpacing: 0.8)),
              ]),
              pw.Divider(color: PdfColors.grey300, height: 16),
              pw.Row(children: [
                pw.Expanded(flex: 5,
                    child: pw.Text(description,
                        style: const pw.TextStyle(fontSize: 12))),
                pw.Text(methodLabel,
                    style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
                pw.SizedBox(width: 40),
                pw.Text('$currency ${amount.toStringAsFixed(2)}',
                    style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              ]),
              pw.Divider(color: PdfColors.grey300, height: 24),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Text('TOTAL PAYÉ : ',
                      style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                  pw.Text('$currency ${amount.toStringAsFixed(2)}',
                      style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold,
                          color: PdfColors.green700)),
                ],
              ),
            ]),
          ),
        ),
        pw.SizedBox(height: 32),

        // Status badge
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: pw.BoxDecoration(
            color: PdfColors.green50,
            border: pw.Border.all(color: PdfColors.green300),
            borderRadius: pw.BorderRadius.circular(20),
          ),
          child: pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
            pw.Text('✓  PAIEMENT CONFIRMÉ',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold,
                    color: PdfColors.green800)),
          ]),
        ),
        pw.Spacer(),
        pw.Divider(color: PdfColors.grey200, height: 1),
        pw.SizedBox(height: 8),
        pw.Center(
          child: pw.Text('Merci pour votre confiance — posconnect.ht',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey500)),
        ),
      ],
    ),
  ));

  await Printing.layoutPdf(onLayout: (_) async => doc.save());
}

// ── Main content ──────────────────────────────────────────────────────────────

class _BillingContent extends ConsumerWidget {
  final Map<String, dynamic> data;

  const _BillingContent({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status        = data['status'] as String? ?? 'trial';
    final daysLeft      = data['days_left'] as int?;
    final isGrace       = data['is_grace'] as bool? ?? false;
    final graceDaysLeft = data['grace_days_left'] as int?;
    final business      = data['business_name'] as String? ?? '';
    final email         = data['owner_email'] as String? ?? '';
    final hasStripe     = data['has_stripe'] as bool? ?? false;
    final payments      = ref.watch(_billingPaymentsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Grace period banner ────────────────────────────────────────────
        if (isGrace && graceDaysLeft != null) ...[
          _GraceBanner(daysLeft: graceDaysLeft),
          const SizedBox(height: 16),
        ],

        // ── Status card ────────────────────────────────────────────────────
        _StatusCard(status: status, daysLeft: daysLeft,
            business: business, email: email, hasStripe: hasStripe),
        const SizedBox(height: 24),

        // ── Payment options (only if not active) ───────────────────────────
        if (status != 'active') ...[
          const Text('Souscrire à un plan',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text(
              'Choisissez votre méthode de paiement pour continuer à utiliser POS Connect.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 16),
          _StripeCard(ref: ref),
          const SizedBox(height: 12),
          ref.watch(_billingConfigProvider).when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (cfg) => Column(
              children: [
                _MoncashCard(config: cfg),
                const SizedBox(height: 12),
                _NatcashCard(config: cfg),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],

        // ── Already active ─────────────────────────────────────────────────
        if (status == 'active') ...[
          _Card(
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.verified_rounded,
                    color: AppColors.success, size: 22),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Abonnement actif',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    SizedBox(height: 2),
                    Text('Votre boutique est pleinement opérationnelle.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 24),
        ],

        // ── Payment history ────────────────────────────────────────────────
        const Text('Historique des paiements',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        payments.when(
          loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              )),
          error: (e, _) => _ErrorCard(message: e.toString()),
          data: (list) => list.isEmpty
              ? _Card(
                  child: const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Aucun paiement enregistré',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ),
                  ),
                )
              : _Card(
                  child: Column(
                    children: [
                      // Header row
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(children: const [
                          Expanded(flex: 2,
                              child: Text('N° Facture',
                                  style: TextStyle(fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textSecondary))),
                          Expanded(flex: 3,
                              child: Text('Description',
                                  style: TextStyle(fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textSecondary))),
                          Expanded(child: Text('Méthode',
                              style: TextStyle(fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary))),
                          Expanded(child: Text('Montant',
                              style: TextStyle(fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary))),
                          Expanded(child: Text('Date',
                              style: TextStyle(fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary))),
                          SizedBox(width: 40),
                        ]),
                      ),
                      const Divider(height: 1),
                      ...list.asMap().entries.map((entry) =>
                          _PaymentRow(
                            payment: entry.value,
                            isLast: entry.key == list.length - 1,
                            statusData: data,
                          )),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

// ── Status card ───────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final String status;
  final int? daysLeft;
  final String business;
  final String email;
  final bool hasStripe;

  const _StatusCard({
    required this.status,
    required this.daysLeft,
    required this.business,
    required this.email,
    required this.hasStripe,
  });

  @override
  Widget build(BuildContext context) {
    final (color, icon, label, subtitle) = switch (status) {
      'active'    => (AppColors.success, Icons.check_circle_rounded,
                      'Actif', 'Votre abonnement est en cours'),
      'trial'     => (AppColors.accent, Icons.hourglass_top_rounded,
                      'Essai gratuit',
                      daysLeft != null ? '$daysLeft jour${daysLeft == 1 ? '' : 's'} restant${daysLeft == 1 ? '' : 's'}' : 'Période d\'essai'),
      'suspended' => (AppColors.error, Icons.block_rounded,
                      'Suspendu', 'Renouvelez pour continuer'),
      _           => (AppColors.textSecondary, Icons.help_outline_rounded,
                      status, ''),
    };

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(label,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(width: 8),
                    _PlanBadge(color: color, label: label),
                  ]),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(color: color, fontSize: 13,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ]),
          if (business.isNotEmpty || email.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            if (business.isNotEmpty)
              _InfoRow(icon: Icons.store_rounded, label: 'Boutique', value: business),
            if (email.isNotEmpty)
              _InfoRow(icon: Icons.email_outlined, label: 'Email', value: email),
          ],
        ],
      ),
    );
  }
}

// ── Stripe card ───────────────────────────────────────────────────────────────

class _StripeCard extends StatefulWidget {
  final WidgetRef ref;
  const _StripeCard({required this.ref});

  @override
  State<_StripeCard> createState() => _StripeCardState();
}

class _StripeCardState extends State<_StripeCard> {
  bool _loading = false;
  String? _error;

  Future<void> _checkout() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await dio.post('/api/billing/checkout/stripe');
      final url = res.data['checkout_url'] as String?;
      if (url != null) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      final msg = extractErrorMessage(e is Exception ? e as dynamic : Exception(e));
      setState(() { _error = msg; });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PaymentCard(
      icon: Icons.credit_card_rounded,
      iconColor: const Color(0xFF635BFF),
      title: 'Carte bancaire (Stripe)',
      subtitle: 'Visa, Mastercard, American Express — paiement sécurisé',
      errorMessage: _error,
      action: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF635BFF),
            minimumSize: const Size.fromHeight(44),
          ),
          onPressed: _loading ? null : _checkout,
          icon: _loading
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.open_in_new_rounded, size: 16),
          label: Text(_loading ? 'Redirection...' : 'Payer avec Stripe'),
        ),
      ),
    );
  }
}

// ── MonCash card ──────────────────────────────────────────────────────────────

class _MoncashCard extends StatelessWidget {
  final Map<String, dynamic> config;
  const _MoncashCard({required this.config});

  @override
  Widget build(BuildContext context) {
    final number  = config['moncash_number'] as String? ?? '';
    final priceHtg = (config['monthly_price_htg'] as num? ?? 1500).toStringAsFixed(0);
    final mode    = config['moncash_mode'] as String? ?? 'manual';
    final isApi   = mode == 'api';

    return _PaymentCard(
      icon: Icons.phone_android_rounded,
      iconColor: const Color(0xFFE53935),
      title: 'MonCash',
      subtitle: isApi
          ? 'Paiement automatique MonCash (Digicel)'
          : 'Paiement mobile MonCash (Digicel)',
      action: isApi
          ? _ApiModeAction(
              priceLabel: '$priceHtg HTG / mois',
              buttonLabel: 'Payer avec MonCash',
              color: const Color(0xFFE53935),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PaymentStep(number: '1', text: 'Ouvrez MonCash et sélectionnez "Transfert"'),
                _PaymentStep(number: '2', text: 'Envoyez $priceHtg HTG / mois au numéro :'),
                _CopyRow(value: number.isEmpty ? '+509 XXXX XXXX' : number),
                _PaymentStep(number: '3', text: 'Envoyez le reçu par WhatsApp ou email à votre agent'),
              ],
            ),
    );
  }
}

// ── NatCash card ──────────────────────────────────────────────────────────────

class _NatcashCard extends StatelessWidget {
  final Map<String, dynamic> config;
  const _NatcashCard({required this.config});

  @override
  Widget build(BuildContext context) {
    final number   = config['natcash_number'] as String? ?? '';
    final priceHtg = (config['monthly_price_htg'] as num? ?? 1500).toStringAsFixed(0);
    final mode     = config['natcash_mode'] as String? ?? 'manual';
    final isApi    = mode == 'api';

    return _PaymentCard(
      icon: Icons.smartphone_rounded,
      iconColor: const Color(0xFF1565C0),
      title: 'NatCash',
      subtitle: isApi
          ? 'Paiement automatique NatCash (Natcom)'
          : 'Paiement mobile NatCash (Natcom)',
      action: isApi
          ? _ApiModeAction(
              priceLabel: '$priceHtg HTG / mois',
              buttonLabel: 'Payer avec NatCash',
              color: const Color(0xFF1565C0),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PaymentStep(number: '1', text: 'Ouvrez NatCash et sélectionnez "Payer"'),
                _PaymentStep(number: '2', text: 'Envoyez $priceHtg HTG / mois au numéro :'),
                _CopyRow(value: number.isEmpty ? '+509 XXXX XXXX' : number),
                _PaymentStep(number: '3', text: 'Envoyez le reçu par WhatsApp ou email à votre agent'),
              ],
            ),
    );
  }
}

// ── API mode action ───────────────────────────────────────────────────────────

class _ApiModeAction extends StatelessWidget {
  final String priceLabel;
  final String buttonLabel;
  final Color color;
  const _ApiModeAction({
    required this.priceLabel,
    required this.buttonLabel,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.bolt_rounded, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              'Traitement automatique — $priceLabel',
              style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Intégration API en cours de configuration — contactez le support.')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
            child: Text(buttonLabel),
          ),
        ),
      ],
    );
  }
}

// ── Grace period banner ───────────────────────────────────────────────────────

class _GraceBanner extends StatelessWidget {
  final int daysLeft;
  const _GraceBanner({required this.daysLeft});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Votre période d\'essai est terminée. '
              'Il vous reste $daysLeft jour${daysLeft > 1 ? 's' : ''} de grâce pour renouveler '
              'avant la suspension de votre compte.',
              style: const TextStyle(fontSize: 13, color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: child,
    );
  }
}

class _PaymentCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget action;
  final String? errorMessage;

  const _PaymentCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.action,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
          ]),
          if (errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline, color: AppColors.error, size: 14),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(errorMessage!,
                        style: const TextStyle(
                            color: AppColors.error, fontSize: 12))),
              ]),
            ),
          ],
          const SizedBox(height: 16),
          action,
        ],
      ),
    );
  }
}

class _PlanBadge extends StatelessWidget {
  final Color color;
  final String label;
  const _PlanBadge({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Text('$label : ',
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 12)),
        Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

class _PaymentStep extends StatelessWidget {
  final String number;
  final String text;
  const _PaymentStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(number,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 13, height: 1.4))),
      ]),
    );
  }
}

class _CopyRow extends StatelessWidget {
  final String value;
  const _CopyRow({required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 28, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(children: [
        Text(value,
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                letterSpacing: 0.5)),
        const Spacer(),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Numéro copié'),
                duration: Duration(seconds: 2),
              ),
            );
          },
          child: const Icon(Icons.copy_rounded,
              size: 16, color: AppColors.textSecondary),
        ),
      ]),
    );
  }
}

// ── Payment row ───────────────────────────────────────────────────────────────

class _PaymentRow extends StatelessWidget {
  final Map<String, dynamic> payment;
  final bool isLast;
  final Map<String, dynamic> statusData;

  const _PaymentRow({
    required this.payment,
    required this.isLast,
    required this.statusData,
  });

  @override
  Widget build(BuildContext context) {
    final invoiceNum  = payment['invoice_number'] as String? ?? '';
    final description = payment['description'] as String? ?? '';
    final method      = payment['method'] as String? ?? '';
    final amount      = (payment['amount'] as num?)?.toDouble() ?? 0.0;
    final currency    = payment['currency'] as String? ?? 'USD';
    final paidAt      = payment['paid_at'] != null
        ? DateTime.tryParse(payment['paid_at'] as String)
        : null;

    final methodLabel = switch (method) {
      'stripe'   => 'Stripe',
      'moncash'  => 'MonCash',
      'natcash'  => 'NatCash',
      'manual'   => 'Manuel',
      _          => method,
    };

    final methodColor = switch (method) {
      'stripe'   => const Color(0xFF635BFF),
      'moncash'  => const Color(0xFFE53935),
      'natcash'  => const Color(0xFF1565C0),
      _          => AppColors.textSecondary,
    };

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Expanded(flex: 2,
                child: Text(invoiceNum,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600,
                        color: AppColors.primary))),
            Expanded(flex: 3,
                child: Text(description,
                    style: const TextStyle(fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis)),
            Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: methodColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(methodLabel,
                      style: TextStyle(fontSize: 10,
                          fontWeight: FontWeight.w600, color: methodColor),
                      textAlign: TextAlign.center),
                )),
            Expanded(
                child: Text('$currency ${amount.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600))),
            Expanded(
                child: Text(
                    paidAt != null
                        ? DateFormat('dd/MM/yyyy').format(paidAt.toLocal())
                        : '—',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary))),
            SizedBox(
              width: 40,
              child: IconButton(
                icon: const Icon(Icons.download_rounded, size: 18),
                tooltip: 'Télécharger le reçu',
                color: AppColors.textSecondary,
                onPressed: () => _printBillingInvoice(payment, statusData),
              ),
            ),
          ]),
        ),
        if (!isLast) const Divider(height: 1),
      ],
    );
  }
}

// ── Error card ────────────────────────────────────────────────────────────────

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline, color: AppColors.error),
        const SizedBox(width: 12),
        Expanded(
            child: Text(message,
                style: const TextStyle(color: AppColors.error))),
      ]),
    );
  }
}
