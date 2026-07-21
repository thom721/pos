import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:pos_connect/core/responsive.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/models/product_model.dart';
import 'package:pos_connect/data/models/proforma_model.dart';
import 'package:pos_connect/data/models/invoice_model.dart';
import 'package:pos_connect/data/repositories/events_repository.dart';
import 'package:pos_connect/core/permissions.dart';
import 'package:pos_connect/providers/customer_provider.dart';
import 'package:pos_connect/providers/permission_provider.dart';
import 'package:pos_connect/providers/product_provider.dart';
import 'package:pos_connect/providers/settings_provider.dart';
import 'package:uuid/uuid.dart';

// ── Shared item model ──────────────────────────────────────────────────────

class ProformaItem {
  final ProductModel? product;
  final String? customName;
  double quantity;
  double unitPrice;

  ProformaItem.fromProduct(ProductModel p)
      : product = p,
        customName = null,
        quantity = 1,
        unitPrice = p.salePrice;

  ProformaItem.custom({
    required String name,
    required this.unitPrice,
    this.quantity = 1,
  })  : product = null,
        customName = name;

  String get name => customName ?? product?.name ?? 'Article';
  double get subtotal => unitPrice * quantity;
}

// ── Proforma model ─────────────────────────────────────────────────────────

class Proforma {
  final String id;
  final String reference;
  final DateTime date;
  final String? clientName;
  final String? clientId;
  final List<ProformaItem> items;
  final double discount;
  final String notes;
  final String currency;
  String status;

  Proforma({
    required this.id,
    required this.reference,
    required this.date,
    this.clientName,
    this.clientId,
    required this.items,
    this.discount = 0,
    this.notes = '',
    this.currency = 'HTG',
    this.status = 'draft',
  });

  double get subtotal => items.fold(0, (s, i) => s + i.subtotal);
  double get total => subtotal - discount;
}

// ── Invoice model ──────────────────────────────────────────────────────────

class Invoice {
  final String id;
  final String reference;
  final DateTime date;
  final DateTime? dueDate;
  final String? clientName;
  final String? clientId;
  final List<ProformaItem> items;
  final double discount;
  double paidAmount;
  final String notes;
  final String currency;
  String status; // draft | sent | paid | partial | overdue | cancelled

  Invoice({
    required this.id,
    required this.reference,
    required this.date,
    this.dueDate,
    this.clientName,
    this.clientId,
    required this.items,
    this.discount = 0,
    this.paidAmount = 0,
    this.notes = '',
    this.currency = 'HTG',
    this.status = 'draft',
  });

  double get subtotal => items.fold(0, (s, i) => s + i.subtotal);
  double get total => subtotal - discount;
  double get balance => total - paidAmount;

  bool get isLate =>
      dueDate != null &&
      DateTime.now().isAfter(dueDate!) &&
      status != 'paid' &&
      status != 'cancelled';
}

// ── Providers ──────────────────────────────────────────────────────────────

// ── API-backed converters ──────────────────────────────────────────────────

Proforma _proformaFromModel(ProformaModel m) => Proforma(
      id: m.id,
      reference: m.reference,
      date: m.date,
      clientName: m.clientName,
      clientId: m.clientId,
      items: m.items
          .map((i) => ProformaItem.custom(
                name: i.name,
                unitPrice: i.unitPrice,
                quantity: i.quantity,
              ))
          .toList(),
      discount: m.discount,
      notes: m.notes ?? '',
      currency: m.currency,
      status: m.status,
    );

Invoice _invoiceFromModel(InvoiceModel m) => Invoice(
      id: m.id,
      reference: m.reference,
      date: m.date,
      dueDate: m.dueDate,
      clientName: m.clientName,
      clientId: m.clientId,
      items: m.items
          .map((i) => ProformaItem.custom(
                name: i.name,
                unitPrice: i.unitPrice,
                quantity: i.quantity,
              ))
          .toList(),
      discount: m.discount,
      paidAmount: m.paidAmount,
      notes: m.notes ?? '',
      currency: m.currency,
      status: m.status,
    );

Map<String, dynamic> _proformaToPayload(Proforma p) => {
      'reference': p.reference,
      'date': p.date.toIso8601String(),
      'client_id': p.clientId,
      'client_name': p.clientName,
      'discount': p.discount,
      'notes': p.notes,
      'currency': p.currency,
      'status': p.status,
      'items': p.items
          .map((i) => {
                'product_id': i.product?.id,
                'name': i.name,
                'quantity': i.quantity,
                'unit_price': i.unitPrice,
                'subtotal': i.subtotal,
              })
          .toList(),
    };

Map<String, dynamic> _invoiceToPayload(Invoice inv) => {
      'reference': inv.reference,
      'date': inv.date.toIso8601String(),
      'due_date': inv.dueDate?.toIso8601String(),
      'client_id': inv.clientId,
      'client_name': inv.clientName,
      'discount': inv.discount,
      'notes': inv.notes,
      'currency': inv.currency,
      'status': inv.status,
      'items': inv.items
          .map((i) => {
                'product_id': i.product?.id,
                'name': i.name,
                'quantity': i.quantity,
                'unit_price': i.unitPrice,
                'subtotal': i.subtotal,
              })
          .toList(),
    };

// ── Notifiers (API-backed) ─────────────────────────────────────────────────

class ProformaNotifier extends StateNotifier<List<Proforma>> {
  final _repo = EventsRepository();

  ProformaNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    try {
      final models = await _repo.getProformas();
      if (mounted) state = models.map(_proformaFromModel).toList();
    } catch (_) {}
  }

  Future<void> add(Proforma p) async {
    state = [p, ...state];
    try {
      final saved = await _repo.createProforma(_proformaToPayload(p));
      if (mounted) {
        state = state
            .map((x) => x.id == p.id ? _proformaFromModel(saved) : x)
            .toList();
      }
    } catch (_) {
      if (mounted) state = state.where((x) => x.id != p.id).toList();
    }
  }

  Future<void> updateStatus(String id, String status) async {
    state = state.map((p) {
      if (p.id == id) p.status = status;
      return p;
    }).toList();
    try {
      await _repo.updateProforma(id, {'status': status});
    } catch (_) {
      _load();
    }
  }

  Future<void> delete(String id) async {
    final backup = List<Proforma>.from(state);
    state = state.where((p) => p.id != id).toList();
    try {
      await _repo.deleteProforma(id);
    } catch (_) {
      if (mounted) state = backup;
    }
  }
}

class InvoiceNotifier extends StateNotifier<List<Invoice>> {
  final _repo = EventsRepository();

  InvoiceNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    try {
      final models = await _repo.getInvoices();
      if (mounted) state = models.map(_invoiceFromModel).toList();
    } catch (_) {}
  }

  Future<void> add(Invoice inv) async {
    state = [inv, ...state];
    try {
      final saved = await _repo.createInvoice(_invoiceToPayload(inv));
      if (mounted) {
        state = state
            .map((x) => x.id == inv.id ? _invoiceFromModel(saved) : x)
            .toList();
      }
    } catch (_) {
      if (mounted) state = state.where((x) => x.id != inv.id).toList();
    }
  }

  Future<void> updateStatus(String id, String newStatus) async {
    state = state.map((inv) {
      if (inv.id == id) inv.status = newStatus;
      return inv;
    }).toList();
    try {
      await _repo.updateInvoice(id, {'status': newStatus});
    } catch (_) {
      _load();
    }
  }

  Future<void> recordPayment(String id, double amount) async {
    try {
      final saved = await _repo.recordPayment(id, amount);
      if (mounted) {
        state = state
            .map((inv) => inv.id == id ? _invoiceFromModel(saved) : inv)
            .toList();
      }
    } catch (_) {}
  }

  Future<void> delete(String id) async {
    final backup = List<Invoice>.from(state);
    state = state.where((inv) => inv.id != id).toList();
    try {
      await _repo.deleteInvoice(id);
    } catch (_) {
      if (mounted) state = backup;
    }
  }
}

