import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:pos_connect/data/models/return_model.dart';
import 'package:pos_connect/providers/settings_provider.dart';

/// Generates an 80 mm thermal receipt PDF for a sale return.
Future<Uint8List> buildReturnPdf(
  ReturnModel ret,
  AppSettings settings,
) async {
  final doc = pw.Document();
  final font = await PdfGoogleFonts.notoSansRegular();
  final fontBold = await PdfGoogleFonts.notoSansBold();
  final numFmt =
      NumberFormat.currency(locale: 'fr_HT', symbol: '', decimalDigits: 2);
  final dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  const pageWidth = 226.0; // ~80 mm

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

      pw.Widget itemsTable() => pw.Table(
            columnWidths: const {
              0: pw.FlexColumnWidth(),
              1: pw.FixedColumnWidth(22),
              2: pw.FixedColumnWidth(54),
            },
            children: [
              pw.TableRow(children: [
                pw.Text('ARTICLE', style: bold),
                pw.Center(child: pw.Text('QTÉ', style: bold)),
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text('TOTAL', style: bold),
                ),
              ]),
              pw.TableRow(children: [
                pw.SizedBox(height: 3),
                pw.SizedBox(height: 3),
                pw.SizedBox(height: 3),
              ]),
              ...ret.items.map((item) => pw.TableRow(children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 1),
                      child: pw.Text(item.productName, style: base),
                    ),
                    pw.Center(
                      child: pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 1),
                        child: pw.Text(
                            item.quantity % 1 == 0
                                ? item.quantity.toInt().toString()
                                : item.quantity.toStringAsFixed(2),
                            style: base),
                      ),
                    ),
                    pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 1),
                        child:
                            pw.Text(numFmt.format(item.subtotal), style: bold),
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
            pw.Center(
                child: pw.Text('Tél: ${settings.phone}', style: small)),
          pw.SizedBox(height: 4),
          divider(),

          // Receipt type + reference
          pw.Center(
              child: pw.Text('*** BON DE RETOUR ***', style: bold)),
          pw.SizedBox(height: 2),
          pw.Text('Réf: ${ret.docReference}', style: base),
          pw.Text('Date: ${dateFmt.format(ret.createdAt)}', style: base),
          divider(),

          // Items
          itemsTable(),
          divider(),

          // Totals
          totalRow(
            'Total retourné',
            '$sym${numFmt.format(ret.totalReturned)}',
            isBold: true,
          ),
          if (ret.refundAmount > 0)
            totalRow(
              'Montant remboursé',
              '$sym${numFmt.format(ret.refundAmount)}',
            ),

          // Reason
          if (ret.reason != null && ret.reason!.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text('Motif: ${ret.reason}', style: small),
          ],
          divider(),

          // Signature area
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text('_________________', style: small),
                  pw.Text('Client', style: small),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text('_________________', style: small),
                  pw.Text('Responsable', style: small),
                ],
              ),
            ],
          ),

          // Footer
          if (settings.receiptFooter.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            divider(),
            pw.Center(child: pw.Text(settings.receiptFooter, style: small)),
          ],
        ],
      );
    },
  ));

  return doc.save();
}
