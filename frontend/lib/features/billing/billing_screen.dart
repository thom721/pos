import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pos_connect/core/date_utils.dart' show haitiNow, toHaitiTime, parseApiDate;
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:dio/dio.dart' show DioException;
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/warehouse_model.dart';
import 'package:pos_connect/data/models/pos_register_model.dart';
import 'package:pos_connect/data/repositories/warehouse_repository.dart';
import 'package:pos_connect/providers/entrepot_provider.dart';

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

/// Pré-sélection des caisses depuis la page Dépôts&Caisses (bouton "Payer").
/// Remis à [] après lecture dans _RegisterPaymentSection.initState.
final preSelectedRegisterIdsProvider = StateProvider<List<String>>((ref) => []);

class _WhWithRegs {
  final WarehouseModel warehouse;
  final List<PosRegisterModel> registers;
  const _WhWithRegs(this.warehouse, this.registers);
}

final _allWarehouseRegistersProvider =
    FutureProvider.autoDispose<List<_WhWithRegs>>((ref) async {
  final repo = WarehouseRepository();
  final whs = await repo.listWarehouses();
  final result = <_WhWithRegs>[];
  for (final wh in whs) {
    final regs = await repo.listRegisters(wh.id);
    result.add(_WhWithRegs(wh, regs));
  }
  return result;
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
                // '-' plutôt que '—' : la police par défaut du package `pdf`
                // (Helvetica/WinAnsi) ne couvre pas l'em dash U+2014.
                pw.Text(paidAt != null ? fmtFull.format(toHaitiTime(paidAt)) : '-',
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
          '$amtStr payé le ${paidAt != null ? fmtFull.format(toHaitiTime(paidAt)) : '-'}',
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
              paidAt != null ? fmtFull.format(toHaitiTime(paidAt)) : '-')),
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
    final business         = data['business_name'] as String? ?? '';
    final email            = data['owner_email'] as String? ?? '';
    final hasStripe        = data['has_stripe'] as bool? ?? false;
    final subscriptionEndsAt = data['subscription_ends_at'] as String?;
    final payments         = ref.watch(_billingPaymentsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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

        // ── Paiement par caisse ────────────────────────────────────────────
        ref.watch(_billingConfigProvider).when(
          loading: () => const SizedBox.shrink(),
          error:   (_, __) => const SizedBox.shrink(),
          data: (cfg) {
            final pricePerCaisse = (cfg['price_per_extra_caisse_htg'] as num? ?? 500).toDouble();
            final discountPct    = (cfg['annual_discount_pct']        as num? ??  20).toDouble();
            return _RegisterPaymentSection(
                pricePerCaisse: pricePerCaisse,
                annualDiscountPct: discountPct,
                cashEnabled: cfg['cash_enabled'] as bool? ?? true,
                moncashEnabled: cfg['moncash_enabled'] as bool? ?? true,
                natcashEnabled: cfg['natcash_enabled'] as bool? ?? true,
                cardEnabled: cfg['card_enabled'] as bool? ?? true);
          },
        ),
        const SizedBox(height: 24),

        // ── Paiement par entrepôt ────────────────────────────────────────────
        ref.watch(_billingConfigProvider).when(
          loading: () => const SizedBox.shrink(),
          error:   (_, __) => const SizedBox.shrink(),
          data: (cfg) {
            final pricePerEntrepot = (cfg['price_per_extra_depot_htg'] as num? ?? 500).toDouble();
            final discountPct      = (cfg['annual_discount_pct']       as num? ??  20).toDouble();
            return _EntrepotPaymentSection(
                pricePerEntrepot: pricePerEntrepot,
                annualDiscountPct: discountPct,
                cashEnabled: cfg['cash_enabled'] as bool? ?? true,
                moncashEnabled: cfg['moncash_enabled'] as bool? ?? true,
                natcashEnabled: cfg['natcash_enabled'] as bool? ?? true);
          },
        ),
        const SizedBox(height: 24),

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
                    parseApiDate(subscriptionEndsAt)),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// ── Détail utilisation du plan (caisses + dépôts) ────────────────────────────

class _PlanUsageCard extends StatefulWidget {
  final Map<String, dynamic> usage;
  const _PlanUsageCard({required this.usage});

  @override
  State<_PlanUsageCard> createState() => _PlanUsageCardState();
}

class _PlanUsageCardState extends State<_PlanUsageCard> {
  bool _showRegisters = false;

  @override
  Widget build(BuildContext context) {
    final usage         = widget.usage;
    final curCaisses    = usage['current_caisses'] as int? ?? 0;
    final maxCaisses    = usage['max_caisses']     as int? ?? 0;  // initial = 1 par dépôt
    final extraCaisses  = usage['extra_caisses']   as int? ?? (curCaisses - maxCaisses).clamp(0, curCaisses);
    final curDepots     = usage['current_depots']  as int? ?? 0;
    final xCaisseHtg    = (usage['price_per_caisse_htg'] as num? ?? 500).toDouble();
    final totalHtg      = (usage['total_monthly_htg'] as num? ?? 0).toDouble();
    final registers     = (usage['registers'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();

    // Grouper par warehouse_name
    final Map<String, List<Map<String, dynamic>>> byWh = {};
    for (final r in registers) {
      final wh = r['warehouse_name'] as String? ?? 'Sans dépôt';
      byWh.putIfAbsent(wh, () => []).add(r);
    }

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Résumé ────────────────────────────────────────────────────
          // Caisses de base (1 par dépôt) — mêmes règles d'abonnement
          Row(children: [
            const Icon(Icons.point_of_sale_rounded,
                size: 14, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              '$maxCaisses caisse${maxCaisses != 1 ? 's' : ''} de base (1 par dépôt)',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            Text('${xCaisseHtg.toStringAsFixed(0)} HTG / caisse / mois',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ]),
          if (extraCaisses > 0) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.point_of_sale_rounded,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                '$extraCaisses caisse${extraCaisses != 1 ? 's' : ''} supplémentaire${extraCaisses != 1 ? 's' : ''}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              Text('${xCaisseHtg.toStringAsFixed(0)} HTG / caisse / mois',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ]),
          ],
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.warehouse_rounded,
                size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text('$curDepots dépôt${curDepots != 1 ? 's' : ''}',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500)),
            const Spacer(),
            const Text('Illimités — sans surcharge',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ]),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total / mois',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              Text(
                '${totalHtg.toStringAsFixed(0)} HTG',
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.primary),
              ),
            ],
          ),

          // ── Détail par caisse (accordion) ──────────────────────────────
          if (registers.isNotEmpty) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: () => setState(() => _showRegisters = !_showRegisters),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Icon(
                    _showRegisters
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _showRegisters
                        ? 'Masquer le détail'
                        : 'Détail par caisse (${registers.length})',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ]),
              ),
            ),
            if (_showRegisters) ...[
              const SizedBox(height: 8),
              ...byWh.entries.map((entry) => _RegisterUsageGroup(
                    warehouseName: entry.key,
                    registers: entry.value,
                  )),
            ],
          ],
        ],
      ),
    );
  }
}