final proformaProvider =
    StateNotifierProvider<ProformaNotifier, List<Proforma>>(
        (ref) => ProformaNotifier());

final invoiceProvider =
    StateNotifierProvider<InvoiceNotifier, List<Invoice>>(
        (ref) => InvoiceNotifier());

// ── Helpers ────────────────────────────────────────────────────────────────

final _dateFmt = DateFormat('dd/MM/yyyy', 'fr');
final _dateFmtLong = DateFormat('dd MMMM yyyy', 'fr');

String _fmtQty(double q) =>
    q % 1 == 0 ? q.toInt().toString() : q.toStringAsFixed(2);

NumberFormat _fmtFor(String currency) {
  switch (currency) {
    case 'USD':
      return NumberFormat.currency(
          locale: 'en_US', symbol: '\$ ', decimalDigits: 2);
    case 'EUR':
      return NumberFormat.currency(
          locale: 'fr_FR', symbol: '€ ', decimalDigits: 2);
    default:
      return NumberFormat.currency(
          locale: 'fr_HT', symbol: 'HTG ', decimalDigits: 2);
  }
}

// ── Invoice PDF (A4) ───────────────────────────────────────────────────────

pw.Widget _pdfTotalRow(
    String label, String value, pw.TextStyle labelStyle, pw.TextStyle valStyle) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: labelStyle),
        pw.Text(value, style: valStyle),
      ],
    ),
  );
}

PdfColor _pdfStatusColor(String status) => switch (status) {
      'paid' => PdfColors.green700,
      'partial' => PdfColors.orange700,
      'overdue' => PdfColors.red700,
      'cancelled' => PdfColors.grey600,
      'sent' => PdfColors.blue700,
      _ => PdfColors.grey700,
    };

String _pdfStatusLabel(String status) => switch (status) {
      'paid' => 'PAYÉE',
      'partial' => 'PAIEMENT PARTIEL',
      'overdue' => 'EN RETARD',
      'cancelled' => 'ANNULÉE',
      'sent' => 'ENVOYÉE',
      _ => 'BROUILLON',
    };

Future<Uint8List> _buildInvoicePdf(
    Invoice invoice, AppSettings settings) async {
  final doc = pw.Document();
  final font = await PdfGoogleFonts.notoSansRegular();
  final fontBold = await PdfGoogleFonts.notoSansBold();
  final fmt = _fmtFor(invoice.currency);
  final df = DateFormat('dd/MM/yyyy');

  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(40),
    build: (ctx) {
      final base = pw.TextStyle(font: font, fontSize: 9);
      final bold = pw.TextStyle(font: fontBold, fontSize: 9);
      final small = pw.TextStyle(font: font, fontSize: 8);
      final h1 = pw.TextStyle(font: fontBold, fontSize: 22);
      final h2 = pw.TextStyle(
          font: fontBold, fontSize: 12, color: PdfColors.grey700);

      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // ── Business header + FACTURE title ──
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(settings.businessName,
                        style:
                            pw.TextStyle(font: fontBold, fontSize: 14)),
                    if (settings.address.isNotEmpty)
                      pw.Text(settings.address, style: small),
                    if (settings.phone.isNotEmpty)
                      pw.Text('Tél: ${settings.phone}', style: small),
                    if (settings.email.isNotEmpty)
                      pw.Text(settings.email, style: small),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('FACTURE', style: h1),
                  pw.Text(invoice.reference, style: h2),
                  pw.SizedBox(height: 6),
                  pw.Text('Date : ${df.format(invoice.date)}',
                      style: base),
                  if (invoice.dueDate != null)
                    pw.Text(
                      'Échéance : ${df.format(invoice.dueDate!)}',
                      style: pw.TextStyle(
                        font: fontBold,
                        fontSize: 9,
                        color: invoice.isLate
                            ? PdfColors.red700
                            : PdfColors.black,
                      ),
                    ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 20),

          // ── Client section ──
          if (invoice.clientName != null) ...[
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(4)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('FACTURER À',
                      style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 7,
                          color: PdfColors.grey600,
                          letterSpacing: 1)),
                  pw.SizedBox(height: 4),
                  pw.Text(invoice.clientName!,
                      style: pw.TextStyle(font: fontBold, fontSize: 10)),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
          ],

          // ── Items table ──
          pw.Table(
            border: pw.TableBorder(
              top: const pw.BorderSide(
                  color: PdfColors.grey800, width: 1.5),
              bottom: const pw.BorderSide(
                  color: PdfColors.grey800, width: 1.5),
              horizontalInside: const pw.BorderSide(
                  color: PdfColors.grey300, width: 0.5),
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(3),
              1: pw.FixedColumnWidth(50),
              2: pw.FixedColumnWidth(80),
              3: pw.FixedColumnWidth(80),
            },
            children: [
              // Header
              pw.TableRow(
                decoration:
                    const pw.BoxDecoration(color: PdfColors.grey800),
                children: [
                  'DESCRIPTION', 'QTÉ', 'PRIX U.', 'TOTAL'
                ].asMap().entries.map((e) {
                  final align = e.key == 0
                      ? pw.Alignment.centerLeft
                      : e.key == 1
                          ? pw.Alignment.center
                          : pw.Alignment.centerRight;
                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    child: pw.Align(
                      alignment: align,
                      child: pw.Text(e.value,
                          style: pw.TextStyle(
                              font: fontBold,
                              fontSize: 8,
                              color: PdfColors.white)),
                    ),
                  );
                }).toList(),
              ),
              // Items
              ...invoice.items.map((item) => pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: pw.Text(item.name, style: base),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: pw.Center(
                            child: pw.Text(_fmtQty(item.quantity),
                                style: base)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: pw.Align(
                          alignment: pw.Alignment.centerRight,
                          child: pw.Text(fmt.format(item.unitPrice),
                              style: base),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: pw.Align(
                          alignment: pw.Alignment.centerRight,
                          child: pw.Text(fmt.format(item.subtotal),
                              style: bold),
                        ),
                      ),
                    ],
                  )),
            ],
          ),
          pw.SizedBox(height: 16),

          // ── Totals (right-aligned) ──
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.SizedBox(
                width: 240,
                child: pw.Column(
                  children: [
                    if (invoice.discount > 0) ...[
                      _pdfTotalRow('Sous-total',
                          fmt.format(invoice.subtotal), base, base),
                      _pdfTotalRow('Remise',
                          '-${fmt.format(invoice.discount)}', base, base),
                      pw.Divider(
                          thickness: 0.5, color: PdfColors.grey400),
                    ],
                    _pdfTotalRow(
                      'TOTAL',
                      fmt.format(invoice.total),
                      pw.TextStyle(font: fontBold, fontSize: 10),
                      pw.TextStyle(font: fontBold, fontSize: 10),
                    ),
                    if (invoice.paidAmount > 0) ...[
                      pw.SizedBox(height: 6),
                      _pdfTotalRow('Montant payé',
                          fmt.format(invoice.paidAmount), base, base),
                      _pdfTotalRow(
                        invoice.balance > 0.001
                            ? 'Reste à payer'
                            : 'Solde',
                        fmt.format(invoice.balance.abs()),
                        pw.TextStyle(font: fontBold, fontSize: 9),
                        pw.TextStyle(
                          font: fontBold,
                          fontSize: 9,
                          color: invoice.balance > 0.001
                              ? PdfColors.red700
                              : PdfColors.green700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 16),

          // ── Status badge ──
          pw.Center(
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 16, vertical: 6),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(
                    color: _pdfStatusColor(invoice.status), width: 1.5),
                borderRadius:
                    const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Text(
                '*** ${_pdfStatusLabel(invoice.status)} ***',
                style: pw.TextStyle(
                  font: fontBold,
                  fontSize: 10,
                  color: _pdfStatusColor(invoice.status),
                ),
              ),
            ),
          ),

          // ── Notes ──
          if (invoice.notes.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius:
                    const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('NOTES / CONDITIONS',
                      style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 7,
                          color: PdfColors.grey600,
                          letterSpacing: 1)),
                  pw.SizedBox(height: 4),
                  pw.Text(invoice.notes, style: small),
                ],
              ),
            ),
          ],

          // ── Footer ──
          pw.SizedBox(height: 24),
          pw.Divider(thickness: 0.5, color: PdfColors.grey400),
          pw.SizedBox(height: 4),
          pw.Center(
              child: pw.Text(settings.receiptFooter, style: small)),
        ],
      );
    },
  ));

  return doc.save();
}

