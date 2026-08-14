import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pos_connect/core/date_utils.dart' show haitiNow;
import 'package:printing/printing.dart';
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';

import 'package:pos_connect/data/models/restaurant_model.dart';
import 'package:pos_connect/data/models/sale_model.dart';
import 'package:pos_connect/providers/settings_provider.dart';
import 'package:pos_connect/services/logo_cache_service.dart';
import 'package:pos_connect/shared/utils/receipt_pdf.dart';
import 'package:pos_connect/shared/utils/restaurant_bill_pdf.dart';

String _fmtQty(double q) =>
    q % 1 == 0 ? q.toInt().toString() : q.toStringAsFixed(2);

/// Abstraction d'impression thermique.
///
/// Sur un appareil Sunmi (H10, V2 Pro, etc.) : SDK intégré — aucune génération
/// PDF, impression instantanée via AIDL.
/// Ailleurs (Windows, web, imprimante réseau) : génère un PDF 80 mm et
/// délègue au package [printing].
class ThermalPrinterService {
  ThermalPrinterService._();
  static final ThermalPrinterService instance = ThermalPrinterService._();

  // null = not yet probed, true/false = cached result
  bool? _isSunmi;

  // ── Détection Sunmi ───────────────────────────────────────────────────────

  Future<bool> _checkSunmi() async {
    if (kIsWeb) return false;
    _isSunmi ??= await _probeSunmi();
    return _isSunmi!;
  }

  Future<bool> _probeSunmi() async {
    try {
      // getStatus() returns non-null on genuine Sunmi hardware;
      // throws PlatformException or returns null on other Android devices.
      final status = await SunmiConfig.getStatus();
      return status != null;
    } catch (_) {
      return false;
    }
  }

  // ── API publique ──────────────────────────────────────────────────────────

  Future<bool> get isSunmiAvailable => _checkSunmi();

  Future<void> _printSunmiLogo(AppSettings settings) async {
    if (settings.logoPath.isEmpty) return;
    try {
      final bytes = await LogoCacheService.instance.getLogoBytes(settings.logoPath);
      if (bytes == null) return;
      await SunmiPrinter.printImage(bytes, align: SunmiPrintAlign.CENTER);
      await SunmiPrinter.lineWrap(1);
    } catch (_) {
      // Logo optionnel — un échec ne doit jamais bloquer le reste du reçu.
    }
  }

  Future<void> printReceipt(
    SaleModel sale,
    AppSettings settings, {
    String? printerUrl,
  }) async {
    if (await _checkSunmi()) {
      await _printSunmi(sale, settings);
    } else {
      await _printSystem(sale, settings, printerUrl: printerUrl);
    }
  }

  Future<void> printRestaurantBill(
    RestaurantOrderModel order,
    AppSettings settings, {
    String? reference,
    double discount = 0,
    double paidAmount = 0,
    String? paymentMethod,
    String? printerUrl,
  }) async {
    if (await _checkSunmi()) {
      await _printSunmiRestaurantBill(order, settings,
          reference: reference, discount: discount,
          paidAmount: paidAmount, paymentMethod: paymentMethod);
    } else {
      await _printSystemRestaurantBill(order, settings,
          reference: reference, discount: discount,
          paidAmount: paidAmount, paymentMethod: paymentMethod,
          printerUrl: printerUrl);
    }
  }

  // ── Impression Sunmi ──────────────────────────────────────────────────────

