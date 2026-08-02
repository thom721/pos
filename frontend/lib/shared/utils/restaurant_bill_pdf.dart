import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pos_connect/core/date_utils.dart' show haitiNow;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:pos_connect/data/models/restaurant_model.dart';
import 'package:pos_connect/providers/settings_provider.dart';
import 'package:pos_connect/services/logo_cache_service.dart';

/// Génère un PDF addition/reçu pour une commande restaurant.
///
/// [reference] : null = addition (avant paiement), non-null = reçu (après)
/// [paidAmount], [discount], [tip] : renseignés après paiement seulement
Future<Uint8List> buildRestaurantBillPdf(
  RestaurantOrderModel order,
  AppSettings settings, {
  String? reference,
  double discount = 0,
  double paidAmount = 0,
  String? paymentMethod,
}) async {
  final doc = pw.Document();

  // Polices intégrées — pas de réseau, pas de timeout, strokes épais
  final font     = pw.Font.helvetica();
  final fontBold = pw.Font.helveticaBold();

  pw.MemoryImage? logoImage;
  final logoBytes = await LogoCacheService.instance.getLogoBytes(settings.logoPath);
  if (logoBytes != null) {
    logoImage = pw.MemoryImage(logoBytes);
  }

  final numFmt =
      NumberFormat.currency(locale: 'fr_HT', symbol: '', decimalDigits: 2);
  final dateFmt = DateFormat('dd/MM/yyyy HH:mm');
  final sym = settings.currencySymbol;
  final isPaid = reference != null;

  // 80 mm ≈ 226 pt  |  58 mm ≈ 164 pt  |  48 mm ≈ 136 pt
  final pageWidth = settings.paperWidth == 58 ? 164.0
                  : settings.paperWidth == 48 ? 136.0
                  : 226.0;
  final qtyW   = settings.paperWidth == 58 ? 18.0
               : settings.paperWidth == 48 ? 14.0
               : 24.0;
  final totalW = settings.paperWidth == 58 ? 46.0
               : settings.paperWidth == 48 ? 36.0
               : 62.0;

  const inkColor = PdfColors.black;

  final tip = order.tip;
  final subtotal = order.subtotal;
  final total = order.total;
  final finalTotal = total - discount;
  final change = isPaid ? (paidAmount - finalTotal).clamp(0, double.infinity) : 0.0;

  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat(pageWidth, double.infinity, marginAll: 8),
    build: (ctx) {
      final base  = pw.TextStyle(font: font,    fontSize: settings.paperWidth == 48 ? 7.0 : 8.0,  color: inkColor);
      final bold  = pw.TextStyle(font: fontBold, fontSize: settings.paperWidth == 48 ? 7.0 : 8.0,  color: inkColor);
      final small = pw.TextStyle(font: font,    fontSize: settings.paperWidth == 48 ? 6.0 : 7.0,  color: inkColor);
      final title = pw.TextStyle(font: fontBold, fontSize: settings.paperWidth == 48 ? 9.0 : 11.0, color: inkColor);
      final head  = pw.TextStyle(font: fontBold, fontSize: settings.paperWidth == 48 ? 8.0 : 10.0, color: inkColor);

      pw.Widget divider() =>
          pw.Divider(thickness: 0.5, color: PdfColors.grey400);

      pw.Widget totalRow(String label, String value,
              {bool isBold = false}) =>
          pw.Row(children: [
            pw.Expanded(child: pw.Text(label, style: isBold ? bold : base)),
            pw.Text(value, style: isBold ? bold : base),
          ]);

      // 3 colonnes : ARTICLE (flex) | QTÉ (fixe) | TOTAL (fixe)
      pw.Widget itemsTable() => pw.Table(
            columnWidths: {
              0: pw.FlexColumnWidth(),
              1: pw.FixedColumnWidth(qtyW),
              2: pw.FixedColumnWidth(totalW),
            },
            children: [
              pw.TableRow(children: [
                pw.Text('ARTICLE', style: bold),
                pw.Center(child: pw.Text('QTÉ', style: bold)),
                pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Text('TOTAL', style: bold)),
              ]),
              pw.TableRow(children: [
                pw.SizedBox(height: 3),
                pw.SizedBox(height: 3),
                pw.SizedBox(height: 3),
              ]),
              ...order.items.map((item) {
                final name = item.productName;
                final noteText = item.notes != null && item.notes!.isNotEmpty
                    ? item.notes!
                    : null;
                return pw.TableRow(children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 1),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(name, style: base),
                        if (noteText != null)
                          pw.Text(noteText,
                              style: pw.TextStyle(
                                  font: font,
                                  fontSize: 7,
                                  color: PdfColors.grey600)),
                      ],
                    ),
                  ),
                  pw.Center(
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 1),
                      child: pw.Text(
                          item.quantity == item.quantity.truncateToDouble()
                              ? item.quantity.toInt().toString()
                              : item.quantity.toStringAsFixed(1),
                          style: base),
                    ),
                  ),
                  pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 1),
                      child: pw.Text(numFmt.format(item.subtotal), style: bold),
                    ),
                  ),
                ]);
              }),
            ],
          );

      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // ── En-tête ───────────────────────────────────────────────────
          if (logoImage != null) ...[
            pw.Center(
                child: pw.Image(logoImage,
                    height: settings.paperWidth == 58 ? 40 : 50,
                    fit: pw.BoxFit.contain)),
            pw.SizedBox(height: 4),
          ],
          pw.Center(
              child: pw.Text(settings.businessName, style: title)),
          if (settings.address.isNotEmpty)
            pw.Center(
                child: pw.Text(settings.address, style: small)),
          if (settings.phone.isNotEmpty)
            pw.Center(
                child: pw.Text('Tél: ${settings.phone}', style: small)),
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Text(
              isPaid ? 'REÇU' : 'ADDITION',
              style: head,
            ),
          ),
          pw.SizedBox(height: 2),
          divider(),

          // ── Infos commande ────────────────────────────────────────────
          if (reference != null)
            pw.Text('Réf: $reference', style: base),
          pw.Text('Date: ${dateFmt.format(haitiNow())}', style: base),
          if (order.tableName != null)
            pw.Text('Table: ${order.tableName}', style: base),
          if (order.waiterName != null)
            pw.Text('Serveur: ${order.waiterName}', style: base),
          pw.Text(
              'Couverts: ${order.covers}', style: base),
          divider(),

          // ── Articles ──────────────────────────────────────────────────
          itemsTable(),
          divider(),

          // ── Totaux ───────────────────────────────────────────────────
          totalRow('Sous-total', '$sym${numFmt.format(subtotal)}'),
          if (tip > 0)
            totalRow('Pourboire', '+$sym${numFmt.format(tip)}'),
          if (discount > 0)
            totalRow('Remise caisse', '-$sym${numFmt.format(discount)}'),
          totalRow('TOTAL',
              '$sym${numFmt.format(isPaid ? finalTotal : total)}',
              isBold: true),
          if (isPaid) ...[
            pw.SizedBox(height: 2),
            if (paymentMethod != null)
              totalRow(
                'Mode',
                switch (paymentMethod) {
                  'CARD' => 'Carte',
                  'TRANSFER' => 'Virement',
                  _ => 'Espèces',
                },
              ),
            totalRow('Reçu', '$sym${numFmt.format(paidAmount)}'),
            if (change > 0.001)
              totalRow('Monnaie', '$sym${numFmt.format(change)}',
                  isBold: true),
          ],
          divider(),

          if (isPaid)
            pw.Center(
                child: pw.Text('*** PAYÉ ***',
                    style: bold)),

          if (settings.receiptFooter.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            divider(),
            pw.Center(
                child:
                    pw.Text(settings.receiptFooter, style: small)),
          ],
        ],
      );
    },
  ));

  return doc.save();
}