// ── Proforma PDF (A4) ──────────────────────────────────────────────────────

Future<Uint8List> _buildProformaPdf(
    Proforma proforma, AppSettings settings) async {
  final doc = pw.Document();
  final font = await PdfGoogleFonts.notoSansRegular();
  final fontBold = await PdfGoogleFonts.notoSansBold();
  final fmt = _fmtFor(proforma.currency);
  final df = DateFormat('dd/MM/yyyy');

  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(40),
    build: (ctx) {
      final base  = pw.TextStyle(font: font,     fontSize: 9);
      final bold  = pw.TextStyle(font: fontBold,  fontSize: 9);
      final small = pw.TextStyle(font: font,     fontSize: 8);
      final h1    = pw.TextStyle(font: fontBold,  fontSize: 22);
      final h2    = pw.TextStyle(font: fontBold,  fontSize: 12, color: PdfColors.grey700);

      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // ── Business header + PROFORMA title ──
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(settings.businessName,
                        style: pw.TextStyle(font: fontBold, fontSize: 14)),
                    if (settings.address.isNotEmpty)
                      pw.Text(settings.address, style: small),
                    if (settings.phone.isNotEmpty)
                      pw.Text('Tél: ${settings.phone}', style: small),
                    if (settings.email.isNotEmpty)
                      pw.Text(settings.email, style: small),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('PROFORMA / DEVIS', style: h1),
                  pw.Text(proforma.reference, style: h2),
                  pw.SizedBox(height: 6),
                  pw.Text('Date : ${df.format(proforma.date)}', style: base),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 20),

          // ── Client section ──
          if (proforma.clientName != null) ...[
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('CLIENT',
                      style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 7,
                          color: PdfColors.grey600,
                          letterSpacing: 1)),
                  pw.SizedBox(height: 4),
                  pw.Text(proforma.clientName!,
                      style: pw.TextStyle(font: fontBold, fontSize: 10)),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
          ],

          // ── Items table ──
          pw.Table(
            border: pw.TableBorder(
              top: const pw.BorderSide(color: PdfColors.grey800, width: 1.5),
              bottom: const pw.BorderSide(color: PdfColors.grey800, width: 1.5),
              horizontalInside: const pw.BorderSide(
                  color: PdfColors.grey300, width: 0.5),
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(3),
              1: pw.FixedColumnWidth(50),
              2: pw.FixedColumnWidth(80),
              3: pw.FixedColumnWidth(80),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey800),
                children: ['DESCRIPTION', 'QTÉ', 'PRIX U.', 'TOTAL']
                    .asMap()
                    .entries
                    .map((e) {
                  final align = e.key == 0
                      ? pw.Alignment.centerLeft
                      : e.key == 1
                          ? pw.Alignment.center
                          : pw.Alignment.centerRight;
                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    child: pw.Align(
                      alignment: align,
                      child: pw.Text(e.value,
                          style: pw.TextStyle(
                              font: fontBold,
                              fontSize: 8,
                              color: PdfColors.white)),
                    ),
                  );
                }).toList(),
              ),
              ...proforma.items.map((item) => pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: pw.Text(item.name, style: base),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: pw.Center(
                            child: pw.Text(_fmtQty(item.quantity),
                                style: base)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: pw.Align(
                          alignment: pw.Alignment.centerRight,
                          child: pw.Text(fmt.format(item.unitPrice),
                              style: base),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: pw.Align(
                          alignment: pw.Alignment.centerRight,
                          child: pw.Text(fmt.format(item.subtotal),
                              style: bold),
                        ),
                      ),
                    ],
                  )),
            ],
          ),
          pw.SizedBox(height: 16),

          // ── Totals ──
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.SizedBox(
                width: 240,
                child: pw.Column(
                  children: [
                    if (proforma.discount > 0) ...[
                      _pdfTotalRow('Sous-total',
                          fmt.format(proforma.subtotal), base, base),
                      _pdfTotalRow('Remise',
                          '-${fmt.format(proforma.discount)}', base, base),
                      pw.Divider(thickness: 0.5, color: PdfColors.grey400),
                    ],
                    _pdfTotalRow(
                      'TOTAL',
                      fmt.format(proforma.total),
                      pw.TextStyle(font: fontBold, fontSize: 10),
                      pw.TextStyle(font: fontBold, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 16),

          // ── Validity notice ──
          pw.Center(
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 16, vertical: 6),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(
                    color: PdfColors.blue700, width: 1.5),
                borderRadius:
                    const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Text(
                '*** DOCUMENT NON CONTRACTUEL — PROFORMA ***',
                style: pw.TextStyle(
                    font: fontBold,
                    fontSize: 9,
                    color: PdfColors.blue700),
              ),
            ),
          ),

          // ── Notes ──
          if (proforma.notes.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius:
                    const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('NOTES / CONDITIONS',
                      style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 7,
                          color: PdfColors.grey600,
                          letterSpacing: 1)),
                  pw.SizedBox(height: 4),
                  pw.Text(proforma.notes, style: small),
                ],
              ),
            ),
          ],

          // ── Footer ──
          pw.SizedBox(height: 24),
          pw.Divider(thickness: 0.5, color: PdfColors.grey400),
          pw.SizedBox(height: 4),
          pw.Center(child: pw.Text(settings.receiptFooter, style: small)),
        ],
      );
    },
  ));

  return doc.save();
}

// ── EventsScreen ───────────────────────────────────────────────────────────

class EventsScreen extends ConsumerStatefulWidget {
  const EventsScreen({super.key});