  Future<void> _printSunmi(SaleModel sale, AppSettings settings) async {
    final fmt = NumberFormat('#,##0.00', 'fr_FR');
    final date = DateFormat('dd/MM/yyyy HH:mm');
    final sym = settings.currencySymbol.trim();

    // En-tête boutique
    await _printSunmiLogo(settings);
    await SunmiPrinter.printText(
      '${settings.businessName}\n',
      style: SunmiTextStyle(fontSize: 36, align: SunmiPrintAlign.CENTER, bold: true),
    );
    if (settings.address.isNotEmpty) {
      await SunmiPrinter.printText(
        '${settings.address}\n',
        style: SunmiTextStyle(fontSize: 24, align: SunmiPrintAlign.CENTER),
      );
    }
    if (settings.phone.isNotEmpty) {
      await SunmiPrinter.printText(
        'Tél: ${settings.phone}\n',
        style: SunmiTextStyle(fontSize: 24, align: SunmiPrintAlign.CENTER),
      );
    }
    await SunmiPrinter.line();
    await SunmiPrinter.lineWrap(1);

    // Infos vente
    await SunmiPrinter.printText(
      'Réf: ${sale.reference}\n',
      style: SunmiTextStyle(fontSize: 24, align: SunmiPrintAlign.LEFT),
    );
    await SunmiPrinter.printText(
      'Date: ${date.format(sale.createdAt)}\n',
      style: SunmiTextStyle(fontSize: 24, align: SunmiPrintAlign.LEFT),
    );
    if (sale.customerName != null) {
      await SunmiPrinter.printText(
        'Client: ${sale.customerName}\n',
        style: SunmiTextStyle(fontSize: 24, align: SunmiPrintAlign.LEFT),
      );
    }
    if (sale.userFullName != null) {
      await SunmiPrinter.printText(
        'Caissier: ${sale.userFullName}\n',
        style: SunmiTextStyle(fontSize: 24, align: SunmiPrintAlign.LEFT),
      );
    }
    await SunmiPrinter.lineWrap(1);
    await SunmiPrinter.line();
    await SunmiPrinter.lineWrap(1);

    // En-tête tableau articles (col widths: 13 + 4 + 7 + 8 = 32)
    await SunmiPrinter.printRow(cols: [
      SunmiColumn(text: 'ARTICLE', width: 13,
          style: SunmiTextStyle(bold: true, align: SunmiPrintAlign.LEFT)),
      SunmiColumn(text: 'QTE', width: 4,
          style: SunmiTextStyle(bold: true, align: SunmiPrintAlign.CENTER)),
      SunmiColumn(text: 'P.U.', width: 7,
          style: SunmiTextStyle(bold: true, align: SunmiPrintAlign.RIGHT)),
      SunmiColumn(text: 'TOTAL', width: 8,
          style: SunmiTextStyle(bold: true, align: SunmiPrintAlign.RIGHT)),
    ]);

    for (final item in sale.items) {
      const maxName = 12;
      final rawName = item.productName ?? '';
      final name = rawName.length > maxName
          ? '${rawName.substring(0, maxName - 1)}…'
          : rawName;
      await SunmiPrinter.printRow(cols: [
        SunmiColumn(text: name, width: 13,
            style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
        SunmiColumn(text: _fmtQty(item.quantity), width: 4,
            style: SunmiTextStyle(align: SunmiPrintAlign.CENTER)),
        SunmiColumn(text: fmt.format(item.unitPrice), width: 7,
            style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
        SunmiColumn(text: fmt.format(item.subtotal), width: 8,
            style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
      ]);
    }
    await SunmiPrinter.line();
    await SunmiPrinter.lineWrap(1);

    // Totaux (col widths: 20 + 12 = 32)
    final itemsDisc = sale.totalItemsDiscount;
    final catalogItemsDisc = sale.totalCatalogItemDiscount;
    final hasDisc = itemsDisc > 0.001 || catalogItemsDisc > 0.001 || sale.discount > 0.001;
    if (hasDisc) {
      await SunmiPrinter.printRow(cols: [
        SunmiColumn(text: 'Sous-total', width: 20,
            style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
        SunmiColumn(text: '$sym${fmt.format(sale.totalAmount + itemsDisc)}', width: 12,
            style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
      ]);
      if (itemsDisc > 0.001) {
        await SunmiPrinter.printRow(cols: [
          SunmiColumn(text: 'Remises articles', width: 20,
              style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
          SunmiColumn(text: '-$sym${fmt.format(itemsDisc)}', width: 12,
              style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
        ]);
      }
      if (catalogItemsDisc > 0.001) {
        await SunmiPrinter.printRow(cols: [
          SunmiColumn(text: 'Rabais catalogue', width: 20,
              style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
          SunmiColumn(text: '-$sym${fmt.format(catalogItemsDisc)}', width: 12,
              style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
        ]);
      }
      if (sale.discount > 0.001) {
        var label = sale.discountName != null
            ? 'Remise (${sale.discountName})'
            : 'Remise caisse';
        if (label.length > 20) label = '${label.substring(0, 19)}…';
        await SunmiPrinter.printRow(cols: [
          SunmiColumn(text: label, width: 20,
              style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
          SunmiColumn(text: '-$sym${fmt.format(sale.discount)}', width: 12,
              style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
        ]);
      }
    }
    await SunmiPrinter.printRow(cols: [
      SunmiColumn(text: 'TOTAL', width: 20,
          style: SunmiTextStyle(bold: true, align: SunmiPrintAlign.LEFT)),
      SunmiColumn(text: '$sym${fmt.format(sale.finalAmount)}', width: 12,
          style: SunmiTextStyle(bold: true, align: SunmiPrintAlign.RIGHT)),
    ]);
    // change_due (create_sale) plafonne paidAmount au montant dû et stocke
    // l'excédent séparément ; les ventes modifiées (update_sale) peuvent
    // encore rendre paidAmount > finalAmount directement.
    final change = sale.changeDue > 0.001
        ? sale.changeDue
        : (sale.balance < -0.001 ? -sale.balance : 0.0);
    final tendered =
        sale.changeDue > 0.001 ? sale.paidAmount + sale.changeDue : sale.paidAmount;
    await SunmiPrinter.printRow(cols: [
      SunmiColumn(text: 'Montant reçu', width: 20,
          style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
      SunmiColumn(text: '$sym${fmt.format(tendered)}', width: 12,
          style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
    ]);
    if (sale.balance > 0.001) {
      await SunmiPrinter.printRow(cols: [
        SunmiColumn(text: 'Reste à payer', width: 20,
            style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
        SunmiColumn(text: '$sym${fmt.format(sale.balance)}', width: 12,
            style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
      ]);
    }
    if (change > 0.001) {
      await SunmiPrinter.printRow(cols: [
        SunmiColumn(text: 'Monnaie', width: 20,
            style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
        SunmiColumn(text: '$sym${fmt.format(change)}', width: 12,
            style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
      ]);
    }
    if (sale.loyaltyRedeemed > 0.001) {
      await SunmiPrinter.printRow(cols: [
        SunmiColumn(text: 'Fidélité utilisée', width: 20,
            style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
        SunmiColumn(text: '-$sym${fmt.format(sale.loyaltyRedeemed)}', width: 12,
            style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
      ]);
    }
    if (sale.loyaltyEarned > 0.001) {
      await SunmiPrinter.printRow(cols: [
        SunmiColumn(text: 'Fidélité gagnée', width: 20,
            style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
        SunmiColumn(text: '+$sym${fmt.format(sale.loyaltyEarned)}', width: 12,
            style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
      ]);
    }
    if ((sale.customerLoyaltyBalance ?? 0) > 0.001) {
      await SunmiPrinter.printRow(cols: [
        SunmiColumn(text: 'Solde fidélité', width: 20,
            style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
        SunmiColumn(text: '$sym${fmt.format(sale.customerLoyaltyBalance!)}', width: 12,
            style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
      ]);
    }
    await SunmiPrinter.line();
    await SunmiPrinter.lineWrap(1);

    // Statut
    final statusText = switch (sale.status) {
      'PAID'    => '*** PAYE ***',
      'PARTIAL' => '*** PAIEMENT PARTIEL ***',
      _         => '*** NON PAYE ***',
    };
    await SunmiPrinter.printText(
      '$statusText\n',
      style: SunmiTextStyle(fontSize: 28, bold: true, align: SunmiPrintAlign.CENTER),
    );

    // Pied de page
    if (settings.receiptFooter.isNotEmpty) {
      await SunmiPrinter.lineWrap(1);
      await SunmiPrinter.line();
      await SunmiPrinter.printText(
        '${settings.receiptFooter}\n',
        style: SunmiTextStyle(fontSize: 24, align: SunmiPrintAlign.CENTER),
      );
    }

    await SunmiPrinter.lineWrap(3);
    try {
      await SunmiPrinter.cutPaper();
    } catch (_) {
      // Modèles handheld sans coupe-papier (ex. H10)
    }
  }

  Future<void> _printSunmiRestaurantBill(
    RestaurantOrderModel order,
    AppSettings settings, {
    String? reference,
    double discount = 0,
    double paidAmount = 0,
    String? paymentMethod,
  }) async {
    final fmt = NumberFormat('#,##0.00', 'fr_FR');
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm');
    final sym = settings.currencySymbol.trim();
    final isPaid = reference != null;

    await _printSunmiLogo(settings);
    await SunmiPrinter.printText(
      '${settings.businessName}\n',
      style: SunmiTextStyle(fontSize: 36, align: SunmiPrintAlign.CENTER, bold: true),
    );
    if (settings.address.isNotEmpty) {
      await SunmiPrinter.printText('${settings.address}\n',
          style: SunmiTextStyle(fontSize: 24, align: SunmiPrintAlign.CENTER));
    }
    if (settings.phone.isNotEmpty) {
      await SunmiPrinter.printText('Tél: ${settings.phone}\n',
          style: SunmiTextStyle(fontSize: 24, align: SunmiPrintAlign.CENTER));
    }
    await SunmiPrinter.line();
    await SunmiPrinter.printText(isPaid ? 'REÇU\n' : 'ADDITION\n',
        style: SunmiTextStyle(fontSize: 28, bold: true, align: SunmiPrintAlign.CENTER));
    if (reference != null) {
      await SunmiPrinter.printText('Réf: $reference\n',
          style: SunmiTextStyle(fontSize: 24, align: SunmiPrintAlign.LEFT));
    }
    await SunmiPrinter.printText('Date: ${dateFmt.format(haitiNow())}\n',
        style: SunmiTextStyle(fontSize: 24, align: SunmiPrintAlign.LEFT));
    if (order.tableName != null) {
      await SunmiPrinter.printText('Table: ${order.tableName}\n',
          style: SunmiTextStyle(fontSize: 24, align: SunmiPrintAlign.LEFT));
    }
    if (order.waiterName != null) {
      await SunmiPrinter.printText('Serveur: ${order.waiterName}\n',
          style: SunmiTextStyle(fontSize: 24, align: SunmiPrintAlign.LEFT));
    }
    await SunmiPrinter.printText('Couverts: ${order.covers}\n',
        style: SunmiTextStyle(fontSize: 24, align: SunmiPrintAlign.LEFT));
    await SunmiPrinter.line();

    await SunmiPrinter.printRow(cols: [
      SunmiColumn(text: 'ARTICLE', width: 18,
          style: SunmiTextStyle(bold: true, align: SunmiPrintAlign.LEFT)),
      SunmiColumn(text: 'QTÉ', width: 4,
          style: SunmiTextStyle(bold: true, align: SunmiPrintAlign.CENTER)),
      SunmiColumn(text: 'TOTAL', width: 10,
          style: SunmiTextStyle(bold: true, align: SunmiPrintAlign.RIGHT)),
    ]);
    for (final item in order.items) {
      const maxName = 17;
      final raw = item.productName;
      final name = raw.length > maxName ? '${raw.substring(0, maxName - 1)}…' : raw;
      await SunmiPrinter.printRow(cols: [
        SunmiColumn(text: name, width: 18,
            style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
        SunmiColumn(
            text: item.quantity == item.quantity.truncateToDouble()
                ? item.quantity.toInt().toString()
                : item.quantity.toStringAsFixed(1),
            width: 4,
            style: SunmiTextStyle(align: SunmiPrintAlign.CENTER)),
        SunmiColumn(text: fmt.format(item.subtotal), width: 10,
            style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
      ]);
      if (item.notes != null && item.notes!.isNotEmpty) {
        await SunmiPrinter.printText('  ${item.notes}\n',
            style: SunmiTextStyle(fontSize: 20, align: SunmiPrintAlign.LEFT));
      }
    }
    await SunmiPrinter.line();
    await SunmiPrinter.lineWrap(1);

    await SunmiPrinter.printRow(cols: [
      SunmiColumn(text: 'Sous-total', width: 20,
          style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
      SunmiColumn(text: '$sym${fmt.format(order.subtotal)}', width: 12,
          style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
    ]);
    if (order.tip > 0) {
      await SunmiPrinter.printRow(cols: [
        SunmiColumn(text: 'Pourboire', width: 20,
            style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
        SunmiColumn(text: '+$sym${fmt.format(order.tip)}', width: 12,
            style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
      ]);
    }
    if (discount > 0) {
      await SunmiPrinter.printRow(cols: [
        SunmiColumn(text: 'Remise', width: 20,
            style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
        SunmiColumn(text: '-$sym${fmt.format(discount)}', width: 12,
            style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
      ]);
    }
    final finalTotal = order.total - discount;
    await SunmiPrinter.printRow(cols: [
      SunmiColumn(text: 'TOTAL', width: 20,
          style: SunmiTextStyle(bold: true, align: SunmiPrintAlign.LEFT)),
      SunmiColumn(
          text: '$sym${fmt.format(isPaid ? finalTotal : order.total)}',
          width: 12,
          style: SunmiTextStyle(bold: true, align: SunmiPrintAlign.RIGHT)),
    ]);
    if (isPaid) {
      if (paymentMethod != null) {
        final modeLabel = switch (paymentMethod) {
          'CARD' => 'Carte',
          'TRANSFER' => 'Virement',
          _ => 'Espèces',
        };
        await SunmiPrinter.printRow(cols: [
          SunmiColumn(text: 'Mode', width: 20,
              style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
          SunmiColumn(text: modeLabel, width: 12,
              style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
        ]);
      }
      await SunmiPrinter.printRow(cols: [
        SunmiColumn(text: 'Reçu', width: 20,
            style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
        SunmiColumn(text: '$sym${fmt.format(paidAmount)}', width: 12,
            style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
      ]);
      final change = (paidAmount - finalTotal).clamp(0.0, double.infinity);
      if (change > 0.001) {
        await SunmiPrinter.printRow(cols: [
          SunmiColumn(text: 'Monnaie', width: 20,
              style: SunmiTextStyle(bold: true, align: SunmiPrintAlign.LEFT)),
          SunmiColumn(text: '$sym${fmt.format(change)}', width: 12,
              style: SunmiTextStyle(bold: true, align: SunmiPrintAlign.RIGHT)),
        ]);
      }
    }
    await SunmiPrinter.line();
    await SunmiPrinter.lineWrap(1);

    if (isPaid) {
      await SunmiPrinter.printText('*** PAYÉ ***\n',
          style: SunmiTextStyle(fontSize: 28, bold: true, align: SunmiPrintAlign.CENTER));
    }
    if (settings.receiptFooter.isNotEmpty) {
      await SunmiPrinter.lineWrap(1);
      await SunmiPrinter.line();
      await SunmiPrinter.printText('${settings.receiptFooter}\n',
          style: SunmiTextStyle(fontSize: 24, align: SunmiPrintAlign.CENTER));
    }
    await SunmiPrinter.lineWrap(3);
    try {
      await SunmiPrinter.cutPaper();
    } catch (_) {}
  }

  Future<void> _printSystemRestaurantBill(
    RestaurantOrderModel order,
    AppSettings settings, {
    String? reference,
    double discount = 0,
    double paidAmount = 0,
    String? paymentMethod,
    String? printerUrl,
  }) async {
    final bytes = await buildRestaurantBillPdf(order, settings,
        reference: reference, discount: discount,
        paidAmount: paidAmount, paymentMethod: paymentMethod);
    await printPdfBytes(
      bytes,
      name: reference != null ? 'Recu_$reference' : 'Addition',
      printerUrl: printerUrl,
    );
  }

  // ── Fallback système / PDF ────────────────────────────────────────────────

  Future<void> _printSystem(
    SaleModel sale,
    AppSettings settings, {
    String? printerUrl,
  }) async {
    final bytes = await buildReceiptPdf(sale, settings);
    await printPdfBytes(
      bytes,
      name: 'Recu_${sale.reference}',
      printerUrl: printerUrl,
    );
  }

  /// Imprime un PDF directement sur une imprimante résolue (celle configurée,
  /// sinon l'imprimante par défaut du système, sinon la première disponible)
  /// — sans jamais ouvrir la boîte de dialogue "Print Setup" du système.
  ///
  /// Sur Windows/macOS : directPrintPdf sans usePrinterSettings scale le PDF sur
  /// le format par défaut du driver (ex: A4) → coupe le reçu et le rend pâle.
  /// usePrinterSettings: true force le driver à utiliser son format roll configuré.
  Future<void> printPdfBytes(
    Uint8List bytes, {
    required String name,
    String? printerUrl,
  }) async {
    if (kIsWeb) {
      await Printing.layoutPdf(onLayout: (_) => bytes, name: name);
      return;
    }
    final printers = await Printing.listPrinters();
    Printer? printer;
    if (printerUrl != null && printerUrl.isNotEmpty) {
      printer = printers.cast<Printer?>().firstWhere(
            (p) => p?.url == printerUrl,
            orElse: () => null,
          );
    }
    printer ??= printers.cast<Printer?>().firstWhere(
          (p) => p?.isDefault ?? false,
          orElse: () => null,
        );
    printer ??= printers.isNotEmpty ? printers.first : null;

    if (printer != null) {
      await Printing.directPrintPdf(
        printer: printer,
        onLayout: (_) => bytes,
        name: name,
        usePrinterSettings: Platform.isWindows || Platform.isMacOS,
      );
      return;
    }
    // Aucune imprimante détectée — dernier recours, ouvre le sélecteur système.
    await Printing.layoutPdf(
      onLayout: (_) => bytes,
      name: name,
      usePrinterSettings: true,
    );
  }
}