// ── Groupe de caisses dans le plan usage ─────────────────────────────────────

class _RegisterUsageGroup extends StatelessWidget {
  final String warehouseName;
  final List<Map<String, dynamic>> registers;
  const _RegisterUsageGroup(
      {required this.warehouseName, required this.registers});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            warehouseName,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                letterSpacing: 0.3),
          ),
        ),
        ...registers.map((r) {
          final name       = r['name'] as String? ?? '';
          final isInitial  = r['is_initial'] as bool? ?? false;
          final status     = r['status'] as String? ?? '';
          final monthlyHtg = (r['monthly_htg'] as num? ?? 0).toDouble();

          final (statusLabel, statusColor) = switch (status) {
            'included'        => ('Incluse', AppColors.success),
            'trial'           => ('Essai', AppColors.accent),
            'active'          => ('Active', AppColors.success),
            'expired'         => ('Expiré', AppColors.error),
            'no_subscription' => ('Sans abonnement', AppColors.error),
            _                 => (status, AppColors.textSecondary),
          };

          final subStartedAt = _parseDate(r['subscription_started_at'] as String?);
          final expiry = _parseDate(r['subscription_ends_at'] as String?)
              ?? _parseDate(r['trial_ends_at'] as String?);
          final daysLeft = expiry?.toUtc().difference(haitiNow().toUtc()).inDays;

          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(Icons.point_of_sale_rounded,
                    size: 13,
                    color: isInitial
                        ? AppColors.primary
                        : AppColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500)),
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(statusLabel,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: statusColor,
                                  fontWeight: FontWeight.w600)),
                        ),
                        if (subStartedAt != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            'depuis ${DateFormat('dd/MM/yy').format(subStartedAt.toLocal())}',
                            style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondary),
                          ),
                        ],
                        if (expiry != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            'exp. ${DateFormat('dd/MM/yy').format(expiry.toLocal())}'
                            '${daysLeft != null ? ' (${daysLeft < 0 ? 'expiré' : '$daysLeft j'})' : ''}',
                            style: TextStyle(
                                fontSize: 10,
                                color: daysLeft != null && daysLeft <= 5
                                    ? AppColors.error
                                    : daysLeft != null && daysLeft <= 30
                                        ? Colors.orange
                                        : AppColors.textSecondary),
                          ),
                        ],
                      ]),
                    ],
                  ),
                ),
                Text(
                  monthlyHtg == 0
                      ? '— HTG'
                      : '${monthlyHtg.toStringAsFixed(0)} HTG/mois',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: monthlyHtg == 0
                          ? AppColors.textSecondary
                          : AppColors.textPrimary),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 4),
      ],
    );
  }

  DateTime? _parseDate(String? s) =>
      s != null ? DateTime.tryParse(s) : null;
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