  @override
  ConsumerState<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends ConsumerState<EventsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  bool get _isInvoiceTab => _tab.index == 1;

  @override
  Widget build(BuildContext context) {
    final proformas = ref.watch(proformaProvider);
    final invoices = ref.watch(invoiceProvider);
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // ── Header with tabs ──
          Container(
            color: AppColors.surface,
            child: Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(24, 20, 24, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Documents commerciaux',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700)),
                            Text(
                              _isInvoiceTab
                                  ? '${invoices.length} facture(s)'
                                  : '${proformas.length} proforma(s)',
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      if ((_isInvoiceTab
                              ? ref.watch(hasPermissionProvider(Perm.invoicesCreate))
                              : ref.watch(hasPermissionProvider(Perm.proformasCreate))))
                        ElevatedButton.icon(
                          onPressed: _isInvoiceTab
                              ? () => _showNewInvoiceDialog(context)
                              : () => _showNewProformaDialog(context),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: Text(_isInvoiceTab
                              ? 'Nouvelle facture'
                              : 'Nouveau proforma'),
                        ),
                    ],
                  ),
                ),
                TabBar(
                  controller: _tab,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: AppColors.primary,
                  tabs: [
                    Tab(
                        text:
                            'Proformas / Devis (${proformas.length})'),
                    Tab(text: 'Factures (${invoices.length})'),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── Tab content ──
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                // Tab 0 – Proformas
                proformas.isEmpty
                    ? _EmptyState(type: 'proforma')
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: proformas.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (ctx, i) => _ProformaCard(
                          proforma: proformas[i],
                          fmt: _fmtFor(proformas[i].currency),
                          onView: () => _showProformaPreview(
                              context, proformas[i], settings),
                          onStatusChange: (s) => ref
                              .read(proformaProvider.notifier)
                              .updateStatus(proformas[i].id, s),
                          onDelete: () => ref
                              .read(proformaProvider.notifier)
                              .delete(proformas[i].id),
                        ),
                      ),

                // Tab 1 – Factures
                invoices.isEmpty
                    ? _EmptyState(type: 'facture')
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: invoices.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (ctx, i) => _InvoiceCard(
                          invoice: invoices[i],
                          fmt: _fmtFor(invoices[i].currency),
                          onView: () => _showInvoicePreview(
                              context, invoices[i], settings),
                          onStatusChange: (s) => ref
                              .read(invoiceProvider.notifier)
                              .updateStatus(invoices[i].id, s),
                          onRecordPayment: (amount) => ref
                              .read(invoiceProvider.notifier)
                              .recordPayment(invoices[i].id, amount),
                          onDelete: () => ref
                              .read(invoiceProvider.notifier)
                              .delete(invoices[i].id),
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showNewProformaDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _NewProformaDialog(
        onCreated: (p) => ref.read(proformaProvider.notifier).add(p),
      ),
    );
  }

  void _showNewInvoiceDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _NewInvoiceDialog(
        onCreated: (inv) =>
            ref.read(invoiceProvider.notifier).add(inv),
      ),
    );
  }

  void _showProformaPreview(
      BuildContext context, Proforma p, AppSettings s) {
    showDialog(
      context: context,
      builder: (ctx) => _ProformaPreviewDialog(
          proforma: p, fmt: _fmtFor(p.currency), settings: s),
    );
  }

  void _showInvoicePreview(
      BuildContext context, Invoice inv, AppSettings s) {
    showDialog(
      context: context,
      builder: (ctx) => _InvoicePreviewDialog(
          invoice: inv, fmt: _fmtFor(inv.currency), settings: s),
    );
  }
}

// ── New Proforma Dialog ────────────────────────────────────────────────────

class _NewProformaDialog extends ConsumerStatefulWidget {
  final void Function(Proforma) onCreated;
  const _NewProformaDialog({required this.onCreated});

  @override
  ConsumerState<_NewProformaDialog> createState() =>
      _NewProformaDialogState();
}

