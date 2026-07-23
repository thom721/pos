import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pos_connect/core/date_utils.dart' show toHaitiTime;
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:dio/dio.dart' show DioException;
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

final _planUsageProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final res = await dio.get('/api/billing/plan-usage');
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
            error: (e, _) => _ErrorCard(
              message: e is DioException
                  ? extractErrorMessage(e)
                  : e.toString(),
            ),
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
  final fmtFull = DateFormat('dd MMMM yyyy', 'fr_FR');

  // Charger le logo
  pw.ImageProvider? logoImg;
  try {
    final data = await rootBundle.load('assets/icon/splash_logo.png');
    logoImg = pw.MemoryImage(data.buffer.asUint8List());
  } catch (_) {}

  // ── Données paiement ────────────────────────────────────────────────────────
  final invoiceNum  = payment['invoice_number'] as String? ?? '';
  final method      = payment['method'] as String? ?? '';
  final amount      = payment['amount'] as double? ?? 0.0;
  final currency    = payment['currency'] as String? ?? 'HTG';
  final description = payment['description'] as String? ?? 'Abonnement POS Connect';
  final paidAt      = payment['paid_at'] != null
      ? DateTime.tryParse(payment['paid_at'] as String) : null;
  final periodEnd   = payment['period_end'] != null
      ? DateTime.tryParse(payment['period_end'] as String) : null;
  final periodStart = payment['period_start'] != null
      ? DateTime.tryParse(payment['period_start'] as String) : null;

  final business = statusData['business_name'] as String? ?? '';
  final email    = statusData['owner_email']   as String? ?? '';

  // Numéro de reçu = 4 derniers chiffres zéro-paddés du numéro de facture
  final receiptNum = invoiceNum.contains('-')
      ? '0000-${invoiceNum.split('-').last.padLeft(4, '0')}'
      : invoiceNum;

  // Durée de l'abonnement
  final days = (periodEnd != null && periodStart != null)
      ? periodEnd.difference(periodStart).inDays
      : 30;

  final expiryLine = periodEnd != null
      ? 'Expire le ${toHaitiTime(periodEnd).toIso8601String().substring(0, 10)} ($days jours)'
      : '';

  final methodLabel = switch (method) {
    'stripe'  => 'Carte bancaire (Stripe)',
    'moncash' => 'MonCash',
    'natcash' => 'NatCash',
    'manual'  => 'Activation manuelle',
    _         => method,
  };

  // Infos plateforme depuis l'API (avec fallback)
  String platformAddr  = '';
  String platformEmail = '';
  try {
    final res = await dio.get('/api/public/contact-info');
    platformAddr  = res.data['address'] as String? ?? '';
    platformEmail = res.data['email']   as String? ?? '';
  } catch (_) {}

  // ── Montant formaté ─────────────────────────────────────────────────────────
  final amtStr = '${amount % 1 == 0 ? amount.toInt() : amount} $currency';

  // ── Couleurs ────────────────────────────────────────────────────────────────
  const blue    = PdfColor(0.0,  0.47, 0.77); // #0077C5
  const darkTxt = PdfColor(0.1,  0.1,  0.1);
  const grey    = PdfColor(0.45, 0.45, 0.45);
  const greyLt  = PdfColor(0.85, 0.85, 0.85);

  // ── Helpers de cellule table ─────────────────────────────────────────────────
  pw.Widget cell(String text, {
    bool bold = false,
    PdfColor color = darkTxt,
    pw.TextAlign align = pw.TextAlign.left,
    double size = 10,
  }) =>
      pw.Text(text,
          textAlign: align,
          style: pw.TextStyle(
              fontSize: size,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color));

  pw.Widget totRow(String label, String value, {bool bold = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(children: [
          pw.Expanded(child: pw.SizedBox()),
          pw.SizedBox(
            width: 120,
            child: pw.Text(label,
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                    color: bold ? darkTxt : grey)),
          ),
          pw.SizedBox(width: 16),
          pw.SizedBox(
            width: 90,
            child: pw.Text(value,
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                    color: darkTxt)),
          ),
        ]),
      );

  // ── Document ─────────────────────────────────────────────────────────────────
  final doc = pw.Document();

  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.symmetric(horizontal: 48, vertical: 40),
    build: (pw.Context ctx) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [

        // ── 1. Header : "Reçu" + brand ────────────────────────────────────────
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Colonne gauche : titre + métadonnées
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Reçu',
                  style: pw.TextStyle(fontSize: 30, fontWeight: pw.FontWeight.bold,
                      color: darkTxt)),
              pw.SizedBox(height: 10),
              pw.Row(children: [
                pw.SizedBox(
                  width: 130,
                  child: pw.Text('Numéro de facture',
                      style: pw.TextStyle(fontSize: 10, color: grey)),
                ),
                pw.Text(invoiceNum,
                    style: pw.TextStyle(fontSize: 10, color: darkTxt)),
              ]),
              pw.SizedBox(height: 3),
              pw.Row(children: [
                pw.SizedBox(
                  width: 130,
                  child: pw.Text('Numéro de reçu',
                      style: pw.TextStyle(fontSize: 10, color: grey)),
                ),
                pw.Text(receiptNum,
                    style: pw.TextStyle(fontSize: 10, color: darkTxt)),
              ]),
              pw.SizedBox(height: 3),
              pw.Row(children: [
                pw.SizedBox(
                  width: 130,
                  child: pw.Text('Date de paiement',
                      style: pw.TextStyle(fontSize: 10, color: grey)),
                ),
                pw.Text(paidAt != null ? fmtFull.format(toHaitiTime(paidAt)) : '—',
                    style: pw.TextStyle(fontSize: 10, color: darkTxt)),
              ]),
            ]),
            // Colonne droite : logo
            if (logoImg != null)
              pw.Image(logoImg, width: 120, height: 55, fit: pw.BoxFit.contain)
            else
              pw.RichText(
                text: pw.TextSpan(children: [
                  pw.TextSpan(
                    text: 'POS',
                    style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold,
                        color: const PdfColor(0.8, 0.0, 0.0)),
                  ),
                  pw.TextSpan(
                    text: 'Connect',
                    style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold,
                        color: blue),
                  ),
                ]),
              ),
          ],
        ),

        pw.SizedBox(height: 24),
        pw.Divider(color: greyLt, thickness: 0.8, height: 1),
        pw.SizedBox(height: 20),

        // ── 2. Vendeur / Client ───────────────────────────────────────────────
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('POS Connect',
                    style: pw.TextStyle(fontSize: 11,
                        fontWeight: pw.FontWeight.bold, color: darkTxt)),
                if (platformAddr.isNotEmpty)
                  pw.Text(platformAddr,
                      style: pw.TextStyle(fontSize: 10, color: grey)),
                if (platformEmail.isNotEmpty)
                  pw.Text(platformEmail,
                      style: pw.TextStyle(fontSize: 10, color: grey)),
              ],
            )),
            pw.Expanded(child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Facturé à',
                    style: pw.TextStyle(fontSize: 11,
                        fontWeight: pw.FontWeight.bold, color: darkTxt)),
                if (business.isNotEmpty)
                  pw.Text(business,
                      style: pw.TextStyle(fontSize: 10, color: darkTxt)),
                if (email.isNotEmpty)
                  pw.Text(email,
                      style: pw.TextStyle(fontSize: 10, color: grey)),
              ],
            )),
          ],
        ),

        pw.SizedBox(height: 24),

        // ── 3. Résumé paiement ────────────────────────────────────────────────
        pw.Text(
          '$amtStr payé le ${paidAt != null ? fmtFull.format(toHaitiTime(paidAt)) : '—'}',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold,
              color: darkTxt),
        ),

        pw.SizedBox(height: 16),

        // ── 4. Table des articles ─────────────────────────────────────────────
        // En-têtes
        pw.Row(children: [
          pw.Expanded(flex: 5, child: cell('Description', color: blue, bold: true)),
          pw.SizedBox(width: 40, child: cell('Qté', color: blue, bold: true, align: pw.TextAlign.center)),
          pw.SizedBox(width: 90, child: cell('Prix unitaire', color: blue, bold: true, align: pw.TextAlign.right)),
          pw.SizedBox(width: 80, child: cell('Montant', color: blue, bold: true, align: pw.TextAlign.right)),
        ]),
        pw.SizedBox(height: 6),
        pw.Divider(color: greyLt, thickness: 0.6, height: 1),
        pw.SizedBox(height: 8),

        // Ligne article
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(flex: 5, child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              cell(description),
              if (expiryLine.isNotEmpty)
                pw.Text(expiryLine,
                    style: pw.TextStyle(fontSize: 9, color: grey)),
            ],
          )),
          pw.SizedBox(width: 40, child: cell('1', align: pw.TextAlign.center)),
          pw.SizedBox(width: 90, child: cell(amtStr, align: pw.TextAlign.right)),
          pw.SizedBox(width: 80, child: cell(amtStr, align: pw.TextAlign.right)),
        ]),

        pw.SizedBox(height: 8),
        pw.Divider(color: greyLt, thickness: 0.6, height: 1),
        pw.SizedBox(height: 4),

        // Totaux
        totRow('Sous-total', amtStr),
        totRow('Total', amtStr),
        pw.SizedBox(height: 2),
        totRow('Montant payé', amtStr, bold: true),

        pw.SizedBox(height: 28),
        pw.Divider(color: greyLt, thickness: 0.6, height: 1),
        pw.SizedBox(height: 16),

        // ── 5. Historique de paiement ─────────────────────────────────────────
        pw.Text('Historique de paiement',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold,
                color: darkTxt)),
        pw.SizedBox(height: 10),

        // En-têtes historique
        pw.Row(children: [
          pw.Expanded(flex: 2, child: cell('Moyen de paiement', color: grey)),
          pw.Expanded(flex: 2, child: cell('Date', color: grey)),
          pw.Expanded(flex: 2, child: cell('Montant payé', color: grey)),
          pw.Expanded(flex: 2, child: cell('Numéro de reçu', color: grey)),
        ]),
        pw.SizedBox(height: 6),
        pw.Divider(color: greyLt, thickness: 0.6, height: 1),
        pw.SizedBox(height: 6),

        // Ligne historique
        pw.Row(children: [
          pw.Expanded(flex: 2, child: cell(methodLabel)),
          pw.Expanded(flex: 2, child: cell(
              paidAt != null ? fmtFull.format(toHaitiTime(paidAt)) : '—')),
          pw.Expanded(flex: 2, child: cell(amtStr)),
          pw.Expanded(flex: 2, child: cell(receiptNum)),
        ]),

        pw.Spacer(),

        // ── 6. Footer ─────────────────────────────────────────────────────────
        pw.Divider(color: greyLt, thickness: 0.6, height: 1),
        pw.SizedBox(height: 6),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.Text('Page 1 sur 1',
                style: pw.TextStyle(fontSize: 9, color: grey)),
          ],
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
    final status           = data['status'] as String? ?? 'trial';
    final daysLeft         = data['days_left'] as int?;
    final isGrace          = data['is_grace'] as bool? ?? false;
    final graceDaysLeft    = data['grace_days_left'] as int?;
    final business         = data['business_name'] as String? ?? '';
    final email            = data['owner_email'] as String? ?? '';
    final hasStripe        = data['has_stripe'] as bool? ?? false;
    final subscriptionEndsAt = data['subscription_ends_at'] as String?;
    final payments         = ref.watch(_billingPaymentsProvider);

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
            business: business, email: email, hasStripe: hasStripe,
            subscriptionEndsAt: subscriptionEndsAt),
        const SizedBox(height: 24),

        // ── Plan usage (caisses + dépôts) ──────────────────────────────────
        const Text('Utilisation du plan',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        ref.watch(_planUsageProvider).when(
          loading: () => const LinearProgressIndicator(),
          error:   (_, __) => const SizedBox.shrink(),
          data: (usage) => _PlanUsageCard(usage: usage),
        ),
        const SizedBox(height: 24),

        // ── Payment options ────────────────────────────────────────────────
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
          // Combine plan-usage (real total) + config (payment modes)
          Builder(builder: (ctx) {
            final cfgAsync   = ref.watch(_billingConfigProvider);
            final usageAsync = ref.watch(_planUsageProvider);
            return cfgAsync.when(
              loading: () => const SizedBox.shrink(),
              error:   (_, __) => const SizedBox.shrink(),
              data: (cfg) {
                final priceHtg = usageAsync.when(
                  data:    (u) => (u['total_monthly_htg'] as num? ?? cfg['monthly_price_htg'] as num? ?? 1500).toDouble(),
                  loading: ()  => (cfg['monthly_price_htg'] as num? ?? 1500).toDouble(),
                  error:   (_, __) => (cfg['monthly_price_htg'] as num? ?? 1500).toDouble(),
                );
                return _PaymentCards(priceHtg: priceHtg, config: cfg);
              },
            );
          }),
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
          error: (e, _) => _ErrorCard(
            message: e is DioException
                ? extractErrorMessage(e)
                : e.toString(),
          ),
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
  final String? subscriptionEndsAt;

  const _StatusCard({
    required this.status,
    required this.daysLeft,
    required this.business,
    required this.email,
    required this.hasStripe,
    this.subscriptionEndsAt,
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
          if (business.isNotEmpty || email.isNotEmpty || subscriptionEndsAt != null) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            if (business.isNotEmpty)
              _InfoRow(icon: Icons.store_rounded, label: 'Boutique', value: business),
            if (email.isNotEmpty)
              _InfoRow(icon: Icons.email_outlined, label: 'Email', value: email),
            if (subscriptionEndsAt != null) ...[
              _InfoRow(
                icon: Icons.event_rounded,
                label: 'Abonnement jusqu\'au',
                value: DateFormat('dd MMM yyyy', 'fr_FR').format(
                    toHaitiTime(DateTime.parse(subscriptionEndsAt!))),
              ),
            ],
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

// ── Détail utilisation du plan (caisses + dépôts) ────────────────────────────

class _PlanUsageCard extends StatelessWidget {
  final Map<String, dynamic> usage;
  const _PlanUsageCard({required this.usage});

  @override
  Widget build(BuildContext context) {
    final maxCaisses   = usage['max_caisses']   as int?    ?? 1;
    final curCaisses   = usage['current_caisses'] as int?  ?? 0;
    final extraCaisses = usage['extra_caisses'] as int?    ?? 0;
    final xCaisseHtg   = (usage['price_per_extra_caisse_htg'] as num? ?? 500).toDouble();
    final maxDepots    = usage['max_depots']    as int?    ?? 1;
    final curDepots    = usage['current_depots'] as int?   ?? 0;
    final extraDepots  = usage['extra_depots']  as int?    ?? 0;
    final xDepotHtg    = (usage['price_per_extra_depot_htg'] as num? ?? 500).toDouble();
    final baseHtg      = (usage['base_price_htg']    as num? ?? 1500).toDouble();
    final totalHtg     = (usage['total_monthly_htg'] as num? ?? 1500).toDouble();
    final hasExtras    = extraCaisses > 0 || extraDepots > 0;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _UsageRow(
            icon: Icons.point_of_sale_rounded,
            label: 'Caisses',
            current: curCaisses,
            max: maxCaisses,
            extra: extraCaisses,
            extraPriceHtg: xCaisseHtg,
          ),
          const SizedBox(height: 10),
          _UsageRow(
            icon: Icons.warehouse_rounded,
            label: 'Dépôts',
            current: curDepots,
            max: maxDepots,
            extra: extraDepots,
            extraPriceHtg: xDepotHtg,
          ),
          const Divider(height: 24),
          if (hasExtras) ...[
            _PriceBreakRow('Plan de base', baseHtg),
            if (extraCaisses > 0)
              _PriceBreakRow(
                '$extraCaisses caisse${extraCaisses > 1 ? "s" : ""} supplémentaire${extraCaisses > 1 ? "s" : ""}',
                extraCaisses * xCaisseHtg,
              ),
            if (extraDepots > 0)
              _PriceBreakRow(
                '$extraDepots dépôt${extraDepots > 1 ? "s" : ""} supplémentaire${extraDepots > 1 ? "s" : ""}',
                extraDepots * xDepotHtg,
              ),
            const Divider(height: 16),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total / mois',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              Text('${totalHtg.toStringAsFixed(0)} HTG',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppColors.primary)),
            ],
          ),
        ],
      ),
    );
  }
}

