import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';

import 'package:pos_connect/data/models/restaurant_model.dart';
import 'package:pos_connect/data/models/sale_model.dart';
import 'package:pos_connect/providers/settings_provider.dart';
import 'package:pos_connect/shared/utils/receipt_pdf.dart';
import 'package:pos_connect/shared/utils/restaurant_bill_pdf.dart';

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
    await SunmiPrinter.line();

    // En-tête tableau articles (col widths: 18 + 4 + 10 = 32)
    await SunmiPrinter.printRow(cols: [
      SunmiColumn(text: 'ARTICLE', width: 18,
          style: SunmiTextStyle(bold: true, align: SunmiPrintAlign.LEFT)),
      SunmiColumn(text: 'QTE', width: 4,
          style: SunmiTextStyle(bold: true, align: SunmiPrintAlign.CENTER)),
      SunmiColumn(text: 'TOTAL', width: 10,
          style: SunmiTextStyle(bold: true, align: SunmiPrintAlign.RIGHT)),
    ]);

    for (final item in sale.items) {
      const maxName = 17;
      final rawName = item.productName ?? '';
      final name = rawName.length > maxName
          ? '${rawName.substring(0, maxName - 1)}…'
          : rawName;
      await SunmiPrinter.printRow(cols: [
        SunmiColumn(text: name, width: 18,
            style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
        SunmiColumn(text: '${item.quantity.toInt()}', width: 4,
            style: SunmiTextStyle(align: SunmiPrintAlign.CENTER)),
        SunmiColumn(text: fmt.format(item.subtotal), width: 10,
            style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
      ]);
    }
    await SunmiPrinter.line();

    // Totaux (col widths: 20 + 12 = 32)
    if (sale.discount > 0) {
      await SunmiPrinter.printRow(cols: [
        SunmiColumn(text: 'Sous-total', width: 20,
            style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
        SunmiColumn(text: '$sym${fmt.format(sale.totalAmount)}', width: 12,
            style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
      ]);
      await SunmiPrinter.printRow(cols: [
        SunmiColumn(text: 'Remise', width: 20,
            style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
        SunmiColumn(text: '-$sym${fmt.format(sale.discount)}', width: 12,
            style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
      ]);
    }
    await SunmiPrinter.printRow(cols: [
      SunmiColumn(text: 'TOTAL', width: 20,
          style: SunmiTextStyle(bold: true, align: SunmiPrintAlign.LEFT)),
      SunmiColumn(text: '$sym${fmt.format(sale.finalAmount)}', width: 12,
          style: SunmiTextStyle(bold: true, align: SunmiPrintAlign.RIGHT)),
    ]);
    await SunmiPrinter.printRow(cols: [
      SunmiColumn(text: 'Montant reçu', width: 20,
          style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
      SunmiColumn(text: '$sym${fmt.format(sale.paidAmount)}', width: 12,
          style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
    ]);
    if (sale.balance.abs() > 0.001) {
      final label = sale.balance > 0 ? 'Reste à payer' : 'Monnaie';
      await SunmiPrinter.printRow(cols: [
        SunmiColumn(text: label, width: 20,
            style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
        SunmiColumn(text: '$sym${fmt.format(sale.balance.abs())}', width: 12,
            style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
      ]);
    }
    await SunmiPrinter.line();

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
    await SunmiPrinter.printText('Date: ${dateFmt.format(DateTime.now())}\n',
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

    if (isPaid) {
      await SunmiPrinter.printText('*** PAYÉ ***\n',
          style: SunmiTextStyle(fontSize: 28, bold: true, align: SunmiPrintAlign.CENTER));
    }
    if (settings.receiptFooter.isNotEmpty) {
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

    if (printerUrl != null && printerUrl.isNotEmpty) {
      final printers = await Printing.listPrinters();
      final printer = printers.cast<Printer?>().firstWhere(
        (p) => p?.url == printerUrl,
        orElse: () => null,
      );
      if (printer != null && printer.isAvailable) {
        await Printing.directPrintPdf(
          printer: printer,
          onLayout: (_) => bytes,
          name: reference != null ? 'Recu_$reference' : 'Addition',
        );
        return;
      }
    }
    await Printing.layoutPdf(
      onLayout: (_) => bytes,
      name: reference != null ? 'Recu_$reference' : 'Addition',
    );
  }

  // ── Fallback système / PDF ────────────────────────────────────────────────

  Future<void> _printSystem(
    SaleModel sale,
    AppSettings settings, {
    String? printerUrl,
  }) async {
    final bytes = await buildReceiptPdf(sale, settings);

    if (printerUrl != null && printerUrl.isNotEmpty) {
      final printers = await Printing.listPrinters();
      final printer = printers.cast<Printer?>().firstWhere(
        (p) => p?.url == printerUrl,
        orElse: () => null,
      );
      // directPrintPdf seulement si l'imprimante est joignable.
      // Les imprimantes Bluetooth peuvent être dans la liste mais non connectées
      // → job bloqué "Unable to locate". On tombe sur layoutPdf dans ce cas.
      if (printer != null && printer.isAvailable) {
        await Printing.directPrintPdf(
          printer: printer,
          onLayout: (_) => bytes,
          name: 'Recu_${sale.reference}',
        );
        return;
      }
    }

    await Printing.layoutPdf(
      onLayout: (_) => bytes,
      name: 'Recu_${sale.reference}',
    );
  }
}
