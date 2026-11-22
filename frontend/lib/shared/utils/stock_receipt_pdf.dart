import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:pos_connect/data/models/price_tier_change_model.dart';
import 'package:pos_connect/data/models/price_tier_model.dart';
import 'package:pos_connect/data/models/product_model.dart';
import 'package:pos_connect/data/models/stock_movement_model.dart';
import 'package:pos_connect/providers/settings_provider.dart';
import 'package:pos_connect/services/logo_cache_service.dart';

/// Génère la "fiche de réception" (ou, avec [title], la fiche d'ajustement
/// de stock) imprimée automatiquement côté caisse quand de nouveaux
/// mouvements de stock arrivent par la synchronisation — le caissier doit
/// voir ce qui a changé sans avoir à aller vérifier manuellement.
Future<Uint8List> buildStockReceiptFichePdf(
  List<StockMovementModel> movements,
  AppSettings settings, {
  String title = 'FICHE DE RÉCEPTION',
}) async {
  final doc = pw.Document();

  final font     = pw.Font.helvetica();
  final fontBold = pw.Font.helveticaBold();

  pw.MemoryImage? logoImage;
  if (settings.showLogoOnReceipt) {
    final logoBytes = await LogoCacheService.instance.getLogoBytes(settings.logoPath);
    if (logoBytes != null) logoImage = pw.MemoryImage(logoBytes);
  }

  final qtyFmt  = NumberFormat('#,##0.##', 'fr');
  final dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  final pageWidth = settings.paperWidth == 58 ? 164.0
                  : settings.paperWidth == 48 ? 136.0
                  : 204.0;
  const inkColor = PdfColors.black;

  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat(pageWidth, double.infinity, marginAll: 8),
    build: (ctx) {
      final base  = pw.TextStyle(font: font,     fontSize: settings.paperWidth == 48 ? 7.0 : 8.0,  color: inkColor);
      final bold  = pw.TextStyle(font: fontBold, fontSize: settings.paperWidth == 48 ? 7.0 : 8.0,  color: inkColor);
      final small = pw.TextStyle(font: font,     fontSize: settings.paperWidth == 48 ? 6.0 : 7.0,  color: inkColor);
      final titleStyle = pw.TextStyle(font: fontBold, fontSize: settings.paperWidth == 48 ? 9.0 : 11.0, color: inkColor);
      final head  = pw.TextStyle(font: fontBold, fontSize: settings.paperWidth == 48 ? 8.0 : 10.0, color: inkColor);

      pw.Widget divider() => pw.Divider(thickness: 0.5, color: PdfColors.grey400);

      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(child: pw.Text(settings.businessName, style: titleStyle)),
          if (settings.address.isNotEmpty)
            pw.Center(child: pw.Text(settings.address, style: small)),
          if (logoImage != null) ...[
            pw.SizedBox(height: 4),
            pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Image(logoImage,
                    height: settings.paperWidth == 58 ? 40 : 50,
                    fit: pw.BoxFit.contain)),
          ],
          pw.SizedBox(height: 6),
          pw.Center(child: pw.Text(title, style: head)),
          pw.Center(child: pw.Text(dateFmt.format(movements.first.createdAt), style: small)),
          pw.SizedBox(height: 2),
          divider(),
          pw.Table(
            columnWidths: {
              0: pw.FlexColumnWidth(),
              1: pw.FixedColumnWidth(settings.paperWidth == 48 ? 28.0 : 36.0),
            },
            children: [
              pw.TableRow(children: [
                pw.Text('PRODUIT', style: bold),
                pw.Align(alignment: pw.Alignment.centerRight,
                    child: pw.Text('QTÉ', style: bold)),
              ]),
              pw.TableRow(children: [
                pw.SizedBox(height: 3),
                pw.SizedBox(height: 3),
              ]),
              ...movements.map((m) {
                final sign = m.quantity >= 0 ? '+' : '';
                return pw.TableRow(children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 1),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(m.productName ?? '—', style: base),
                          pw.Text(
                            '${m.sourceLabel.isNotEmpty ? m.sourceLabel : '—'} · ${dateFmt.format(m.createdAt)}',
                            style: pw.TextStyle(font: font, fontSize: 6, color: PdfColors.grey600),
                          ),
                        ],
                      ),
                    ),
                    pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 1),
                        child: pw.Text('$sign${qtyFmt.format(m.quantity)}', style: bold),
                      ),
                    ),
                  ]);
              }),
            ],
          ),
          pw.SizedBox(height: 4),
          divider(),
          pw.Row(children: [
            pw.Expanded(child: pw.Text('Total lignes', style: base)),
            pw.Text('${movements.length}', style: bold),
          ]),
        ],
      );
    },
  ));

  return doc.save();
}

