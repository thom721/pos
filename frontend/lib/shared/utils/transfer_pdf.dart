import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:pos_connect/data/models/transfer_receipt_model.dart';
import 'package:pos_connect/providers/settings_provider.dart';

String _fmtQty(double q) =>
    q % 1 == 0 ? q.toInt().toString() : q.toStringAsFixed(2);

/// Bon de transfert de stock (audit) — format page complète, pas un reçu
/// thermique 80mm : destiné à être archivé/imprimé sur une imprimante bureau
/// classique, pas la caisse.
Future<Uint8List> buildTransferPdf(
  TransferReceiptModel receipt,
  AppSettings settings,
) async {
  final doc = pw.Document();
  final font = pw.Font.helvetica();
  final fontBold = pw.Font.helveticaBold();
  final dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(36),
    build: (ctx) {
      final base  = pw.TextStyle(font: font, fontSize: 11);
      final small = pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey700);
      final bold  = pw.TextStyle(font: fontBold, fontSize: 11);
      final title = pw.TextStyle(font: fontBold, fontSize: 18);

      pw.Widget locationBlock(String label, String name, String? address) =>
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(label, style: small),
                  pw.SizedBox(height: 4),
                  pw.Text(name, style: bold),
                  if (address != null && address.isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    pw.Text(address, style: small),
                  ],
                ],
              ),
            ),
          );

      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(settings.businessName, style: bold),
                  if (settings.address.isNotEmpty)
                    pw.Text(settings.address, style: small),
                  if (settings.phone.isNotEmpty)
                    pw.Text('Tél: ${settings.phone}', style: small),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('BON DE TRANSFERT', style: title),
                  pw.SizedBox(height: 4),
                  pw.Text('Réf: ${receipt.movementId.substring(0, 8).toUpperCase()}',
                      style: small),
                  pw.Text(dateFmt.format(receipt.createdAt), style: small),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 24),
          pw.Row(children: [
            locationBlock('DE (source)', receipt.sourceName, receipt.sourceAddress),
            pw.SizedBox(width: 16),
            pw.Text('→', style: pw.TextStyle(font: fontBold, fontSize: 20)),
            pw.SizedBox(width: 16),
            locationBlock('VERS (destination)', receipt.targetName, receipt.targetAddress),
          ]),
          pw.SizedBox(height: 24),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            columnWidths: const {
              0: pw.FlexColumnWidth(3),
              1: pw.FlexColumnWidth(1),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text('Produit', style: bold),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text('Quantité', style: bold),
                  ),
                ],
              ),
              pw.TableRow(children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text(receipt.productName, style: base),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text(_fmtQty(receipt.quantity), style: base),
                ),
              ]),
            ],
          ),
          if (receipt.reason != null && receipt.reason!.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text('Motif : ${receipt.reason}', style: base),
          ],
          pw.SizedBox(height: 48),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('_________________________', style: base),
                  pw.Text('Signature — remis par', style: small),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('_________________________', style: base),
                  pw.Text('Signature — reçu par', style: small),
                ],
              ),
            ],
          ),
        ],
      );
    },
  ));

  return doc.save();
}
