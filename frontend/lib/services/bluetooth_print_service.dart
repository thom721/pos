import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:pos_connect/core/date_utils.dart' show haitiNow;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:pos_connect/data/models/restaurant_model.dart';
import 'package:pos_connect/data/models/return_model.dart';
import 'package:pos_connect/data/models/sale_model.dart';
import 'package:pos_connect/providers/settings_provider.dart';
import 'package:pos_connect/services/logo_cache_service.dart';

// Les imprimantes ESC/POS ne supportent que le Latin-1 (ISO-8859-1) — au-delà,
// chaque caractère devient un octet 0x3F ('?'). NumberFormat('fr') utilise une
// espace fine insécable (U+202F) comme séparateur de milliers, ce qui produisait
// un "?" entre les chiffres (ex: "1?250,00" au lieu de "1 250,00") — normalisée
// ici en espace ASCII avant l'encodage.
String _fmtQty(double q) =>
    q % 1 == 0 ? q.toInt().toString() : q.toStringAsFixed(2);

int _escposByte(int codeUnit) {
  const nonBreakingSpaces = {0x00A0, 0x2007, 0x2009, 0x200A, 0x202F};
  if (nonBreakingSpaces.contains(codeUnit)) return 0x20;
  return codeUnit <= 0xFF ? codeUnit : 0x3F;
}

class BluetoothPrintService {
  BluetoothPrintService._();
  static final BluetoothPrintService instance = BluetoothPrintService._();

  static const _ch = MethodChannel('pos_connect/bluetooth');

  Future<List<BluetoothInfo>> getPairedPrinters() async {
    if (kIsWeb) return [];
    try {
      // Sur Android 12+, BLUETOOTH_CONNECT est une permission runtime.
      // Si elle n'est pas accordée, le plugin retourne sans résoudre le
      // Future → spinner infini. On vérifie d'abord, puis on ajoute un
      // timeout de sécurité pour ne jamais bloquer l'UI.
      final granted = await PrintBluetoothThermal.isPermissionBluetoothGranted;
      if (!granted) return [];
      return await PrintBluetoothThermal.pairedBluetooths
          .timeout(const Duration(seconds: 6), onTimeout: () => []);
    } catch (_) {
      return [];
    }
  }