class _UsageRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final int      current;
  final int      max;
  final int      extra;
  final double   extraPriceHtg;

  const _UsageRow({
    required this.icon,
    required this.label,
    required this.current,
    required this.max,
    required this.extra,
    required this.extraPriceHtg,
  });

  @override
  Widget build(BuildContext context) {
    final isOver  = extra > 0;
    final barFrac = max == 0 ? 1.0 : (current / max).clamp(0.0, 1.0);
    final color   = isOver ? AppColors.error : AppColors.success;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          const Spacer(),
          Text('$current / $max inclus',
              style: TextStyle(
                  fontSize: 12,
                  color: isOver ? AppColors.error : AppColors.textSecondary,
                  fontWeight: isOver ? FontWeight.w600 : FontWeight.w400)),
          if (isOver) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('+$extra × ${extraPriceHtg.toStringAsFixed(0)} HTG',
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.error)),
            ),
          ],
        ]),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: barFrac,
            minHeight: 5,
            backgroundColor: AppColors.divider,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _PriceBreakRow extends StatelessWidget {
  final String label;
  final double amount;
  const _PriceBreakRow(this.label, this.amount);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          Text('${amount.toStringAsFixed(0)} HTG',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

// ── Cartes de paiement (MonCash + NatCash) ────────────────────────────────────

class _PaymentCards extends StatelessWidget {
  final double              priceHtg;
  final Map<String, dynamic> config;

  const _PaymentCards({required this.priceHtg, required this.config});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _MoncashCard(priceHtg: priceHtg, config: config),
        const SizedBox(height: 12),
        _NatcashCard(priceHtg: priceHtg, config: config),
      ],
    );
  }
}