class _NewProformaDialogState
    extends ConsumerState<_NewProformaDialog> {
  final _clientCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: '0');
  final _searchCtrl = TextEditingController();
  final List<ProformaItem> _items = [];
  String? _selectedClientId;
  String _currency = 'HTG';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(
            () => _currency = ref.read(settingsProvider).currency);
      }
    });
  }

  @override
  void dispose() {
    _clientCtrl.dispose();
    _notesCtrl.dispose();
    _discountCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  double get _subtotal => _items.fold(0, (s, i) => s + i.subtotal);
  double get _discount => double.tryParse(_discountCtrl.text) ?? 0;
  double get _total => _subtotal - _discount;

  void _addProduct(ProductModel p) {
    setState(() {
      final idx = _items.indexWhere(
          (i) => i.product?.id == p.id && i.customName == null);
      if (idx >= 0) {
        _items[idx].quantity += 1;
      } else {
        _items.add(ProformaItem.fromProduct(p));
      }
    });
  }

  void _showCustomEntry() async {
    final item = await showDialog<ProformaItem>(
      context: context,
      builder: (ctx) => _CustomEntryDialog(currency: _currency),
    );
    if (item != null) setState(() => _items.add(item));
  }

  void _save() {
    if (_items.isEmpty) return;
    final ref = const Uuid().v4().substring(0, 8).toUpperCase();
    widget.onCreated(Proforma(
      id: const Uuid().v4(),
      reference: 'PRF-$ref',
      date: DateTime.now(),
      clientName:
          _clientCtrl.text.isNotEmpty ? _clientCtrl.text : null,
      clientId: _selectedClientId,
      items: List.from(_items),
      discount: _discount,
      notes: _notesCtrl.text.trim(),
      currency: _currency,
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(posProductsProvider);
    final customersAsync = ref.watch(customersProvider);
    final fmt = _fmtFor(_currency);

    return _DocumentDialog(
      title: 'Nouveau proforma',
      currency: _currency,
      onCurrencyChanged: (c) => setState(() => _currency = c),
      searchCtrl: _searchCtrl,
      productsAsync: productsAsync,
      fmtHTG: _fmtFor('HTG'),
      onAddProduct: _addProduct,
      onCustomEntry: _showCustomEntry,
      customersAsync: customersAsync,
      selectedClientId: _selectedClientId,
      clientCtrl: _clientCtrl,
      onClientChanged: (v, name) {
        setState(() {
          _selectedClientId = v;
          _clientCtrl.text = name ?? '';
        });
      },
      items: _items,
      fmt: fmt,
      discountCtrl: _discountCtrl,
      notesCtrl: _notesCtrl,
      onRebuild: () => setState(() {}),
      subtotal: _subtotal,
      discount: _discount,
      total: _total,
      saveLabel: 'Créer le proforma',
      onSave: _items.isEmpty ? null : _save,
    );
  }
}

// ── New Invoice Dialog ─────────────────────────────────────────────────────

class _NewInvoiceDialog extends ConsumerStatefulWidget {
  final void Function(Invoice) onCreated;
  const _NewInvoiceDialog({required this.onCreated});

  @override
  ConsumerState<_NewInvoiceDialog> createState() =>
      _NewInvoiceDialogState();
}

class _NewInvoiceDialogState extends ConsumerState<_NewInvoiceDialog> {
  final _clientCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: '0');
  final _searchCtrl = TextEditingController();
  final List<ProformaItem> _items = [];
  String? _selectedClientId;
  String _currency = 'HTG';
  DateTime? _dueDate = DateTime.now().add(const Duration(days: 30));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(
            () => _currency = ref.read(settingsProvider).currency);
      }
    });
  }

  @override
  void dispose() {
    _clientCtrl.dispose();
    _notesCtrl.dispose();
    _discountCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  double get _subtotal => _items.fold(0, (s, i) => s + i.subtotal);
  double get _discount => double.tryParse(_discountCtrl.text) ?? 0;
  double get _total => _subtotal - _discount;

  void _addProduct(ProductModel p) {
    setState(() {
      final idx = _items.indexWhere(
          (i) => i.product?.id == p.id && i.customName == null);
      if (idx >= 0) {
        _items[idx].quantity += 1;
      } else {
        _items.add(ProformaItem.fromProduct(p));
      }
    });
  }

  void _showCustomEntry() async {
    final item = await showDialog<ProformaItem>(
      context: context,
      builder: (ctx) => _CustomEntryDialog(currency: _currency),
    );
    if (item != null) setState(() => _items.add(item));
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  void _save() {
    if (_items.isEmpty) return;
    final uuid = const Uuid().v4().substring(0, 8).toUpperCase();
    widget.onCreated(Invoice(
      id: const Uuid().v4(),
      reference: 'FAC-$uuid',
      date: DateTime.now(),
      dueDate: _dueDate,
      clientName:
          _clientCtrl.text.isNotEmpty ? _clientCtrl.text : null,
      clientId: _selectedClientId,
      items: List.from(_items),
      discount: _discount,
      notes: _notesCtrl.text.trim(),
      currency: _currency,
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(posProductsProvider);
    final customersAsync = ref.watch(customersProvider);
    final fmt = _fmtFor(_currency);

    return _DocumentDialog(
      title: 'Nouvelle facture',
      currency: _currency,
      onCurrencyChanged: (c) => setState(() => _currency = c),
      searchCtrl: _searchCtrl,
      productsAsync: productsAsync,
      fmtHTG: _fmtFor('HTG'),
      onAddProduct: _addProduct,
      onCustomEntry: _showCustomEntry,
      customersAsync: customersAsync,
      selectedClientId: _selectedClientId,
      clientCtrl: _clientCtrl,
      onClientChanged: (v, name) {
        setState(() {
          _selectedClientId = v;
          _clientCtrl.text = name ?? '';
        });
      },
      items: _items,
      fmt: fmt,
      discountCtrl: _discountCtrl,
      notesCtrl: _notesCtrl,
      onRebuild: () => setState(() {}),
      subtotal: _subtotal,
      discount: _discount,
      total: _total,
      saveLabel: 'Créer la facture',
      onSave: _items.isEmpty ? null : _save,
      // Invoice-specific extras
      extraHeaderWidgets: [
        GestureDetector(
          onTap: _pickDueDate,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.divider),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.event_rounded,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  _dueDate != null
                      ? 'Échéance : ${_dateFmt.format(_dueDate!)}'
                      : 'Pas d\'échéance',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Shared document dialog (used by both Proforma & Invoice) ──────────────

class _DocumentDialog extends ConsumerStatefulWidget {
  final String title;
  final String currency;
  final void Function(String) onCurrencyChanged;
  final TextEditingController searchCtrl;
  final AsyncValue productsAsync;
  final NumberFormat fmtHTG;
  final void Function(ProductModel) onAddProduct;
  final VoidCallback onCustomEntry;
  final AsyncValue customersAsync;
  final String? selectedClientId;
  final TextEditingController clientCtrl;
  final void Function(String? id, String? name) onClientChanged;
  final List<ProformaItem> items;
  final NumberFormat fmt;
  final TextEditingController discountCtrl;
  final TextEditingController notesCtrl;
  final VoidCallback onRebuild;
  final double subtotal;
  final double discount;
  final double total;
  final String saveLabel;
  final VoidCallback? onSave;
  final List<Widget> extraHeaderWidgets;

  const _DocumentDialog({
    required this.title,
    required this.currency,
    required this.onCurrencyChanged,
    required this.searchCtrl,
    required this.productsAsync,
    required this.fmtHTG,
    required this.onAddProduct,
    required this.onCustomEntry,
    required this.customersAsync,
    required this.selectedClientId,
    required this.clientCtrl,
    required this.onClientChanged,
    required this.items,
    required this.fmt,
    required this.discountCtrl,
    required this.notesCtrl,
    required this.onRebuild,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.saveLabel,
    required this.onSave,
    this.extraHeaderWidgets = const [],
  });

  @override
  ConsumerState<_DocumentDialog> createState() =>
      _DocumentDialogState();
}

class _DocumentDialogState extends ConsumerState<_DocumentDialog> {
  Widget _buildProductPanel() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: widget.searchCtrl,
            decoration: const InputDecoration(
              hintText: 'Rechercher un produit...',
              prefixIcon: Icon(Icons.search_rounded),
              isDense: true,
            ),
            onChanged: (v) =>
                ref.read(posProductSearchProvider.notifier).state = v,
          ),
        ),
        Expanded(
          child: widget.productsAsync.when(
            data: (res) => ListView.builder(
              itemCount: res.data.length,
              itemBuilder: (ctx, i) {
                final p = res.data[i];
                return ListTile(
                  dense: true,
                  title: Text(p.name, style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                    widget.fmtHTG.format(p.salePrice),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.primary),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.add_circle_rounded,
                        color: AppColors.primary, size: 22),
                    onPressed: () => widget.onAddProduct(p),
                  ),
                );
              },
            ),
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, s) => Center(child: Text('Erreur: $e')),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: OutlinedButton.icon(
            onPressed: widget.onCustomEntry,
            icon: const Icon(Icons.edit_note_rounded, size: 18),
            label: const Text('Entrée manuelle'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: const BorderSide(color: AppColors.divider),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCartPanel() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                widget.customersAsync.when(
                  data: (customers) => InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Client',
                      prefixIcon: Icon(Icons.person_outline, size: 20),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    child: DropdownButton<String?>(
                      value: widget.selectedClientId,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      isDense: true,
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Sans client',
                                style: TextStyle(fontSize: 14))),
                        ...customers.data.map(
                          (c) => DropdownMenuItem<String?>(
                            value: c.id,
                            child: Text(c.name,
                                style: const TextStyle(fontSize: 14)),
                          ),
                        ),
                      ],
                      onChanged: (v) {
                        final name = v != null
                            ? customers.data
                                .firstWhere((c) => c.id == v)
                                .name
                            : null;
                        widget.onClientChanged(v, name);
                      },
                    ),
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (e, s) => TextField(
                    controller: widget.clientCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Nom du client', isDense: true),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Articles',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (widget.items.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.divider),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Ajoutez des produits',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13)),
                  )
                else
                  ...widget.items.map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            if (item.customName != null)
                              const Padding(
                                padding: EdgeInsets.only(right: 4),
                                child: Icon(Icons.edit_note_rounded,
                                    size: 14, color: AppColors.info),
                              ),
                            Expanded(
                              child: Text(item.name,
                                  style:
                                      const TextStyle(fontSize: 13)),
                            ),
                            SizedBox(
                              width: 56,
                              child: TextFormField(
                                initialValue: _fmtQty(item.quantity),
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 13),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding:
                                      EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 8),
                                ),
                                onChanged: (v) {
                                  final qty = double.tryParse(v);
                                  if (qty != null && qty > 0) {
                                    item.quantity = qty;
                                  }
                                  widget.onRebuild();
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              widget.fmt.format(item.subtotal),
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded,
                                  size: 16, color: AppColors.error),
                              onPressed: () {
                                widget.items.remove(item);
                                widget.onRebuild();
                              },
                            ),
                          ],
                        ),
                      )),
                const SizedBox(height: 12),
                Row(children: [
                  const Expanded(
                      child:
                          Text('Remise', style: TextStyle(fontSize: 13))),
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: widget.discountCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8)),
                      onChanged: (_) => widget.onRebuild(),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                TextField(
                  controller: widget.notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Notes / Conditions', isDense: true),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.divider))),
          child: Column(
            children: [
              Row(children: [
                const Text('Sous-total',
                    style: TextStyle(fontSize: 13)),
                const Spacer(),
                Text(widget.fmt.format(widget.subtotal),
                    style: const TextStyle(fontSize: 13)),
              ]),
              if (widget.discount > 0)
                Row(children: [
                  const Text('Remise',
                      style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary)),
                  const Spacer(),
                  Text('-${widget.fmt.format(widget.discount)}',
                      style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary)),
                ]),
              const Divider(height: 12),
              Row(children: [
                const Text('TOTAL',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                const Spacer(),
                Text(widget.fmt.format(widget.total),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppColors.primary)),
              ]),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: widget.onSave,
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: Text(widget.saveLabel),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = context.isMobile;

    final header = Container(
      padding: isMobile
          ? const EdgeInsets.fromLTRB(16, 12, 8, 12)
          : const EdgeInsets.fromLTRB(24, 20, 16, 20),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(widget.title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  _CurrencyToggle(
                    value: widget.currency,
                    onChanged: widget.onCurrencyChanged,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 40, minHeight: 40),
                    onPressed: () => Navigator.pop(context),
                  ),
                ]),
                if (widget.extraHeaderWidgets.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: widget.extraHeaderWidgets),
                ],
              ],
            )
          : Row(children: [
              Text(widget.title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              const Spacer(),
              ...widget.extraHeaderWidgets,
              if (widget.extraHeaderWidgets.isNotEmpty)
                const SizedBox(width: 12),
              _CurrencyToggle(
                value: widget.currency,
                onChanged: widget.onCurrencyChanged,
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ]),
    );

    final productPanel = _buildProductPanel();
    final cartPanel = _buildCartPanel();

    if (isMobile) {
      return DefaultTabController(
        length: 2,
        child: Dialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 900,
              maxHeight: MediaQuery.sizeOf(context).height - 48,
            ),
            child: Column(
              children: [
                header,
                TabBar(
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: AppColors.primary,
                  tabs: const [
                    Tab(text: 'Produits'),
                    Tab(text: 'Panier'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [productPanel, cartPanel],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Dialog(
      backgroundColor: AppColors.surface,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
        child: Column(
          children: [
            header,
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 340, child: productPanel),
                  const VerticalDivider(width: 1),
                  Expanded(child: cartPanel),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Currency toggle ────────────────────────────────────────────────────────

class _CurrencyToggle extends StatelessWidget {
  final String value;
  final void Function(String) onChanged;

  const _CurrencyToggle(
      {required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const options = ['HTG', 'USD', 'EUR'];
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((c) {
          final sel = value == c;
          return GestureDetector(
            onTap: () => onChanged(c),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color:
                    sel ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(c,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color:
                        sel ? Colors.white : AppColors.textSecondary,
                  )),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Custom entry dialog ────────────────────────────────────────────────────

class _CustomEntryDialog extends StatefulWidget {
  final String currency;
  const _CustomEntryDialog({required this.currency});

  @override
  State<_CustomEntryDialog> createState() =>
      _CustomEntryDialogState();
}

class _CustomEntryDialogState extends State<_CustomEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _priceCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  void _confirm() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      ProformaItem.custom(
        name: _nameCtrl.text.trim(),
        unitPrice: double.tryParse(_priceCtrl.text) ?? 0,
        quantity: double.tryParse(_qtyCtrl.text) ?? 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.edit_note_rounded, color: AppColors.primary, size: 20),
        SizedBox(width: 8),
        Text('Entrée manuelle', style: TextStyle(fontSize: 16)),
      ]),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Description *',
                  hintText: 'Ex: Transport, Service, ...',
                  isDense: true,
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requis' : null,
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Quantité', isDense: true),
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      return (n == null || n <= 0) ? 'Invalide' : null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _priceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Prix unitaire *',
                      suffixText: widget.currency,
                      isDense: true,
                    ),
                    validator: (v) {
                      final d = double.tryParse(v ?? '');
                      return (d == null || d < 0) ? 'Invalide' : null;
                    },
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        ElevatedButton(
            onPressed: _confirm, child: const Text('Ajouter')),
      ],
    );
  }
}

// ── Proforma card ──────────────────────────────────────────────────────────

class _ProformaCard extends StatelessWidget {
  final Proforma proforma;
  final NumberFormat fmt;
  final VoidCallback onView;
  final void Function(String) onStatusChange;
  final VoidCallback onDelete;

  const _ProformaCard({
    required this.proforma,
    required this.fmt,
    required this.onView,
    required this.onStatusChange,
    required this.onDelete,
  });

  Color get _statusColor => switch (proforma.status) {
        'sent' => AppColors.info,
        'accepted' => AppColors.success,
        'converted' => AppColors.accent,
        _ => AppColors.textSecondary,
      };

  String get _statusLabel => switch (proforma.status) {
        'sent' => 'Envoyé',
        'accepted' => 'Accepté',
        'converted' => 'Converti',
        _ => 'Brouillon',
      };

  @override
  Widget build(BuildContext context) {
    return _DocCard(
      icon: Icons.description_rounded,
      reference: proforma.reference,
      clientName: proforma.clientName,
      date: proforma.date,
      currency: proforma.currency,
      total: proforma.total,
      fmt: fmt,
      statusLabel: _statusLabel,
      statusColor: _statusColor,
      onView: onView,
      menuItems: [
        _cardMenuItem('view', Icons.receipt_rounded, 'Voir le reçu'),
        if (proforma.status == 'draft')
          _cardMenuItem(
              'sent', Icons.send_rounded, 'Marquer envoyé'),
        if (proforma.status == 'sent')
          _cardMenuItem('accepted', Icons.check_circle_rounded,
              'Marquer accepté'),
        _cardMenuItem('delete', Icons.delete_rounded, 'Supprimer',
            isDestructive: true),
      ],
      onMenuSelected: (action) {
        if (action == 'view') {
          onView();
        } else if (action == 'delete') {
          onDelete();
        } else {
          onStatusChange(action);
        }
      },
    );
  }
}

// ── Invoice card ───────────────────────────────────────────────────────────

class _InvoiceCard extends StatelessWidget {
  final Invoice invoice;
  final NumberFormat fmt;
  final VoidCallback onView;
  final void Function(String) onStatusChange;
  final void Function(double) onRecordPayment;
  final VoidCallback onDelete;

  const _InvoiceCard({
    required this.invoice,
    required this.fmt,
    required this.onView,
    required this.onStatusChange,
    required this.onRecordPayment,
    required this.onDelete,
  });

  Color get _statusColor => switch (invoice.status) {
        'sent' => AppColors.info,
        'paid' => AppColors.success,
        'partial' => AppColors.warning,
        'overdue' => AppColors.error,
        'cancelled' => AppColors.textSecondary,
        _ => AppColors.textSecondary,
      };

  String get _statusLabel => switch (invoice.status) {
        'sent' => 'Envoyée',
        'paid' => 'Payée',
        'partial' => 'Partielle',
        'overdue' => 'En retard',
        'cancelled' => 'Annulée',
        _ => 'Brouillon',
      };

  @override
  Widget build(BuildContext context) {
    final effectiveStatus =
        (invoice.isLate && invoice.status == 'sent') ? 'overdue' : invoice.status;

    return _DocCard(
      icon: Icons.receipt_long_rounded,
      reference: invoice.reference,
      clientName: invoice.clientName,
      date: invoice.date,
      dueDate: invoice.dueDate,
      isLate: invoice.isLate,
      currency: invoice.currency,
      total: invoice.total,
      balance: invoice.balance > 0.001 ? invoice.balance : null,
      fmt: fmt,
      statusLabel: effectiveStatus == 'overdue' ? 'En retard' : _statusLabel,
      statusColor: effectiveStatus == 'overdue' ? AppColors.error : _statusColor,
      onView: onView,
      menuItems: [
        _cardMenuItem(
            'view', Icons.receipt_long_rounded, 'Voir la facture'),
        if (invoice.status == 'draft')
          _cardMenuItem(
              'sent', Icons.send_rounded, 'Marquer envoyée'),
        if (invoice.status != 'paid' && invoice.status != 'cancelled')
          _cardMenuItem(Icons.payments_rounded.codePoint.toString(),
              Icons.payments_rounded, 'Enregistrer un paiement'),
        if (invoice.status != 'paid' && invoice.status != 'cancelled')
          _cardMenuItem(
              'paid', Icons.check_circle_rounded, 'Marquer payée'),
        if (invoice.status != 'cancelled')
          _cardMenuItem('cancelled', Icons.cancel_rounded, 'Annuler'),
        _cardMenuItem('delete', Icons.delete_rounded, 'Supprimer',
            isDestructive: true),
      ],
      onMenuSelected: (action) async {
        if (action == 'view') {
          onView();
        } else if (action == 'delete') {
          onDelete();
        } else if (action ==
            Icons.payments_rounded.codePoint.toString()) {
          final amount = await showDialog<double>(
            context: context,
            builder: (_) => _PaymentDialog(
              remaining: invoice.balance,
              currency: invoice.currency,
            ),
          );
          if (amount != null && amount > 0) onRecordPayment(amount);
        } else {
          onStatusChange(action);
        }
      },
    );
  }
}

// ── Shared document card ───────────────────────────────────────────────────

PopupMenuItem<String> _cardMenuItem(
    String value, IconData icon, String label,
    {bool isDestructive = false}) {
  return PopupMenuItem(
    value: value,
    child: Row(children: [
      Icon(icon,
          size: 16,
          color: isDestructive ? AppColors.error : AppColors.textPrimary),
      const SizedBox(width: 8),
      Text(label,
          style: TextStyle(
              color: isDestructive ? AppColors.error : null)),
    ]),
  );
}

class _DocCard extends StatelessWidget {
  final IconData icon;
  final String reference;
  final String? clientName;
  final DateTime date;
  final DateTime? dueDate;
  final bool isLate;
  final String currency;
  final double total;
  final double? balance;
  final NumberFormat fmt;
  final String statusLabel;
  final Color statusColor;
  final VoidCallback onView;
  final List<PopupMenuItem<String>> menuItems;
  final void Function(String) onMenuSelected;

  const _DocCard({
    required this.icon,
    required this.reference,
    required this.clientName,
    required this.date,
    this.dueDate,
    this.isLate = false,
    required this.currency,
    required this.total,
    this.balance,
    required this.fmt,
    required this.statusLabel,
    required this.statusColor,
    required this.onView,
    required this.menuItems,
    required this.onMenuSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isLate ? AppColors.error.withValues(alpha: 0.4) : AppColors.divider,
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.primary, size: 22),
        ),
        title: Text(reference,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${clientName ?? 'Sans client'} · ${_dateFmt.format(date)} · $currency',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            if (dueDate != null)
              Text(
                'Échéance : ${_dateFmt.format(dueDate!)}',
                style: TextStyle(
                  fontSize: 11,
                  color: isLate ? AppColors.error : AppColors.textSecondary,
                  fontWeight: isLate ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(fmt.format(total),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                if (balance != null)
                  Text(
                    'Solde : ${fmt.format(balance!)}',
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.error,
                        fontWeight: FontWeight.w600),
                  )
                else
                  _StatusChip(label: statusLabel, color: statusColor),
              ],
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded,
                  color: AppColors.textSecondary),
              onSelected: onMenuSelected,
              itemBuilder: (_) => menuItems,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600)),
    );
  }
}

// ── Proforma preview dialog ────────────────────────────────────────────────

class _ProformaPreviewDialog extends StatefulWidget {
  final Proforma proforma;
  final NumberFormat fmt;
  final AppSettings settings;

  const _ProformaPreviewDialog({
    required this.proforma,
    required this.fmt,
    required this.settings,
  });

  @override
  State<_ProformaPreviewDialog> createState() => _ProformaPreviewDialogState();
}

class _ProformaPreviewDialogState extends State<_ProformaPreviewDialog> {
  bool _printing = false;

  Future<void> _print() async {
    setState(() => _printing = true);
    try {
      final bytes = await _buildProformaPdf(widget.proforma, widget.settings);
      await Printing.layoutPdf(onLayout: (_) => bytes);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final proforma = widget.proforma;
    final fmt      = widget.fmt;
    final settings = widget.settings;
    return Dialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(settings.businessName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 18)),
                if (settings.address.isNotEmpty)
                  Text(settings.address,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary)),
                if (settings.phone.isNotEmpty)
                  Text(settings.phone,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary)),
                const SizedBox(height: 16),
                const Text('PROFORMA / DEVIS',
                    style: TextStyle(
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                const SizedBox(height: 4),
                Text(proforma.reference,
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary)),
                Text(_dateFmtLong.format(proforma.date),
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary)),
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(proforma.currency,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary)),
                ),
                if (proforma.clientName != null) ...[
                  const SizedBox(height: 8),
                  Text('Client : ${proforma.clientName}',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ],
                const Divider(height: 24),
                ...proforma.items.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(children: [
                        if (item.customName != null)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(Icons.edit_note_rounded,
                                size: 12, color: AppColors.info),
                          ),
                        Expanded(
                            child: Text(item.name,
                                style: const TextStyle(fontSize: 13))),
                        Text(
                          '${_fmtQty(item.quantity)} × ${fmt.format(item.unitPrice)}',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary),
                        ),
                        const SizedBox(width: 8),
                        Text(fmt.format(item.subtotal),
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                      ]),
                    )),
                const Divider(height: 16),
                if (proforma.discount > 0)
                  Row(children: [
                    const Expanded(
                        child: Text('Remise',
                            style: TextStyle(fontSize: 13))),
                    Text('-${fmt.format(proforma.discount)}',
                        style: const TextStyle(fontSize: 13)),
                  ]),
                Row(children: [
                  const Expanded(
                      child: Text('TOTAL',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15))),
                  Text(fmt.format(proforma.total),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                ]),
                if (proforma.notes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(proforma.notes,
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary)),
                  ),
                ],
                const Divider(height: 24),
                Text(settings.receiptFooter,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Fermer'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _printing ? null : _print,
                        icon: _printing
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.print_rounded, size: 16),
                        label: const Text('Imprimer (A4)'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Invoice preview dialog ─────────────────────────────────────────────────

class _InvoicePreviewDialog extends StatefulWidget {
  final Invoice invoice;
  final NumberFormat fmt;
  final AppSettings settings;

  const _InvoicePreviewDialog({
    required this.invoice,
    required this.fmt,
    required this.settings,
  });

  @override
  State<_InvoicePreviewDialog> createState() =>
      _InvoicePreviewDialogState();
}

class _InvoicePreviewDialogState
    extends State<_InvoicePreviewDialog> {
  bool _printing = false;

  Future<void> _print() async {
    setState(() => _printing = true);
    try {
      final bytes =
          await _buildInvoicePdf(widget.invoice, widget.settings);
      await Printing.layoutPdf(
        onLayout: (_) => bytes,
        name: 'Facture_${widget.invoice.reference}',
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = widget.invoice;
    final fmt = widget.fmt;
    final s = widget.settings;
    final lbl = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    final val = const TextStyle(fontSize: 12, fontWeight: FontWeight.w500);
    final big = const TextStyle(fontSize: 15, fontWeight: FontWeight.w700);

    final statusColor = switch (inv.status) {
      'paid' => AppColors.success,
      'partial' => AppColors.warning,
      'overdue' => AppColors.error,
      'cancelled' => AppColors.textSecondary,
      'sent' => AppColors.info,
      _ => AppColors.textSecondary,
    };
    final statusLabel = switch (inv.status) {
      'paid' => 'PAYÉE',
      'partial' => 'PAIEMENT PARTIEL',
      'overdue' => 'EN RETARD',
      'cancelled' => 'ANNULÉE',
      'sent' => 'ENVOYÉE',
      _ => 'BROUILLON',
    };

    return Dialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints:
            const BoxConstraints(maxWidth: 460, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header bar
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(children: [
                const Icon(Icons.receipt_long_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Aperçu de la facture',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16)),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 20),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ]),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Business + title
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(s.businessName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15)),
                              if (s.address.isNotEmpty)
                                Text(s.address,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color:
                                            AppColors.textSecondary)),
                              if (s.phone.isNotEmpty)
                                Text(s.phone,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color:
                                            AppColors.textSecondary)),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.end,
                          children: [
                            const Text('FACTURE',
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 20,
                                    color: AppColors.primary)),
                            Text(inv.reference,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Meta info
                    _previewRow(
                        'Date', _dateFmtLong.format(inv.date), lbl, val),
                    if (inv.dueDate != null)
                      _previewRow(
                        'Échéance',
                        _dateFmtLong.format(inv.dueDate!),
                        lbl,
                        TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: inv.isLate
                              ? AppColors.error
                              : AppColors.textPrimary,
                        ),
                      ),
                    if (inv.clientName != null)
                      _previewRow('Client', inv.clientName!, lbl, val),
                    const Divider(height: 20),

                    // Items
                    const Text('Articles',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 6),
                    ...inv.items.map((item) => Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 4),
                          child: Row(children: [
                            if (item.customName != null)
                              const Padding(
                                padding: EdgeInsets.only(right: 4),
                                child: Icon(Icons.edit_note_rounded,
                                    size: 12, color: AppColors.info),
                              ),
                            Expanded(
                                child: Text(item.name,
                                    style:
                                        const TextStyle(fontSize: 12))),
                            Text(
                              '${_fmtQty(item.quantity)} × ${fmt.format(item.unitPrice)}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary),
                            ),
                            const SizedBox(width: 8),
                            Text(fmt.format(item.subtotal),
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ]),
                        )),
                    const Divider(height: 20),

                    // Totals
                    if (inv.discount > 0) ...[
                      _totalRow(
                          'Sous-total', fmt.format(inv.subtotal), lbl, val),
                      _totalRow('Remise',
                          '-${fmt.format(inv.discount)}', lbl, val),
                    ],
                    _totalRow('TOTAL', fmt.format(inv.total), lbl, big),
                    if (inv.paidAmount > 0) ...[
                      const SizedBox(height: 4),
                      _totalRow('Montant payé',
                          fmt.format(inv.paidAmount), lbl, val),
                      _totalRow(
                        inv.balance > 0.001
                            ? 'Reste à payer'
                            : 'Solde',
                        fmt.format(inv.balance.abs()),
                        lbl,
                        TextStyle(
                          fontSize: 12,
                          color: inv.balance > 0.001
                              ? AppColors.error
                              : AppColors.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),

                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 6, horizontal: 12),
                      decoration: BoxDecoration(
                        color:
                            statusColor.withValues(alpha: 0.1),
                        border: Border.all(
                            color: statusColor.withValues(alpha: 0.4)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text('*** $statusLabel ***',
                            style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 12)),
                      ),
                    ),

                    if (inv.notes.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(inv.notes,
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Actions
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Fermer'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _printing ? null : _print,
                    icon: _printing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2))
                        : const Icon(Icons.print_rounded, size: 16),
                    label: const Text('Imprimer (A4)'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewRow(
          String l, String v, TextStyle ls, TextStyle vs) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Text('$l : ', style: ls),
          Expanded(
              child: Text(v, style: vs, overflow: TextOverflow.ellipsis)),
        ]),
      );

  Widget _totalRow(String l, String v, TextStyle ls, TextStyle vs) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Text(l, style: ls),
          const Spacer(),
          Text(v, style: vs),
        ]),
      );
}