  Future<bool> connect(String mac) async {
    if (mac.isEmpty) return false;
    // Déconnecter session précédente
    try { await _ch.invokeMethod('disconnect'); } catch (_) {}

    // Connexion RFCOMM non-sécurisée via Method Channel Android
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final ok = await _ch.invokeMethod<bool>('connect', {'mac': mac})
            .timeout(const Duration(seconds: 10), onTimeout: () => false);
        if (ok == true) return true;
      } catch (_) {}
      if (attempt < 2) await Future.delayed(const Duration(milliseconds: 800));
    }
    return false;
  }

  Future<bool> get isConnected async => false;

  Future<void> disconnect() async {
    try { await _ch.invokeMethod('disconnect'); } catch (_) {}
  }

  Future<bool> _sendBytes(List<int> bytes) async {
    try {
      final ok = await _ch.invokeMethod<bool>(
          'sendBytes', {'bytes': Uint8List.fromList(bytes)});
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> printReceipt(SaleModel sale, AppSettings settings,
      {String? mac}) async {
    final printerMac = mac ?? settings.bluetoothPrinterMac;
    if (printerMac.isEmpty) return false;

    final connected = await connect(printerMac);
    if (!connected) return false;

    final logoBytes = await _logoToEscPos(settings);
    final bytes = _buildEscPos(sale, settings, logoBytes);
    return _sendBytes(bytes);
  }

  Future<bool> printReturn(ReturnModel ret, AppSettings settings,
      {String? mac}) async {
    final printerMac = mac ?? settings.bluetoothPrinterMac;
    if (printerMac.isEmpty) return false;

    final connected = await connect(printerMac);
    if (!connected) return false;

    final logoBytes = await _logoToEscPos(settings);
    final bytes = _buildEscPosReturn(ret, settings, logoBytes);
    return _sendBytes(bytes);
  }

  Future<bool> printRestaurantBill(
    RestaurantOrderModel order,
    AppSettings settings, {
    String? mac,
    String? reference,
    double discount = 0,
    double paidAmount = 0,
    String? paymentMethod,
  }) async {
    final printerMac = mac ?? settings.bluetoothPrinterMac;
    if (printerMac.isEmpty) return false;

    final connected = await connect(printerMac);
    if (!connected) return false;

    final logoBytes = await _logoToEscPos(settings);
    final bytes = _buildEscPosRestaurantBill(order, settings, logoBytes,
        reference: reference, discount: discount,
        paidAmount: paidAmount, paymentMethod: paymentMethod);
    return _sendBytes(bytes);
  }

  // ── Logo → ESC/POS bitmap ─────────────────────────────────────────────────

  Future<List<int>> _logoToEscPos(AppSettings settings) async {
    if (settings.logoPath.isEmpty) return [];
    try {
      final rawBytes = await LogoCacheService.instance.getLogoBytes(settings.logoPath);
      if (rawBytes == null) return [];

      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) return [];

      // Target width: ~40% of paper dot width (203 dpi ≈ 8 dots/mm)
      final targetW = settings.paperWidth == 80 ? 200 : 128;
      final aspect = decoded.height / decoded.width;
      final targetH = (targetW * aspect).round();
      final resized = img.copyResize(decoded, width: targetW, height: targetH,
          interpolation: img.Interpolation.average);

      final bytesPerRow = (targetW + 7) ~/ 8;
      final cmd = <int>[];

      // Center the image: left padding in bytes
      final paperDots = settings.paperWidth == 80 ? 576 : 384;
      final paddingDots = ((paperDots - targetW) ~/ 2).clamp(0, paperDots);
      final paddingBytes = paddingDots ~/ 8;
      // Adjust xL/xH to include padding so the image is centered
      final totalBytesPerRow = paddingBytes + bytesPerRow;

      // GS v 0 — raster bit image
      cmd.addAll([
        0x1D, 0x76, 0x30, 0x00,
        totalBytesPerRow & 0xFF, (totalBytesPerRow >> 8) & 0xFF,
        targetH & 0xFF, (targetH >> 8) & 0xFF,
      ]);

      for (int y = 0; y < targetH; y++) {
        // Left padding bytes (white = 0)
        for (int i = 0; i < paddingBytes; i++) {
          cmd.add(0x00);
        }
        // Image bytes
        for (int bx = 0; bx < bytesPerRow; bx++) {
          int b = 0;
          for (int bit = 0; bit < 8; bit++) {
            final x = bx * 8 + bit;
            if (x < targetW) {
              final pixel = resized.getPixel(x, y);
              final lum = 0.299 * pixel.r.toDouble() +
                  0.587 * pixel.g.toDouble() +
                  0.114 * pixel.b.toDouble();
              if (lum < 128.0) b |= (0x80 >> bit);
            }
          }
          cmd.add(b);
        }
      }
      return cmd;
    } catch (_) {
      return [];
    }
  }

  // ── ESC/POS receipt builder ───────────────────────────────────────────────

  Uint8List _buildEscPos(
      SaleModel sale, AppSettings settings, List<int> logoBytes) {
    final buf = <int>[];
    final numFmt = NumberFormat('#,##0.00', 'fr');
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm');
    final sym = settings.currencySymbol.trim();

    // Column counts for each paper width
    final cols = settings.paperWidth == 80 ? 48 : 32;
    final nameW = settings.paperWidth == 80 ? 20 : 14;
    final qtyW = settings.paperWidth == 80 ? 6 : 4;
    final puW = settings.paperWidth == 80 ? 8 : 6;
    // Marge de sécurité : gras+double-strike restent actifs pendant le
    // tableau d'articles (pour l'assombrissement, voir plus bas) et élargissent
    // légèrement chaque caractère sur certaines imprimantes — une ligne à 48/32
    // colonnes pleines déborde alors physiquement et perd ses derniers
    // caractères (ex: "TOTAL" → "TO", "9,60" → "9"). On réserve 2 colonnes de
    // marge à droite pour absorber ce débordement sans toucher au réglage
    // d'assombrissement.
    final rowMargin = 2;
    final totW = cols - nameW - qtyW - puW - rowMargin;
    final labelW = cols - 16;

    void esc(List<int> cmd) => buf.addAll(cmd);
    // WPC1252 : les caractères français (U+00C0–U+00FF) ont le même octet que
    // leur code point Unicode. Les chars hors Latin-1 sont remplacés par '?'.
    void text(String t) => buf.addAll(t.codeUnits.map(_escposByte));
    void nl([int n = 1]) {
      for (var i = 0; i < n; i++) {
        buf.add(10);
      }
    }
    void dash() {
      text('-' * cols);
      nl();
    }

    // Init + code page WPC1252 + assombrissement maximum
    esc([0x1B, 0x40]);                      // Initialize printer
    esc([0x1B, 0x37, 0x07, 0x96, 0x02]);   // ESC 7: heating max dots=7, time=150µs×10, interval=2 → encre plus foncée
    esc([0x1B, 0x74, 0x10]);               // Code page 16 = WPC1252 (é=0xE9, à=0xE0, ç=0xE7…)
    esc([0x1B, 0x47, 0x01]);               // Double-strike ON
    esc([0x1B, 0x45, 0x01]);               // Bold ON global — retiré puis restauré : sans lui, certaines
                                            // imprimantes (dont celle testée) impriment trop pâle même avec double-strike

    // ── Logo (si disponible) ───────────────────────────────────────────────
    if (logoBytes.isNotEmpty) {
      esc([0x1B, 0x61, 0x01]); // centre
      buf.addAll(logoBytes);
      nl();
      esc([0x1B, 0x61, 0x00]); // gauche
    }

    // ── En-tête ────────────────────────────────────────────────────────────
    esc([0x1B, 0x61, 0x01]);
    esc([0x1D, 0x21, 0x10]); // double hauteur
    text(settings.businessName);
    nl();
    esc([0x1D, 0x21, 0x00]);
    if (settings.address.isNotEmpty) {
      text(settings.address);
      nl();
    }
    if (settings.phone.isNotEmpty) {
      text('Tél: ${settings.phone}');
      nl();
    }
    esc([0x1B, 0x61, 0x00]);
    nl();
    dash();

    // ── Infos vente ────────────────────────────────────────────────────────
    text('Réf: ${sale.reference}');
    nl();
    text('Date: ${dateFmt.format(sale.createdAt)}');
    nl();
    if (sale.customerName != null) {
      text('Client: ${sale.customerName}');
      nl();
    }
    if (sale.userFullName != null) {
      text('Caissier: ${sale.userFullName}');
      nl();
    }
    dash();
    nl();

    // ── Articles ───────────────────────────────────────────────────────────
    text('ARTICLE'.padRight(nameW) +
        'QTE'.padLeft(qtyW) +
        'P.U.'.padLeft(puW) +
        'TOTAL'.padLeft(totW));
    nl();
    for (final item in sale.items) {
      final name =
          (item.productName ?? 'Article').padRight(nameW).substring(0, nameW);
      final qty = '${_fmtQty(item.quantity)}x'.padLeft(qtyW);
      final pu = numFmt.format(item.unitPrice).padLeft(puW);
      final total = '$sym ${numFmt.format(item.subtotal)}'.padLeft(totW);
      text('$name$qty$pu$total');
      nl();
    }
    dash();
    nl();

    // ── Totaux ─────────────────────────────────────────────────────────────
    final itemsDisc = sale.totalItemsDiscount;
    final catalogItemsDisc = sale.totalCatalogItemDiscount;
    final hasDisc = itemsDisc > 0.001 || catalogItemsDisc > 0.001 || sale.discount > 0.001;
    if (hasDisc) {
      text('Sous-total'.padRight(labelW) +
          '$sym ${numFmt.format(sale.totalAmount + itemsDisc)}'.padLeft(16));
      nl();
      if (itemsDisc > 0.001) {
        text('Remises articles'.padRight(labelW) +
            '-$sym ${numFmt.format(itemsDisc)}'.padLeft(16));
        nl();
      }
      if (catalogItemsDisc > 0.001) {
        text('Rabais articles'.padRight(labelW) +
            '-$sym ${numFmt.format(catalogItemsDisc)}'.padLeft(16));
        nl();
      }
      if (sale.discount > 0.001) {
        var label = sale.discountName != null ? 'Remise (${sale.discountName})' : 'Remise';
        if (label.length > labelW) label = label.substring(0, labelW);
        text(label.padRight(labelW) +
            '-$sym ${numFmt.format(sale.discount)}'.padLeft(16));
        nl();
      }
    }
    esc([0x1B, 0x45, 0x01]);
    text('TOTAL'.padRight(labelW) +
        '$sym ${numFmt.format(sale.finalAmount)}'.padLeft(16));
    nl();
    esc([0x1B, 0x45, 0x00]);
    // change_due (create_sale) plafonne paidAmount au montant dû et stocke
    // l'excédent séparément ; les ventes modifiées (update_sale) peuvent
    // encore rendre paidAmount > finalAmount directement.
    final change = sale.changeDue > 0.001
        ? sale.changeDue
        : (sale.balance < -0.001 ? -sale.balance : 0.0);
    final tendered =
        sale.changeDue > 0.001 ? sale.paidAmount + sale.changeDue : sale.paidAmount;
    text('Payé'.padRight(labelW) +
        '$sym ${numFmt.format(tendered)}'.padLeft(16));
    nl();
    if (sale.balance > 0.01) {
      text('Reste'.padRight(labelW) +
          '$sym ${numFmt.format(sale.balance)}'.padLeft(16));
      nl();
    }
    if (change > 0.01) {
      text('Monnaie'.padRight(labelW) +
          '$sym ${numFmt.format(change)}'.padLeft(16));
      nl();
    }
    if (sale.loyaltyRedeemed > 0.01) {
      text('Fidélité utilisée'.padRight(labelW) +
          '-$sym ${numFmt.format(sale.loyaltyRedeemed)}'.padLeft(16));
      nl();
    }
    if (sale.loyaltyEarned > 0.01) {
      text('Fidélité gagnée'.padRight(labelW) +
          '+$sym ${numFmt.format(sale.loyaltyEarned)}'.padLeft(16));
      nl();
    }
    if ((sale.customerLoyaltyBalance ?? 0) > 0.01) {
      text('Solde fidélité'.padRight(labelW) +
          '$sym ${numFmt.format(sale.customerLoyaltyBalance!)}'.padLeft(16));
      nl();
    }
    dash();
    nl();

    // ── Statut ─────────────────────────────────────────────────────────────
    esc([0x1B, 0x61, 0x01]);
    esc([0x1B, 0x45, 0x01]);
    final statusLabel = switch (sale.status) {
      'PAID' => '*** PAYÉ ***',
      'PARTIAL' => '*** PAIEMENT PARTIEL ***',
      _ => '*** NON PAYÉ ***',
    };
    text(statusLabel);
    nl();
    esc([0x1B, 0x45, 0x00]);

    if (settings.receiptFooter.isNotEmpty) {
      nl();
      dash();
      text(settings.receiptFooter);
      nl();
    }

    nl(4);
    esc([0x1D, 0x56, 0x42, 0x00]); // coupe partielle

    return Uint8List.fromList(buf);
  }

  // ── ESC/POS return receipt builder ───────────────────────────────────────

  Uint8List _buildEscPosReturn(
      ReturnModel ret, AppSettings settings, List<int> logoBytes) {
    final buf = <int>[];
    final numFmt = NumberFormat('#,##0.00', 'fr');
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm');
    final sym = settings.currencySymbol.trim();

    final cols = settings.paperWidth == 80 ? 48 : 32;
    final nameW = settings.paperWidth == 80 ? 24 : 16;
    final qtyW = settings.paperWidth == 80 ? 6 : 4;
    // Marge de sécurité contre le débordement physique gras+double-strike —
    // voir le commentaire équivalent dans le reçu de vente ci-dessus.
    final rowMargin = 2;
    final totW = cols - nameW - qtyW - rowMargin;
    final labelW = cols - 16;

    void esc(List<int> cmd) => buf.addAll(cmd);
    void text(String t) => buf.addAll(t.codeUnits.map(_escposByte));
    void nl([int n = 1]) {
      for (var i = 0; i < n; i++) {
        buf.add(10);
      }
    }
    void dash() {
      text('-' * cols);
      nl();
    }

    esc([0x1B, 0x40]);
    esc([0x1B, 0x37, 0x07, 0x96, 0x02]);
    esc([0x1B, 0x74, 0x10]);
    esc([0x1B, 0x47, 0x01]);
    esc([0x1B, 0x45, 0x01]);

    if (logoBytes.isNotEmpty) {
      esc([0x1B, 0x61, 0x01]);
      buf.addAll(logoBytes);
      nl();
      esc([0x1B, 0x61, 0x00]);
    }

    esc([0x1B, 0x61, 0x01]);
    esc([0x1D, 0x21, 0x10]);
    text(settings.businessName);
    nl();
    esc([0x1D, 0x21, 0x00]);
    if (settings.address.isNotEmpty) {
      text(settings.address);
      nl();
    }
    if (settings.phone.isNotEmpty) {
      text('Tél: ${settings.phone}');
      nl();
    }
    esc([0x1B, 0x61, 0x00]);
    nl();
    dash();
    nl();

    esc([0x1B, 0x61, 0x01]);
    esc([0x1D, 0x21, 0x10]);
    final typeLabel = ret.returnType == 'sale' ? 'RETOUR VENTE' : 'RETOUR ACHAT';
    text(typeLabel);
    nl();
    esc([0x1D, 0x21, 0x00]);
    esc([0x1B, 0x61, 0x00]);
    nl();

    text('Réf: ${ret.docReference}');
    nl();
    text('Date: ${dateFmt.format(ret.createdAt)}');
    nl();
    if (ret.reason != null && ret.reason!.isNotEmpty) {
      text('Motif: ${ret.reason}');
      nl();
    }
    dash();
    nl();

    text('ARTICLE'.padRight(nameW) +
        'QTE'.padLeft(qtyW) +
        'TOTAL'.padLeft(totW));
    nl();
    for (final item in ret.items) {
      final name = item.productName.padRight(nameW).substring(0, nameW);
      final qty = '${item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 2)}x'.padLeft(qtyW);
      final total = '$sym ${numFmt.format(item.subtotal)}'.padLeft(totW);
      text('$name$qty$total');
      nl();
    }
    dash();
    nl();

    text('Total retourné'.padRight(labelW) +
        '$sym ${numFmt.format(ret.totalReturned)}'.padLeft(16));
    nl();
    esc([0x1B, 0x45, 0x01]);
    text('Remboursement'.padRight(labelW) +
        '$sym ${numFmt.format(ret.refundAmount)}'.padLeft(16));
    nl();
    esc([0x1B, 0x45, 0x00]);
    dash();
    nl();

    esc([0x1B, 0x61, 0x01]);
    text('*** RETOUR ACCEPTÉ ***');
    nl();
    esc([0x1B, 0x61, 0x00]);

    if (settings.receiptFooter.isNotEmpty) {
      nl();
      dash();
      text(settings.receiptFooter);
      nl();
    }

    nl(4);
    esc([0x1D, 0x56, 0x42, 0x00]);

    return Uint8List.fromList(buf);
  }

  // ── ESC/POS restaurant bill builder ──────────────────────────────────────

  Uint8List _buildEscPosRestaurantBill(
    RestaurantOrderModel order,
    AppSettings settings,
    List<int> logoBytes, {
    String? reference,
    double discount = 0,
    double paidAmount = 0,
    String? paymentMethod,
  }) {
    final buf = <int>[];
    final numFmt = NumberFormat('#,##0.00', 'fr');
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm');
    final sym = settings.currencySymbol.trim();
    final isPaid = reference != null;

    final cols = settings.paperWidth == 80 ? 48 : 32;
    final nameW = settings.paperWidth == 80 ? 26 : 18;
    final qtyW = settings.paperWidth == 80 ? 6 : 4;
    // Marge de sécurité contre le débordement physique gras+double-strike —
    // voir le commentaire équivalent dans le reçu de vente.
    final rowMargin = 2;
    final totW = cols - nameW - qtyW - rowMargin;
    final labelW = cols - 16;

    void esc(List<int> cmd) => buf.addAll(cmd);
    void text(String t) => buf.addAll(t.codeUnits.map(_escposByte));
    void nl([int n = 1]) { for (var i = 0; i < n; i++) { buf.add(10); } }
    void dash() { text('-' * cols); nl(); }

    esc([0x1B, 0x40]);                      // Initialize printer
    esc([0x1B, 0x37, 0x07, 0x96, 0x02]);   // ESC 7: heating max dots=7, time=150µs×10, interval=2
    esc([0x1B, 0x74, 0x10]);               // Code page 16 = WPC1252 (é=0xE9, à=0xE0, ç=0xE7…)
    esc([0x1B, 0x47, 0x01]);               // Double-strike ON
    esc([0x1B, 0x45, 0x01]);               // Bold ON global

    if (logoBytes.isNotEmpty) {
      esc([0x1B, 0x61, 0x01]);
      buf.addAll(logoBytes);
      nl();
      esc([0x1B, 0x61, 0x00]);
    }

    // Header
    esc([0x1B, 0x61, 0x01]);
    esc([0x1D, 0x21, 0x10]);
    text(settings.businessName);
    nl();
    esc([0x1D, 0x21, 0x00]);
    if (settings.address.isNotEmpty) { text(settings.address); nl(); }
    if (settings.phone.isNotEmpty) { text('Tél: ${settings.phone}'); nl(); }
    nl();
    esc([0x1B, 0x45, 0x01]);
    text(isPaid ? 'RECU' : 'ADDITION');
    nl();
    esc([0x1B, 0x45, 0x00]);
    esc([0x1B, 0x61, 0x00]);
    dash();
    nl();

    // Order info
    if (reference != null) { text('Ref: $reference'); nl(); }
    text('Date: ${dateFmt.format(haitiNow())}'); nl();
    if (order.tableName != null) { text('Table: ${order.tableName}'); nl(); }
    if (order.waiterName != null) { text('Serveur: ${order.waiterName}'); nl(); }
    text('Couverts: ${order.covers}'); nl();
    dash();
    nl();

    // Items
    text('ARTICLE'.padRight(nameW) +
        'QTE'.padLeft(qtyW) +
        'TOTAL'.padLeft(totW));
    nl();
    for (final item in order.items) {
      final name = item.productName.padRight(nameW).substring(0, nameW);
      final qtyStr = item.quantity == item.quantity.truncateToDouble()
          ? '${item.quantity.toInt()}x'
          : '${item.quantity.toStringAsFixed(1)}x';
      final qty = qtyStr.padLeft(qtyW);
      final total = '$sym${numFmt.format(item.subtotal)}'.padLeft(totW);
      text('$name$qty$total'); nl();
      if (item.notes != null && item.notes!.isNotEmpty) {
        text('  ${item.notes}'); nl();
      }
    }
    dash();
    nl();

    // Totals
    final finalTotal = order.total - discount;
    text('Sous-total'.padRight(labelW) +
        '$sym${numFmt.format(order.subtotal)}'.padLeft(16)); nl();
    if (order.tip > 0) {
      text('Pourboire'.padRight(labelW) +
          '+$sym${numFmt.format(order.tip)}'.padLeft(16)); nl();
    }
    if (discount > 0) {
      text('Remise'.padRight(labelW) +
          '-$sym${numFmt.format(discount)}'.padLeft(16)); nl();
    }
    esc([0x1B, 0x45, 0x01]);
    text('TOTAL'.padRight(labelW) +
        '$sym${numFmt.format(isPaid ? finalTotal : order.total)}'.padLeft(16)); nl();
    esc([0x1B, 0x45, 0x00]);
    if (isPaid) {
      if (paymentMethod != null) {
        final modeLabel = switch (paymentMethod) {
          'CARD' => 'Carte',
          'TRANSFER' => 'Virement',
          _ => 'Especes',
        };
        text('Mode'.padRight(labelW) + modeLabel.padLeft(16)); nl();
      }
      text('Recu'.padRight(labelW) +
          '$sym${numFmt.format(paidAmount)}'.padLeft(16)); nl();
      final change = (paidAmount - finalTotal).clamp(0.0, double.infinity);
      if (change > 0.001) {
        esc([0x1B, 0x45, 0x01]);
        text('Monnaie'.padRight(labelW) +
            '$sym${numFmt.format(change)}'.padLeft(16)); nl();
        esc([0x1B, 0x45, 0x00]);
      }
    }
    dash();
    nl();

    esc([0x1B, 0x61, 0x01]);
    esc([0x1B, 0x45, 0x01]);
    if (isPaid) { text('*** PAYE ***'); nl(); }
    esc([0x1B, 0x45, 0x00]);
    esc([0x1B, 0x61, 0x00]);

    if (settings.receiptFooter.isNotEmpty) {
      nl();
      dash();
      text(settings.receiptFooter); nl();
    }

    nl(4);
    esc([0x1D, 0x56, 0x42, 0x00]);

    return Uint8List.fromList(buf);
  }
}
