import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:pos_connect/core/currency.dart';
import 'package:pos_connect/data/models/purchase_model.dart';
import 'package:pos_connect/providers/settings_provider.dart';
import 'package:pos_connect/services/logo_cache_service.dart';

/// Génère un reçu d'achat fournisseur au format lettre US (8.5x11 po) —
/// format bureau classique, distinct du petit ticket thermique des ventes
/// (receipt_pdf.dart), plus adapté à un document fournisseur archivé/imprimé
/// sur imprimante de bureau.
Future<Uint8List> buildPurchaseReceiptPdf(
  PurchaseModel purchase,
  AppSettings settings,
) async {
  final doc = pw.Document();
  final font     = pw.Font.helvetica();
  final fontBold = pw.Font.helveticaBold();

  pw.MemoryImage? logoImage;
  if (settings.showLogoOnReceipt) {
    final logoBytes = await LogoCacheService.instance.getLogoBytes(settings.logoPath);
    if (logoBytes != null) {
      logoImage = pw.MemoryImage(logoBytes);
    }
  }

  final numFmt =
      NumberFormat.currency(locale: 'fr_HT', symbol: '', decimalDigits: 2);
  final dateFmt = DateFormat('dd/MM/yyyy HH:mm');
  final sym = settings.currencySymbol;

  final base  = pw.TextStyle(font: font, fontSize: 10);
  final bold  = pw.TextStyle(font: fontBold, fontSize: 10);
  final small = pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey700);
  final title = pw.TextStyle(font: fontBold, fontSize: 20);
  final h2    = pw.TextStyle(font: fontBold, fontSize: 13);

  pw.Widget totalRow(String label, String value, {bool isBold = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.SizedBox(
                width: 140,
                child: pw.Text(label,
                    textAlign: pw.TextAlign.right,
                    style: isBold ? bold : base)),
            pw.SizedBox(width: 12),
            pw.SizedBox(
                width: 90,
                child: pw.Text(value,
                    textAlign: pw.TextAlign.right,
                    style: isBold ? bold : base)),
          ],
        ),
      );

  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.letter,
    margin: const pw.EdgeInsets.all(36),
    build: (ctx) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // ── En-tête ────────────────────────────────────────────────────
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (logoImage != null) ...[
                    pw.Image(logoImage, height: 40, fit: pw.BoxFit.contain),
                    pw.SizedBox(height: 6),
                  ],
                  pw.Text(settings.businessName, style: h2),
                  if (settings.address.isNotEmpty)
                    pw.Text(settings.address, style: small),
                  if (settings.phone.isNotEmpty)
                    pw.Text('Tél: ${settings.phone}', style: small),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('ACHAT', style: title),
                  pw.SizedBox(height: 4),
                  pw.Text('Réf: ${purchase.reference}', style: base),
                  pw.Text(dateFmt.format(purchase.createdAt), style: small),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Divider(thickness: 1, color: PdfColors.grey400),
          pw.SizedBox(height: 10),

          // ── Fournisseur ────────────────────────────────────────────────
          pw.Text('FOURNISSEUR', style: pw.TextStyle(font: fontBold, fontSize: 9, color: PdfColors.grey600)),
          pw.Text(purchase.supplierName ?? 'Achat informel — sans fournisseur', style: bold),
          if (purchase.userFullName != null && purchase.userFullName!.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text('Enregistré par: ${purchase.userFullName}', style: small),
          ],
          pw.SizedBox(height: 18),

          // ── Articles ───────────────────────────────────────────────────
          pw.Table(
            columnWidths: {
              0: const pw.FlexColumnWidth(),
              1: const pw.FixedColumnWidth(60),
              2: const pw.FixedColumnWidth(90),
              3: const pw.FixedColumnWidth(90),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                      bottom: pw.BorderSide(width: 1, color: PdfColors.black)),
                ),
                children: [
                  pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 4),
                      child: pw.Text('ARTICLE', style: bold)),
                  pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 4),
                      child: pw.Text('QTÉ', style: bold, textAlign: pw.TextAlign.center)),
                  pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 4),
                      child: pw.Text('PRIX UNIT.', style: bold, textAlign: pw.TextAlign.right)),
                  pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 4),
                      child: pw.Text('TOTAL', style: bold, textAlign: pw.TextAlign.right)),
                ],
              ),
              ...purchase.items.map((item) => pw.TableRow(children: [
                    pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 5),
                        child: pw.Text(item.productName ?? 'Produit', style: base)),
                    pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 5),
                        child: pw.Text(item.orderedQty.toStringAsFixed(
                            item.orderedQty % 1 == 0 ? 0 : 2),
                            textAlign: pw.TextAlign.center, style: base)),
                    pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 5),
                        child: pw.Text(
                            '$sym${numFmt.format(toDisplayAmount(item.unitPrice, settings))}',
                            textAlign: pw.TextAlign.right, style: base)),
                    pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 5),
                        child: pw.Text(
                            '$sym${numFmt.format(toDisplayAmount(item.subtotal, settings))}',
                            textAlign: pw.TextAlign.right, style: bold)),
                  ])),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Divider(thickness: 1, color: PdfColors.grey400),
          pw.SizedBox(height: 10),

          // ── Totaux ─────────────────────────────────────────────────────
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                totalRow('Total',
                    '$sym${numFmt.format(toDisplayAmount(purchase.totalAmount, settings))}',
                    isBold: true),
                totalRow('Payé',
                    '$sym${numFmt.format(toDisplayAmount(purchase.paidAmount, settings))}'),
                totalRow('Solde dû',
                    '$sym${numFmt.format(toDisplayAmount(purchase.balance, settings))}',
                    isBold: true),
              ],
            ),
          ),
          pw.SizedBox(height: 24),
          pw.Text(
            switch (purchase.status) {
              'paid'     => '*** PAYÉ ***',
              'partial'  => '*** PAIEMENT PARTIEL ***',
              'received' => '*** RÉCEPTIONNÉ ***',
              _          => '*** EN ATTENTE ***',
            },
            style: bold,
          ),

          if (settings.receiptFooter.isNotEmpty) ...[
            pw.SizedBox(height: 24),
            pw.Divider(thickness: 0.5, color: PdfColors.grey400),
            pw.SizedBox(height: 6),
            pw.Text(settings.receiptFooter, style: small),
          ],
        ],
      );
    },
  ));

  return doc.save();
}
