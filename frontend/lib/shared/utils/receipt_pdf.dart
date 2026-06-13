import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:pos_connect/data/models/sale_model.dart';
import 'package:pos_connect/providers/settings_provider.dart';

/// Generates an 80mm thermal receipt PDF for [sale].
Future<Uint8List> buildReceiptPdf(SaleModel sale, AppSettings settings) async {
  final doc = pw.Document();
  final font = await PdfGoogleFonts.notoSansRegular();
  final fontBold = await PdfGoogleFonts.notoSansBold();
  final numFmt =
      NumberFormat.currency(locale: 'fr_HT', symbol: '', decimalDigits: 2);
  final dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  const pageWidth = 226.0; // ~80 mm in points

  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat(pageWidth, double.infinity, marginAll: 8),
    build: (ctx) {
      final base = pw.TextStyle(font: font, fontSize: 8);
      final bold = pw.TextStyle(font: fontBold, fontSize: 8);
      final small = pw.TextStyle(font: font, fontSize: 7);
      final title = pw.TextStyle(font: fontBold, fontSize: 11);
      final sym = settings.currencySymbol;

      pw.Widget divider() =>
          pw.Divider(thickness: 0.5, color: PdfColors.grey400);

      pw.Widget totalRow(String label, String value,
              {bool isBold = false}) =>
          pw.Row(children: [
            pw.Expanded(child: pw.Text(label, style: isBold ? bold : base)),
            pw.Text(value, style: isBold ? bold : base),
          ]);

      // ── Items table with centered QTÉ and right-aligned PRIX/TOTAL ──────
      pw.Widget itemsTable() => pw.Table(
            columnWidths: const {
              0: pw.FlexColumnWidth(),
              1: pw.FixedColumnWidth(22),
              2: pw.FixedColumnWidth(54),
              3: pw.FixedColumnWidth(54),
            },
            children: [
              // Header row
              pw.TableRow(children: [
                pw.Text('ARTICLE', style: bold),
                pw.Center(child: pw.Text('QTÉ', style: bold)),
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text('PRIX', style: bold),
                ),
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text('TOTAL', style: bold),
                ),
              ]),
              // Spacer
              pw.TableRow(children: [
                pw.SizedBox(height: 3),
                pw.SizedBox(height: 3),
                pw.SizedBox(height: 3),
                pw.SizedBox(height: 3),
              ]),
              // Item rows
              ...sale.items.map((item) => pw.TableRow(children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 1),
                      child: pw.Text(item.productName ?? '', style: base),
                    ),
                    pw.Center(
                      child: pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 1),
                        child: pw.Text(
                            '${item.quantity.toInt()}',
                            style: base),
                      ),
                    ),
                    pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 1),
                        child: pw.Text(numFmt.format(item.unitPrice),
                            style: base),
                      ),
                    ),
                    pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 1),
                        child: pw.Text(numFmt.format(item.subtotal),
                            style: bold),
                      ),
                    ),
                  ])),
            ],
          );

      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // Business header
          pw.Center(child: pw.Text(settings.businessName, style: title)),
          if (settings.address.isNotEmpty)
            pw.Center(child: pw.Text(settings.address, style: small)),
          if (settings.phone.isNotEmpty)
            pw.Center(child: pw.Text('Tél: ${settings.phone}', style: small)),
          pw.SizedBox(height: 4),
          divider(),

          // Sale info
          pw.Text('Réf: ${sale.reference}', style: base),
          pw.Text('Date: ${dateFmt.format(sale.createdAt)}', style: base),
          if (sale.customerName != null)
            pw.Text('Client: ${sale.customerName}', style: base),
          if (sale.userFullName != null)
            pw.Text('Caissier: ${sale.userFullName}', style: base),
          divider(),

          // Items
          itemsTable(),
          divider(),

          // Totals
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

          // Status
          pw.Center(
            child: pw.Text(
              switch (sale.status) {
                'PAID' => '*** PAYÉ ***',
                'PARTIAL' => '*** PAIEMENT PARTIEL ***',
                _ => '*** NON PAYÉ ***',
              },
              style: bold,
            ),
          ),

          // Footer
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
