import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:pos_connect/data/models/stock_movement_model.dart';
import 'package:pos_connect/providers/settings_provider.dart';
import 'package:pos_connect/services/logo_cache_service.dart';

/// Génère la "fiche de réception" imprimée automatiquement côté caisse
/// quand de nouveaux mouvements de stock entrants (achats, ajustements,
/// transferts reçus…) arrivent par la synchronisation — le caissier doit
/// voir ce qui a été ajouté au dépôt sans avoir à aller vérifier manuellement.
Future<Uint8List> buildStockReceiptFichePdf(
  List<StockMovementModel> movements,
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
      final title = pw.TextStyle(font: fontBold, fontSize: settings.paperWidth == 48 ? 9.0 : 11.0, color: inkColor);
      final head  = pw.TextStyle(font: fontBold, fontSize: settings.paperWidth == 48 ? 8.0 : 10.0, color: inkColor);

      pw.Widget divider() => pw.Divider(thickness: 0.5, color: PdfColors.grey400);

      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(child: pw.Text(settings.businessName, style: title)),
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
          pw.Center(child: pw.Text('FICHE DE RÉCEPTION', style: head)),
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
              ...movements.map((m) => pw.TableRow(children: [
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
                        child: pw.Text('+${qtyFmt.format(m.quantity)}', style: bold),
                      ),
                    ),
                  ])),
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
