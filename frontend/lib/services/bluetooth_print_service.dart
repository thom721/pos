import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/restaurant_model.dart';
import 'package:pos_connect/data/models/sale_model.dart';
import 'package:pos_connect/providers/settings_provider.dart';

class BluetoothPrintService {
  BluetoothPrintService._();
  static final BluetoothPrintService instance = BluetoothPrintService._();

  static const _ch = MethodChannel('pos_connect/bluetooth');

  Future<List<BluetoothInfo>> getPairedPrinters() async {
    if (kIsWeb) return [];
    try {
      return await PrintBluetoothThermal.pairedBluetooths;
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
      final res = await dio.get(
        settings.logoPath,
        options: Options(responseType: ResponseType.bytes),
      ).timeout(const Duration(seconds: 5));
      final rawBytes = Uint8List.fromList(res.data as List<int>);

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
    final nameW = settings.paperWidth == 80 ? 24 : 16;
    final qtyW = settings.paperWidth == 80 ? 6 : 4;
    final totW = cols - nameW - qtyW;
    final labelW = cols - 16;

    void esc(List<int> cmd) => buf.addAll(cmd);
    void text(String t) => buf.addAll(t.codeUnits);
    void nl([int n = 1]) {
      for (var i = 0; i < n; i++) {
        buf.add(10);
      }
    }
    void dash() {
      text('-' * cols);
      nl();
    }

    // Init + code page Latin-1
    esc([0x1B, 0x40]);
    esc([0x1B, 0x74, 0x02]);

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

    // ── Articles ───────────────────────────────────────────────────────────
    for (final item in sale.items) {
      final name =
          (item.productName ?? 'Article').padRight(nameW).substring(0, nameW);
      final qty = '${item.quantity.toInt()}x'.padLeft(qtyW);
      final total = '$sym ${numFmt.format(item.subtotal)}'.padLeft(totW);
      text('$name$qty$total');
      nl();
    }
    dash();

    // ── Totaux ─────────────────────────────────────────────────────────────
    if (sale.discount > 0) {
      text('Sous-total'.padRight(labelW) +
          '$sym ${numFmt.format(sale.totalAmount)}'.padLeft(16));
      nl();
      text('Remise'.padRight(labelW) +
          '-$sym ${numFmt.format(sale.discount)}'.padLeft(16));
      nl();
    }
    esc([0x1B, 0x45, 0x01]);
    text('TOTAL'.padRight(labelW) +
        '$sym ${numFmt.format(sale.finalAmount)}'.padLeft(16));
    nl();
    esc([0x1B, 0x45, 0x00]);
    text('Payé'.padRight(labelW) +
        '$sym ${numFmt.format(sale.paidAmount)}'.padLeft(16));
    nl();
    if (sale.balance.abs() > 0.01) {
      final label = sale.balance > 0 ? 'Reste' : 'Monnaie';
      text(label.padRight(labelW) +
          '$sym ${numFmt.format(sale.balance.abs())}'.padLeft(16));
      nl();
    }
    dash();

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
      text(settings.receiptFooter);
      nl();
    }

    nl(4);
    esc([0x1D, 0x56, 0x42, 0x00]); // coupe partielle

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
    final totW = cols - nameW - qtyW;
    final labelW = cols - 16;

    void esc(List<int> cmd) => buf.addAll(cmd);
    void text(String t) => buf.addAll(t.codeUnits);
    void nl([int n = 1]) { for (var i = 0; i < n; i++) { buf.add(10); } }
    void dash() { text('-' * cols); nl(); }

    esc([0x1B, 0x40]);
    esc([0x1B, 0x74, 0x02]);

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

    // Order info
    if (reference != null) { text('Ref: $reference'); nl(); }
    text('Date: ${dateFmt.format(DateTime.now())}'); nl();
    if (order.tableName != null) { text('Table: ${order.tableName}'); nl(); }
    if (order.waiterName != null) { text('Serveur: ${order.waiterName}'); nl(); }
    text('Couverts: ${order.covers}'); nl();
    dash();

    // Items
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

    esc([0x1B, 0x61, 0x01]);
    esc([0x1B, 0x45, 0x01]);
    if (isPaid) { text('*** PAYE ***'); nl(); }
    esc([0x1B, 0x45, 0x00]);
    esc([0x1B, 0x61, 0x00]);

    if (settings.receiptFooter.isNotEmpty) {
      nl();
      text(settings.receiptFooter); nl();
    }

    nl(4);
    esc([0x1D, 0x56, 0x42, 0x00]);

    return Uint8List.fromList(buf);
  }
}