/// Fiche avant/après imprimée côté caisse quand la synchro ramène un
/// changement de palier de prix — détecté en comparant deux relevés
/// successifs de /api/price-tiers, voir app.dart::_checkPriceTierChangeFiche.
Future<Uint8List> buildPriceTierChangeFichePdf(
  List<PriceTierChangeModel> changes,
  AppSettings settings,
) async {
  final doc = pw.Document();

  final font     = pw.Font.helvetica();
  final fontBold = pw.Font.helveticaBold();

  pw.MemoryImage? logoImage;
  if (settings.showLogoOnReceipt) {
    final logoBytes = await LogoCacheService.instance.getLogoBytes(settings.logoPath);
    if (logoBytes != null) logoImage = pw.MemoryImage(logoBytes);
  }

  final dateFmt = DateFormat('dd/MM/yyyy HH:mm');
  final sym = settings.currencySymbol.trim();
  String fmtTiers(List<PriceTier> tiers) => tiers.isEmpty
      ? '—'
      : tiers.map((t) {
          final qty = t.minQuantity % 1 == 0 ? t.minQuantity.toInt().toString() : t.minQuantity.toStringAsFixed(2);
          return '$qty+: ${t.price.toStringAsFixed(2)} $sym';
        }).join(', ');

  final pageWidth = settings.paperWidth == 58 ? 164.0
                  : settings.paperWidth == 48 ? 136.0
                  : 204.0;
  const inkColor = PdfColors.black;

  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat(pageWidth, double.infinity, marginAll: 8),
    build: (ctx) {
      final base  = pw.TextStyle(font: font,     fontSize: settings.paperWidth == 48 ? 7.0 : 8.0,  color: inkColor);
      final bold  = pw.TextStyle(font: fontBold, fontSize: settings.paperWidth == 48 ? 7.0 : 8.0,  color: inkColor);
      final small = pw.TextStyle(font: font,     fontSize: settings.paperWidth == 48 ? 6.0 : 7.0,  color: inkColor);
      final titleStyle = pw.TextStyle(font: fontBold, fontSize: settings.paperWidth == 48 ? 9.0 : 11.0, color: inkColor);
      final head  = pw.TextStyle(font: fontBold, fontSize: settings.paperWidth == 48 ? 8.0 : 10.0, color: inkColor);

      pw.Widget divider() => pw.Divider(thickness: 0.5, color: PdfColors.grey400);

      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(child: pw.Text(settings.businessName, style: titleStyle)),
          if (settings.address.isNotEmpty)
            pw.Center(child: pw.Text(settings.address, style: small)),
          if (logoImage != null) ...[
            pw.SizedBox(height: 4),
            pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Image(logoImage,
                    height: settings.paperWidth == 58 ? 40 : 50,
                    fit: pw.BoxFit.contain)),
          ],
          pw.SizedBox(height: 6),
          pw.Center(child: pw.Text('PALIERS DE PRIX MIS À JOUR', style: head)),
          pw.Center(child: pw.Text(dateFmt.format(changes.first.createdAt), style: small)),
          pw.SizedBox(height: 2),
          divider(),
          ...changes.expand((c) => [
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 3),
                  child: pw.Text(c.productName, style: bold),
                ),
                pw.Text('Avant: ${fmtTiers(c.oldTiers)}', style: base),
                pw.Text('Après: ${fmtTiers(c.newTiers)}', style: bold),
              ]),
          pw.SizedBox(height: 2),
          divider(),
        ],
      );
    },
  ));

  return doc.save();
}