// ══════════════════════════════════════════════════════════════════════════════
//  Section paiement par caisse (caisses supplémentaires uniquement)
// ══════════════════════════════════════════════════════════════════════════════

class _RegisterPaymentSection extends ConsumerStatefulWidget {
  final double pricePerCaisse;
  final double annualDiscountPct;
  final bool cashEnabled;
  final bool moncashEnabled;
  final bool natcashEnabled;
  final bool cardEnabled;

  const _RegisterPaymentSection({
    required this.pricePerCaisse,
    required this.annualDiscountPct,
    this.cashEnabled = true,
    this.moncashEnabled = true,
    this.natcashEnabled = true,
    this.cardEnabled = true,
  });

  @override
  ConsumerState<_RegisterPaymentSection> createState() =>
      _RegisterPaymentSectionState();
}

class _RegisterPaymentSectionState
    extends ConsumerState<_RegisterPaymentSection> {
  Set<String> _selected = {};
  String _planType = 'monthly';
  int _months = 1;
  late String _method;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _method = widget.cashEnabled
        ? 'cash'
        : widget.moncashEnabled
            ? 'moncash'
            : widget.natcashEnabled
                ? 'natcash'
                : 'cash';
    // Pré-sélection depuis la page Dépôts&Caisses (bouton "Payer" par caisse).
    final preSelected = ref.read(preSelectedRegisterIdsProvider);
    if (preSelected.isNotEmpty) {
      _selected = Set.from(preSelected);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(preSelectedRegisterIdsProvider.notifier).state = [];
      });
    }
  }

  double get _totalAmount {
    final n = _selected.length.toDouble();
    if (_planType == 'annual') {
      return widget.pricePerCaisse * 12 * n *
          (1 - widget.annualDiscountPct / 100);
    }
    return widget.pricePerCaisse * _months * n;
  }

  Future<void> _submit() async {
    if (_selected.isEmpty) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await dio.post('/api/billing/submit-register-payment', data: {
        'register_ids': _selected.toList(),
        'method': _method,
        'months': _months,
        'plan_type': _planType,
      });
      ref.invalidate(_billingPaymentsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Demande de paiement soumise — en attente de confirmation admin.'),
          backgroundColor: AppColors.success,
        ));
        setState(() => _selected = {});
      }
    } catch (e) {
      setState(() {
        _error = e is DioException
            ? extractErrorMessage(e)
            : e.toString();
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// La carte bancaire (Stripe) n'a pas de flux "demande manuelle par
  /// caisse" — c'est un abonnement global, payé et activé immédiatement via
  /// un checkout externe (contrairement à cash/MonCash/NatCash qui créent
  /// une demande "pending" pour validation admin).
  Future<void> _launchStripeCheckout() async {
    try {
      final res = await dio.post('/api/billing/checkout/stripe');
      final url = res.data['checkout_url'] as String?;
      if (url != null) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e is DioException
            ? extractErrorMessage(e)
            : 'Paiement par carte indisponible pour le moment.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final whRegsAsync = ref.watch(_allWarehouseRegistersProvider);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── En-tête section ────────────────────────────────────────────
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.point_of_sale_rounded,
                  color: AppColors.primary, size: 18),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Payer vos caisses',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(
                      'Chaque caisse a sa propre période d\'abonnement.',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 16),

          // ── Plan type ─────────────────────────────────────────────────
          SegmentedButton<String>(
            segments: [
              const ButtonSegment(
                  value: 'monthly',
                  label: Text('Mensuel'),
                  icon: Icon(Icons.calendar_today, size: 14)),
              ButtonSegment(
                  value: 'annual',
                  label: Text(
                      'Annuel −${widget.annualDiscountPct.toStringAsFixed(0)}%'),
                  icon: const Icon(Icons.event_available, size: 14)),
            ],
            selected: {_planType},
            onSelectionChanged: (s) =>
                setState(() => _planType = s.first),
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
            ),
          ),

          // ── Durée (mensuel) ────────────────────────────────────────────
          if (_planType == 'monthly') ...[
            const SizedBox(height: 10),
            Row(children: [
              const Text('Durée :',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(width: 10),
              ...[1, 3, 6].map((m) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text('$m mois'),
                      selected: _months == m,
                      onSelected: (_) => setState(() => _months = m),
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      selectedColor: AppColors.primary.withValues(alpha: 0.15),
                      labelStyle: TextStyle(
                        fontSize: 11,
                        color: _months == m
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        fontWeight: _months == m
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  )),
            ]),
          ],

          // ── Méthode de paiement ─────────────────────────────────────────
          // Les 4 méthodes sont toujours visibles ; celles désactivées par
          // la plateforme restent affichées mais non cliquables (grisées).
          const SizedBox(height: 10),
          Row(children: [
            const Text('Méthode :',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(width: 10),
            ...[
              ('cash', 'Espèces', widget.cashEnabled),
              ('moncash', 'MonCash', widget.moncashEnabled),
              ('natcash', 'NatCash', widget.natcashEnabled),
              ('card', 'Carte', widget.cardEnabled),
            ].map((m) {
              final (value, label, enabled) = m;
              // "Carte" n'a pas de flux de demande manuelle par caisse — elle
              // déclenche directement le checkout Stripe (abonnement global).
              final isCard = value == 'card';
              final active = !isCard && _method == value;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(label),
                  selected: active,
                  onSelected: !enabled
                      ? null
                      : (_) {
                          if (isCard) {
                            _launchStripeCheckout();
                          } else {
                            setState(() => _method = value);
                          }
                        },
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  selectedColor: AppColors.primary.withValues(alpha: 0.15),
                  labelStyle: TextStyle(
                    fontSize: 11,
                    color: !enabled
                        ? AppColors.textSecondary.withValues(alpha: 0.4)
                        : (active ? AppColors.primary : AppColors.textSecondary),
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              );
            }),
          ]),

          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // ── Liste des caisses par warehouse ────────────────────────────
          whRegsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            ),
            error: (e, _) => Text('Erreur : $e',
                style:
                    const TextStyle(color: AppColors.error, fontSize: 12)),
            data: (whRegs) {
              final groups = whRegs
                  .map((w) => _WhWithRegs(
                      w.warehouse,
                      w.registers.where((r) => r.isActive).toList()))
                  .where((w) => w.registers.isNotEmpty)
                  .toList();

              if (groups.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                      'Aucune caisse active.',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary)),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: groups
                    .map((g) => _WhRegisterGroup(
                          group: g,
                          selected: _selected,
                          onToggle: (id, checked) => setState(() {
                            if (checked) {
                              _selected.add(id);
                            } else {
                              _selected.remove(id);
                            }
                          }),
                        ))
                    .toList(),
              );
            },
          ),

          // ── Total + bouton soumettre ───────────────────────────────────
          if (_selected.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_selected.length} caisse${_selected.length > 1 ? 's' : ''}'
                  ' × ${_planType == 'annual' ? '12 mois −${widget.annualDiscountPct.toStringAsFixed(0)}%' : '$_months mois'}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                Text(
                  '${_totalAmount.toStringAsFixed(0)} HTG',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!,
                    style: const TextStyle(
                        color: AppColors.error, fontSize: 12)),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(42)),
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text(
                        'Soumettre le paiement — ${_totalAmount.toStringAsFixed(0)} HTG'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Groupe de caisses par dépôt ───────────────────────────────────────────────

// ══════════════════════════════════════════════════════════════════════════════
//  Section paiement par entrepôt (pas d'essai gratuit, contrairement aux caisses)
// ══════════════════════════════════════════════════════════════════════════════

class _EntrepotPaymentSection extends ConsumerStatefulWidget {
  final double pricePerEntrepot;
  final double annualDiscountPct;
  final bool cashEnabled;
  final bool moncashEnabled;
  final bool natcashEnabled;

  const _EntrepotPaymentSection({
    required this.pricePerEntrepot,
    required this.annualDiscountPct,
    this.cashEnabled = true,
    this.moncashEnabled = true,
    this.natcashEnabled = true,
  });

  @override
  ConsumerState<_EntrepotPaymentSection> createState() =>
      _EntrepotPaymentSectionState();
}

class _EntrepotPaymentSectionState
    extends ConsumerState<_EntrepotPaymentSection> {
  Set<String> _selected = {};
  String _planType = 'monthly';
  int _months = 1;
  late String _method;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _method = widget.cashEnabled
        ? 'cash'
        : widget.moncashEnabled
            ? 'moncash'
            : widget.natcashEnabled
                ? 'natcash'
                : 'cash';
  }

  double get _totalAmount {
    final n = _selected.length.toDouble();
    if (_planType == 'annual') {
      return widget.pricePerEntrepot * 12 * n *
          (1 - widget.annualDiscountPct / 100);
    }
    return widget.pricePerEntrepot * _months * n;
  }

  Future<void> _submit() async {
    if (_selected.isEmpty) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await dio.post('/api/billing/submit-entrepot-payment', data: {
        'entrepot_ids': _selected.toList(),
        'method': _method,
        'months': _months,
        'plan_type': _planType,
      });
      ref.invalidate(_billingPaymentsProvider);
      ref.invalidate(entrepotsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Demande de paiement soumise — en attente de confirmation admin.'),
          backgroundColor: AppColors.success,
        ));
        setState(() => _selected = {});
      }
    } catch (e) {
      setState(() {
        _error = e is DioException
            ? extractErrorMessage(e)
            : e.toString();
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entrepotsAsync = ref.watch(entrepotsProvider);

    return entrepotsAsync.maybeWhen(
      data: (list) => list.isEmpty,
      orElse: () => false,
    )
        ? const SizedBox.shrink() // pas d'entrepôt configuré — rien à payer
        : _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── En-tête section ────────────────────────────────────────
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.warehouse_rounded,
                        color: AppColors.primary, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Payer vos entrepôts',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        Text(
                            'Pas d\'essai gratuit — la distribution est bloquée tant que non payé.',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 16),

                // ── Plan type ─────────────────────────────────────────────
                SegmentedButton<String>(
                  segments: [
                    const ButtonSegment(
                        value: 'monthly',
                        label: Text('Mensuel'),
                        icon: Icon(Icons.calendar_today, size: 14)),
                    ButtonSegment(
                        value: 'annual',
                        label: Text(
                            'Annuel −${widget.annualDiscountPct.toStringAsFixed(0)}%'),
                        icon: const Icon(Icons.event_available, size: 14)),
                  ],
                  selected: {_planType},
                  onSelectionChanged: (s) =>
                      setState(() => _planType = s.first),
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                ),

                // ── Durée (mensuel) ───────────────────────────────────────
                if (_planType == 'monthly') ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    const Text('Durée :',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(width: 10),
                    ...[1, 3, 6].map((m) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            label: Text('$m mois'),
                            selected: _months == m,
                            onSelected: (_) => setState(() => _months = m),
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                            selectedColor: AppColors.primary.withValues(alpha: 0.15),
                            labelStyle: TextStyle(
                              fontSize: 11,
                              color: _months == m
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                              fontWeight: _months == m
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        )),
                  ]),
                ],

                // ── Méthode de paiement ───────────────────────────────────
                const SizedBox(height: 10),
                Row(children: [
                  const Text('Méthode :',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(width: 10),
                  ...[
                    ('cash', 'Espèces', widget.cashEnabled),
                    ('moncash', 'MonCash', widget.moncashEnabled),
                    ('natcash', 'NatCash', widget.natcashEnabled),
                  ].map((m) {
                    final (value, label, enabled) = m;
                    final active = _method == value;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(label),
                        selected: active,
                        onSelected: !enabled
                            ? null
                            : (_) => setState(() => _method = value),
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        selectedColor: AppColors.primary.withValues(alpha: 0.15),
                        labelStyle: TextStyle(
                          fontSize: 11,
                          color: !enabled
                              ? AppColors.textSecondary.withValues(alpha: 0.4)
                              : (active ? AppColors.primary : AppColors.textSecondary),
                          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    );
                  }),
                ]),

                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // ── Liste des entrepôts ───────────────────────────────────
                entrepotsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))),
                  ),
                  error: (e, _) => Text('Erreur : $e',
                      style: const TextStyle(color: AppColors.error, fontSize: 12)),
                  data: (entrepots) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: entrepots.map((e) {
                      final isSelected = _selected.contains(e.id);
                      final paid = e.isSubscriptionActive;
                      final statusStr = paid
                          ? 'Payé jusqu\'au ${DateFormat('dd/MM/yy').format(e.subscriptionEndsAt!)}'
                          : 'Non payé';
                      return CheckboxListTile(
                        dense: true,
                        value: isSelected,
                        onChanged: (v) => setState(() {
                          if (v ?? false) {
                            _selected.add(e.id);
                          } else {
                            _selected.remove(e.id);
                          }
                        }),
                        title: Text(e.name,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500)),
                        subtitle: Text(statusStr,
                            style: TextStyle(
                                fontSize: 11,
                                color: paid ? AppColors.success : AppColors.error)),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: AppColors.primary,
                      );
                    }).toList(),
                  ),
                ),

                // ── Total + bouton soumettre ──────────────────────────────
                if (_selected.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_selected.length} entrepôt${_selected.length > 1 ? 's' : ''}'
                        ' × ${_planType == 'annual' ? '12 mois −${widget.annualDiscountPct.toStringAsFixed(0)}%' : '$_months mois'}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                      Text(
                        '${_totalAmount.toStringAsFixed(0)} HTG',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(_error!,
                          style: const TextStyle(
                              color: AppColors.error, fontSize: 12)),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _submitting ? null : _submit,
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(42)),
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : Text(
                              'Soumettre le paiement — ${_totalAmount.toStringAsFixed(0)} HTG'),
                    ),
                  ),
                ],
              ],
            ),
          );
  }
}