// ── Payment dialog ─────────────────────────────────────────────────────────

class _PaymentDialog extends StatefulWidget {
  final double remaining;
  final String currency;

  const _PaymentDialog(
      {required this.remaining, required this.currency});

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ctrl.text = widget.remaining.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fmt = _fmtFor(widget.currency);
    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.payments_rounded, color: AppColors.primary, size: 20),
        SizedBox(width: 8),
        Text('Enregistrer un paiement', style: TextStyle(fontSize: 16)),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Solde restant : ${fmt.format(widget.remaining)}',
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true),
            decoration: InputDecoration(
              labelText: 'Montant reçu',
              suffixText: widget.currency,
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              _ctrl.text = widget.remaining.toStringAsFixed(2);
            },
            style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 0)),
            child: const Text('Payer le solde complet',
                style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            final amount = double.tryParse(_ctrl.text) ?? 0;
            if (amount > 0) Navigator.pop(context, amount);
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String type; // 'proforma' | 'facture'
  const _EmptyState({required this.type});

  @override
  Widget build(BuildContext context) {
    final isInvoice = type == 'facture';
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isInvoice
                ? Icons.receipt_long_outlined
                : Icons.description_outlined,
            size: 64,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 16),
          Text(
            isInvoice ? 'Aucune facture' : 'Aucun proforma',
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            isInvoice
                ? 'Créez une facture pour votre client'
                : 'Créez un devis ou proforma\npour un client',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 14, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
