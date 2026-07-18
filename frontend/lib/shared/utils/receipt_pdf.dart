import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/sale_model.dart';
import 'package:pos_connect/providers/settings_provider.dart';

/// Generates a thermal receipt PDF for [sale].
/// Page width adapts to [AppSettings.paperWidth] (80 mm or 58 mm).
Future<Uint8List> buildReceiptPdf(SaleModel sale, AppSettings settings) async {
  final doc = pw.Document();

  final font = await PdfGoogleFonts.notoSansRegular()
      .timeout(const Duration(seconds: 4), onTimeout: () => pw.Font.helvetica());
  final fontBold = await PdfGoogleFonts.notoSansBold()
      .timeout(const Duration(seconds: 4), onTimeout: () => pw.Font.helveticaBold());

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

  // 80 mm ≈ 226 pt  |  58 mm ≈ 164 pt
  final pageWidth = settings.paperWidth == 58 ? 164.0 : 226.0;
  // Item table column widths scale with page
  final qtyColW  = settings.paperWidth == 58 ? 16.0 : 22.0;
  final priceColW = settings.paperWidth == 58 ? 36.0 : 54.0;
  final totalColW = settings.paperWidth == 58 ? 36.0 : 54.0;

  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat(pageWidth, double.infinity, marginAll: 8),
    build: (ctx) {
      final base  = pw.TextStyle(font: font,     fontSize: 8);
      final bold  = pw.TextStyle(font: fontBold,  fontSize: 8);
      final small = pw.TextStyle(font: font,     fontSize: 7);
      final title = pw.TextStyle(font: fontBold,  fontSize: 11);
      final sym   = settings.currencySymbol;

      pw.Widget divider() =>
          pw.Divider(thickness: 0.5, color: PdfColors.grey400);

      pw.Widget totalRow(String label, String value, {bool isBold = false}) =>
          pw.Row(children: [
            pw.Expanded(child: pw.Text(label, style: isBold ? bold : base)),
            pw.Text(value, style: isBold ? bold : base),
          ]);

      pw.Widget itemsTable() => pw.Table(
            columnWidths: {
              0: pw.FlexColumnWidth(),
              1: pw.FixedColumnWidth(qtyColW),
              2: pw.FixedColumnWidth(priceColW),
              3: pw.FixedColumnWidth(totalColW),
            },
            children: [
              pw.TableRow(children: [
                pw.Text('ARTICLE', style: bold),
                pw.Center(child: pw.Text('QTÉ', style: bold)),
                pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Text('PRIX', style: bold)),
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
                        child: pw.Text('${item.quantity.toInt()}', style: base),
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
                    height: settings.paperWidth == 58 ? 40 : 50,
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
          if (sale.discount > 0) ...[
            totalRow('Sous-total', '$sym${numFmt.format(sale.totalAmount)}'),
            totalRow('Remise', '-$sym${numFmt.format(sale.discount)}'),
          ],
          totalRow('TOTAL', '$sym${numFmt.format(sale.finalAmount)}',
              isBold: true),
          pw.SizedBox(height: 2),
          totalRow('Montant reçu', '$sym${numFmt.format(sale.paidAmount)}'),
          if (sale.balance.abs() > 0.001)
            totalRow(
              sale.balance > 0 ? 'Reste à payer' : 'Monnaie',
              '$sym${numFmt.format(sale.balance.abs())}',
            ),
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