class _WhRegisterGroup extends StatelessWidget {
  final _WhWithRegs group;
  final Set<String> selected;
  final void Function(String id, bool checked) onToggle;

  const _WhRegisterGroup({
    required this.group,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            group.warehouse.name,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                letterSpacing: 0.3),
          ),
        ),
        ...group.registers.map((reg) {
          final isSelected = selected.contains(reg.id);
          final expiry = reg.effectiveExpiry;
          final daysLeft = reg.daysLeft;
          final expiryColor = daysLeft == null
              ? AppColors.textSecondary
              : daysLeft <= 5
                  ? AppColors.error
                  : daysLeft <= 30
                      ? Colors.orange
                      : AppColors.success;
          final expiryStr = expiry == null
              ? ''
              : '${reg.isTrial ? 'Essai ' : ''}exp. ${DateFormat('dd/MM/yy').format(expiry.toLocal())} (${daysLeft != null && daysLeft < 0 ? 'expiré' : '$daysLeft j'})';

          return CheckboxListTile(
            dense: true,
            value: isSelected,
            onChanged: (v) => onToggle(reg.id, v ?? false),
            title: Text(reg.name,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            subtitle: expiryStr.isEmpty
                ? null
                : Text(expiryStr,
                    style: TextStyle(fontSize: 11, color: expiryColor)),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: AppColors.primary,
          );
        }),
        const SizedBox(height: 4),
      ],
    );
  }
}
