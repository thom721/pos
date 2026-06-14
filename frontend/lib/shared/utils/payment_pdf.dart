import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:pos_connect/providers/settings_provider.dart';

/// Generates an 80 mm thermal receipt PDF for a credit payment.
Future<Uint8List> buildPaymentPdf({
  required String partnerName,
  required String referenceLabel,   // e.g. "Vente VNT-00001"
  required double amountPaid,       // amount paid in this transaction
  required double totalDebt,        // total original debt
  required double previouslyPaid,   // amount already paid before this
  required double remainingAfter,   // balance remaining after this payment
  required String method,           // CASH | BANK | MOBILE | CARD
  required DateTime date,
  required AppSettings settings,
}) async {
  final doc = pw.Document();
  final font = await PdfGoogleFonts.notoSansRegular();
  final fontBold = await PdfGoogleFonts.notoSansBold();
  final numFmt =
      NumberFormat.currency(locale: 'fr_HT', symbol: '', decimalDigits: 2);
  final dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  const pageWidth = 226.0; // ~80 mm

  String methodLabel(String m) {
    switch (m.toUpperCase()) {
      case 'CASH':   return 'Espèces';
      case 'BANK':   return 'Virement bancaire';
      case 'MOBILE': return 'Mobile Money';
      case 'CARD':   return 'Carte bancaire';
      default:       return m;
    }
  }

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

      pw.Widget row(String label, String value,
              {bool isBold = false, PdfColor? valueColor}) =>
          pw.Row(children: [
            pw.Expanded(child: pw.Text(label, style: isBold ? bold : base)),
            pw.Text(value,
                style: (isBold ? bold : base).copyWith(color: valueColor)),
          ]);

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

          // Title
          pw.Center(
              child: pw.Text('REÇU DE PAIEMENT', style: bold)),
          pw.SizedBox(height: 2),
          pw.Text('Réf: $referenceLabel', style: base),
          pw.Text('Client: $partnerName', style: base),
          pw.Text('Date: ${dateFmt.format(date)}', style: base),
          pw.Text('Mode: ${methodLabel(method)}', style: base),
          divider(),

          // Payment detail
          row('Total de la dette', '$sym${numFmt.format(totalDebt)}'),
          row('Déjà payé', '$sym${numFmt.format(previouslyPaid)}'),
          pw.SizedBox(height: 3),
          row(
            'Montant encaissé',
            '$sym${numFmt.format(amountPaid)}',
            isBold: true,
          ),
          divider(),
          row(
            remainingAfter <= 0.001 ? 'Solde' : 'Reste à payer',
            '$sym${numFmt.format(remainingAfter.abs())}',
            isBold: remainingAfter <= 0.001,
            valueColor: remainingAfter <= 0.001
                ? PdfColors.green700
                : PdfColors.red700,
          ),
          divider(),

          // Status
          pw.Center(
            child: pw.Text(
              remainingAfter <= 0.001
                  ? '*** DETTE SOLDÉE ***'
                  : '*** PAIEMENT ENREGISTRÉ ***',
              style: bold,
            ),
          ),

          // Signature
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(children: [
                pw.Text('_________________', style: small),
                pw.Text('Client', style: small),
              ]),
              pw.Column(children: [
                pw.Text('_________________', style: small),
                pw.Text('Caissier', style: small),
              ]),
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