// ── MonCash card ──────────────────────────────────────────────────────────────

class _MoncashCard extends StatelessWidget {
  final double              priceHtg;
  final Map<String, dynamic> config;
  const _MoncashCard({required this.priceHtg, required this.config});

  @override
  Widget build(BuildContext context) {
    final mode  = config['moncash_mode'] as String? ?? 'manual';
    final isApi = mode == 'api';

    return _PaymentCard(
      icon: Icons.phone_android_rounded,
      iconColor: const Color(0xFFE53935),
      title: 'MonCash',
      subtitle: isApi
          ? 'Paiement automatique MonCash (Digicel)'
          : 'Paiement mobile MonCash (Digicel)',
      action: isApi
          ? _ApiModeAction(
              priceLabel: '${priceHtg.toStringAsFixed(0)} HTG / mois',
              buttonLabel: 'Payer avec MonCash',
              color: const Color(0xFFE53935),
            )
          : _ManualPaymentForm(method: 'moncash', priceHtg: priceHtg),
    );
  }
}

// ── NatCash card ──────────────────────────────────────────────────────────────

class _NatcashCard extends StatelessWidget {
  final double              priceHtg;
  final Map<String, dynamic> config;
  const _NatcashCard({required this.priceHtg, required this.config});

  @override
  Widget build(BuildContext context) {
    final mode  = config['natcash_mode'] as String? ?? 'manual';
    final isApi = mode == 'api';

    return _PaymentCard(
      icon: Icons.smartphone_rounded,
      iconColor: const Color(0xFF1565C0),
      title: 'NatCash',
      subtitle: isApi
          ? 'Paiement automatique NatCash (Natcom)'
          : 'Paiement mobile NatCash (Natcom)',
      action: isApi
          ? _ApiModeAction(
              priceLabel: '${priceHtg.toStringAsFixed(0)} HTG / mois',
              buttonLabel: 'Payer avec NatCash',
              color: const Color(0xFF1565C0),
            )
          : _ManualPaymentForm(method: 'natcash', priceHtg: priceHtg),
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

// ── Manual payment submission form ────────────────────────────────────────────

class _ManualPaymentForm extends StatefulWidget {
  final String  method;
  final double  priceHtg;
  final String? number;    // null = cache étapes + champ référence
  final String? stepVerb;

  const _ManualPaymentForm({
    required this.method,
    required this.priceHtg,
    this.number,
    this.stepVerb,
  });

  @override
  State<_ManualPaymentForm> createState() => _ManualPaymentFormState();
}

class _ManualPaymentFormState extends State<_ManualPaymentForm> {
  final _refCtrl = TextEditingController();
  int    _months    = 1;
  bool   _submitting = false;
  bool   _submitted  = false;
  String? _error;

  static const _monthOptions = [1, 2, 3, 6, 12];

  @override
  void dispose() {
    _refCtrl.dispose();
    super.dispose();
  }

  double get _totalAmount => widget.priceHtg * _months;

  Future<void> _submit() async {
    final ref = _refCtrl.text.trim();
    // Référence obligatoire seulement si le numéro de paiement est affiché
    if (widget.number != null && ref.isEmpty) return;
    setState(() { _submitting = true; _error = null; _submitted = false; });
    try {
      await dio.post('/api/billing/submit-payment', data: {
        'method':  widget.method,
        'months':  _months,
        if (ref.isNotEmpty) 'reference': ref,
      });
      setState(() { _submitted = true; });
    } catch (e) {
      setState(() { _error = e is DioException ? extractErrorMessage(e) : e.toString(); });
    } finally {
      setState(() { _submitting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          const Icon(Icons.check_circle_outline, color: AppColors.success, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Paiement de $_months mois soumis — un administrateur le validera sous peu '
              'et votre abonnement sera activé.',
              style: const TextStyle(color: AppColors.success, fontSize: 13),
            ),
          ),
        ]),
      );
    }

    final totalStr = _totalAmount.toStringAsFixed(0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Month selector ────────────────────────────────────────────────
        const Text('Nombre de mois',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          children: _monthOptions.map((m) {
            final selected = m == _months;
            return ChoiceChip(
              label: Text('$m mois'),
              selected: selected,
              onSelected: (_) => setState(() { _months = m; }),
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
              selectedColor: AppColors.primary,
              backgroundColor: AppColors.background,
              side: BorderSide(
                color: selected ? AppColors.primary : AppColors.divider,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),

        // ── Étapes de paiement (visibles uniquement si un numéro est configuré) ──
        if (widget.number != null) ...[
          _PaymentStep(number: '1',
              text: 'Ouvrez ${widget.method == 'moncash' ? 'MonCash' : 'NatCash'} '
                    'et sélectionnez "${widget.stepVerb ?? ''}"'),
          _PaymentStep(number: '2',
              text: 'Envoyez $totalStr HTG'
                    '${_months > 1 ? ' ($_months × ${widget.priceHtg.toStringAsFixed(0)} HTG)' : ''}'
                    ' au numéro :'),
          _CopyRow(value: widget.number!),
          _PaymentStep(number: '3',
              text: 'Entrez le numéro de transaction ci-dessous et cliquez Soumettre :'),
          const SizedBox(height: 6),
          TextField(
            controller: _refCtrl,
            decoration: const InputDecoration(
              labelText: 'Numéro de transaction / reçu',
              hintText: 'Ex: MC-20260715-XXXX',
              prefixIcon: Icon(Icons.tag_rounded),
              isDense: true,
            ),
            onSubmitted: (_) { if (!_submitting) _submit(); },
          ),
          const SizedBox(height: 12),
        ],
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send_rounded, size: 16),
            label: Text(_submitting ? 'Envoi...' : 'Soumettre — $totalStr HTG / $_months mois'),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 16),
            const SizedBox(width: 6),
            Expanded(child: Text(_error!,
                style: const TextStyle(color: AppColors.error, fontSize: 12))),
          ]),
        ],
      ],
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

    final paymentStatus = payment['status'] as String? ?? 'paid';
    final isPending     = paymentStatus == 'pending';

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
            // Invoice number — dim if pending
            Expanded(flex: 2,
                child: Text(invoiceNum,
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600,
                        color: isPending
                            ? AppColors.textSecondary
                            : AppColors.primary))),
            Expanded(flex: 3,
                child: Text(description,
                    style: const TextStyle(fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis)),
            // Method badge
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
            // Amount
            Expanded(
                child: Text('$currency ${amount.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600))),
            // Date or pending badge
            Expanded(
                child: isPending
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                        ),
                        child: const Text('En attente',
                            style: TextStyle(fontSize: 10,
                                fontWeight: FontWeight.w600, color: Colors.orange),
                            textAlign: TextAlign.center),
                      )
                    : Text(
                        paidAt != null
                            ? DateFormat('dd/MM/yyyy').format(paidAt.toLocal())
                            : '—',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary))),
            // Download (hidden for pending)
            SizedBox(
              width: 40,
              child: isPending
                  ? const Tooltip(
                      message: 'En attente de confirmation admin',
                      child: Icon(Icons.hourglass_top_rounded,
                          size: 16, color: Colors.orange),
                    )
                  : IconButton(
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