/// Fiche imprimée côté caisse dès qu'un NOUVEAU produit est créé sur le
/// cloud pour ce dépôt — détectée via created_from sur GET /api/products/,
/// voir app.dart::_checkNewProductFiche (même principe universel que les
/// paliers de prix : pas de journal serveur dédié).
Future<Uint8List> buildNewProductFichePdf(
  List<ProductModel> products,
  AppSettings settings,
) async {
  final doc = pw.Document();

  final font     = pw.Font.helvetica();
  final fontBold = pw.Font.helveticaBold();

  pw.MemoryImage? logoImage;
  if (settings.showLogoOnReceipt) {
    final logoBytes = await LogoCacheService.instance.getLogoBytes(settings.logoPath);
    if (logoBytes != null) logoImage = pw.MemoryImage(logoBytes);
  }

  final dateFmt = DateFormat('dd/MM/yyyy HH:mm');
  final sym = settings.currencySymbol.trim();

  final pageWidth = settings.paperWidth == 58 ? 164.0
                  : settings.paperWidth == 48 ? 136.0
                  : 204.0;
  const inkColor = PdfColors.black;

  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat(pageWidth, double.infinity, marginAll: 8),
    build: (ctx) {
      final base  = pw.TextStyle(font: font,     fontSize: settings.paperWidth == 48 ? 7.0 : 8.0,  color: inkColor);
      final bold  = pw.TextStyle(font: fontBold, fontSize: settings.paperWidth == 48 ? 7.0 : 8.0,  color: inkColor);
      final small = pw.TextStyle(font: font,     fontSize: settings.paperWidth == 48 ? 6.0 : 7.0,  color: inkColor);
      final titleStyle = pw.TextStyle(font: fontBold, fontSize: settings.paperWidth == 48 ? 9.0 : 11.0, color: inkColor);
      final head  = pw.TextStyle(font: fontBold, fontSize: settings.paperWidth == 48 ? 8.0 : 10.0, color: inkColor);

      pw.Widget divider() => pw.Divider(thickness: 0.5, color: PdfColors.grey400);
      pw.Widget line(String label, String value) => pw.Row(
            children: [
              pw.SizedBox(width: 70, child: pw.Text(label, style: small)),
              pw.Expanded(child: pw.Text(value, style: base)),
            ],
          );

      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(child: pw.Text(settings.businessName, style: titleStyle)),
          if (settings.address.isNotEmpty)
            pw.Center(child: pw.Text(settings.address, style: small)),
          if (logoImage != null) ...[
            pw.SizedBox(height: 4),
            pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Image(logoImage,
                    height: settings.paperWidth == 58 ? 40 : 50,
                    fit: pw.BoxFit.contain)),
          ],
          pw.SizedBox(height: 6),
          pw.Center(child: pw.Text('NOUVEAU PRODUIT', style: head)),
          pw.SizedBox(height: 2),
          divider(),
          ...products.expand((p) => [
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 4),
                  child: pw.Text(p.name, style: bold),
                ),
                if (p.barcode != null && p.barcode!.isNotEmpty)
                  line('Code-barres', p.barcode!),
                line('Catégorie', p.category?.name ?? '—'),
                line('Type', p.isService
                    ? 'Service'
                    : p.isComposite
                        ? 'Composé (x${p.componentQuantity!.toStringAsFixed(0)} du composant)'
                        : 'Produit simple'),
                if (!p.isService) ...[
                  line('Prix de vente', '${p.salePrice.toStringAsFixed(2)} $sym'),
                  line('Prix d\'achat', '${p.purchasePrice.toStringAsFixed(2)} $sym'),
                  line('Stock initial', '${p.stock ?? 0}'),
                  line('Seuil d\'alerte', '${p.alertStock}'),
                ] else
                  line('Prix', '${p.salePrice.toStringAsFixed(2)} $sym'),
                if (p.description != null && p.description!.isNotEmpty)
                  line('Description', p.description!),
                line('Créé le', p.createdAt != null ? dateFmt.format(p.createdAt!) : '—'),
                pw.SizedBox(height: 2),
                divider(),
              ]),
        ],
      );
    },
  ));

  return doc.save();
}
