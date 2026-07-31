import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/sale_model.dart';
import 'package:pos_connect/providers/settings_provider.dart';

String _fmtQty(double q) =>
    q % 1 == 0 ? q.toInt().toString() : q.toStringAsFixed(2);

/// Generates a thermal receipt PDF for [sale].
/// Page width adapts to [AppSettings.paperWidth] (80 mm or 58 mm).
Future<Uint8List> buildReceiptPdf(SaleModel sale, AppSettings settings) async {
  final doc = pw.Document();

  // Polices intégrées — pas de réseau, pas de timeout, strokes épais
  final font     = pw.Font.helvetica();
  final fontBold = pw.Font.helveticaBold();

  // Fetch logo bytes (ignore errors — logo is optional)
  pw.MemoryImage? logoImage;
  if (settings.logoPath.isNotEmpty) {
    try {
      final res = await dio
          .get(settings.logoPath, options: Options(responseType: ResponseType.bytes))
          .timeout(const Duration(seconds: 5));
      logoImage = pw.MemoryImage(Uint8List.fromList(res.data as List<int>));
    } catch (_) {}
  }

  final numFmt =
      NumberFormat.currency(locale: 'fr_HT', symbol: '', decimalDigits: 2);
  final dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  // 80 mm ≈ 226 pt  |  58 mm ≈ 164 pt  |  48 mm ≈ 136 pt
  final pageWidth = settings.paperWidth == 58 ? 164.0
                  : settings.paperWidth == 48 ? 136.0
                  : 226.0;
  // 4 colonnes : ARTICLE (flex) | QTÉ (fixe) | P.U. (fixe) | TOTAL (fixe)
  final qtyColW   = settings.paperWidth == 58 ? 18.0
                  : settings.paperWidth == 48 ? 14.0
                  : 24.0;
  final puColW    = settings.paperWidth == 58 ? 32.0
                  : settings.paperWidth == 48 ? 26.0
                  : 44.0;
  final totalColW = settings.paperWidth == 58 ? 46.0
                  : settings.paperWidth == 48 ? 36.0
                  : 62.0;

  // Noir pur pour impression bureau — receiptDarkness n'agit que sur Sunmi
  const inkColor = PdfColors.black;

  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat(pageWidth, double.infinity, marginAll: 8),
    build: (ctx) {
      final base  = pw.TextStyle(font: font,    fontSize: settings.paperWidth == 48 ? 7.0 : 8.0,  color: inkColor);
      final bold  = pw.TextStyle(font: fontBold, fontSize: settings.paperWidth == 48 ? 7.0 : 8.0,  color: inkColor);
      final small = pw.TextStyle(font: font,    fontSize: settings.paperWidth == 48 ? 6.0 : 7.0,  color: inkColor);
      final title = pw.TextStyle(font: fontBold, fontSize: settings.paperWidth == 48 ? 9.0 : 11.0, color: inkColor);
      final sym   = settings.currencySymbol;

      pw.Widget divider() =>
          pw.Divider(thickness: 0.5, color: PdfColors.black);

      pw.Widget totalRow(String label, String value, {bool isBold = false}) =>
          pw.Row(children: [
            pw.Expanded(child: pw.Text(label, style: isBold ? bold : base)),
            pw.Text(value, style: isBold ? bold : base),
          ]);

      // 4 colonnes : ARTICLE (flex) | QTÉ (fixe) | P.U. (fixe) | TOTAL (fixe)
      pw.Widget itemsTable() => pw.Table(
            columnWidths: {
              0: pw.FlexColumnWidth(),
              1: pw.FixedColumnWidth(qtyColW),
              2: pw.FixedColumnWidth(puColW),
              3: pw.FixedColumnWidth(totalColW),
            },
            children: [
              pw.TableRow(children: [
                pw.Text('ARTICLE', style: bold),
                pw.Center(child: pw.Text('QTÉ', style: bold)),
                pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Text('P.U.', style: bold)),
                pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Text('TOTAL', style: bold)),
              ]),
              pw.TableRow(children: [
                pw.SizedBox(height: 3),
                pw.SizedBox(height: 3),
                pw.SizedBox(height: 3),
                pw.SizedBox(height: 3),
              ]),
              ...sale.items.map((item) => pw.TableRow(children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 1),
                      child: pw.Text(item.productName ?? '', style: base),
                    ),
                    pw.Center(
                      child: pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 1),
                        child: pw.Text(_fmtQty(item.quantity), style: base),
                      ),
                    ),
                    pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 1),
                        child: pw.Text(numFmt.format(item.unitPrice), style: base),
                      ),
                    ),
                    pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 1),
                        child: pw.Text(numFmt.format(item.subtotal), style: bold),
                      ),
                    ),
                  ])),
            ],
          );

      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // ── En-tête : logo + infos entreprise ──────────────────────────
          if (logoImage != null) ...[
            pw.Center(
                child: pw.Image(logoImage,
                    height: settings.paperWidth == 48 ? 30 : settings.paperWidth == 58 ? 40 : 50,
                    fit: pw.BoxFit.contain)),
            pw.SizedBox(height: 4),
          ],
          pw.Center(child: pw.Text(settings.businessName, style: title)),
          if (settings.address.isNotEmpty)
            pw.Center(child: pw.Text(settings.address, style: small)),
          if (settings.phone.isNotEmpty)
            pw.Center(child: pw.Text('Tél: ${settings.phone}', style: small)),
          pw.SizedBox(height: 4),
          divider(),

          // ── Infos vente ────────────────────────────────────────────────
          pw.Text('Réf: ${sale.reference}', style: base),
          pw.Text('Date: ${dateFmt.format(sale.createdAt)}', style: base),
          if (sale.customerName != null)
            pw.Text('Client: ${sale.customerName}', style: base),
          if (sale.userFullName != null)
            pw.Text('Caissier: ${sale.userFullName}', style: base),
          divider(),

          // ── Articles ───────────────────────────────────────────────────
          itemsTable(),
          divider(),

          // ── Totaux ─────────────────────────────────────────────────────
          // Remises articles : écart original_price / unit_price
          // Remise caisse    : rabais global saisi à la caisse
          ...() {
            final itemsDisc = sale.totalItemsDiscount;
            final catalogItemsDisc = sale.totalCatalogItemDiscount;
            final hasDisc = itemsDisc > 0.001 ||
                catalogItemsDisc > 0.001 ||
                sale.discount > 0.001;
            if (!hasDisc) return <pw.Widget>[];
            return [
              totalRow('Sous-total',
                  '$sym${numFmt.format(sale.totalAmount + itemsDisc)}'),
              if (itemsDisc > 0.001)
                totalRow('Remises articles',
                    '-$sym${numFmt.format(itemsDisc)}'),
              if (catalogItemsDisc > 0.001)
                totalRow('Rabais articles (catalogue)',
                    '-$sym${numFmt.format(catalogItemsDisc)}'),
              if (sale.discount > 0.001)
                totalRow(
                    sale.discountName != null
                        ? 'Remise caisse (${sale.discountName})'
                        : 'Remise caisse',
                    '-$sym${numFmt.format(sale.discount)}'),
            ];
          }(),
          totalRow('TOTAL', '$sym${numFmt.format(sale.finalAmount)}',
              isBold: true),
          pw.SizedBox(height: 2),
          ...() {
            // change_due (create_sale) plafonne paidAmount au montant dû et
            // stocke l'excédent séparément ; les ventes modifiées (update_sale)
            // peuvent encore rendre paidAmount > finalAmount directement.
            final change = sale.changeDue > 0.001
                ? sale.changeDue
                : (sale.balance < -0.001 ? -sale.balance : 0.0);
            final tendered =
                sale.changeDue > 0.001 ? sale.paidAmount + sale.changeDue : sale.paidAmount;
            return [
              totalRow('Montant reçu', '$sym${numFmt.format(tendered)}'),
              if (sale.balance > 0.001)
                totalRow('Reste à payer', '$sym${numFmt.format(sale.balance)}'),
              if (change > 0.001)
                totalRow('Monnaie', '$sym${numFmt.format(change)}'),
            ];
          }(),
          if (sale.loyaltyEarned > 0.001 || sale.loyaltyRedeemed > 0.001) ...[
            pw.SizedBox(height: 2),
            if (sale.loyaltyRedeemed > 0.001)
              totalRow('Fidélité utilisée',
                  '-$sym${numFmt.format(sale.loyaltyRedeemed)}'),
            if (sale.loyaltyEarned > 0.001)
              totalRow('Fidélité gagnée',
                  '+$sym${numFmt.format(sale.loyaltyEarned)}'),
          ],
          divider(),

          // ── Statut ─────────────────────────────────────────────────────
          pw.Center(
            child: pw.Text(
              switch (sale.status) {
                'PAID'    => '*** PAYÉ ***',
                'PARTIAL' => '*** PAIEMENT PARTIEL ***',
                _         => '*** NON PAYÉ ***',
              },
              style: bold,
            ),
          ),

          // ── Pied de page ───────────────────────────────────────────────
          if (settings.receiptFooter.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            divider(),
            pw.Center(child: pw.Text(settings.receiptFooter, style: small)),
          ],
        ],
      );
    },
  ));

  return doc.save();
}
