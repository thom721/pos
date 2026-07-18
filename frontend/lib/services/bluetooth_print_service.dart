import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:pos_connect/data/models/sale_model.dart';
import 'package:pos_connect/providers/settings_provider.dart';

class BluetoothPrintService {
  BluetoothPrintService._();
  static final BluetoothPrintService instance = BluetoothPrintService._();

  /// Liste les imprimantes Bluetooth déjà appairées.
  Future<List<BluetoothInfo>> getPairedPrinters() async {
    if (kIsWeb) return [];
    try {
      return await PrintBluetoothThermal.pairedBluetooths;
    } catch (_) {
      return [];
    }
  }

  /// Connecte à l'imprimante dont le [mac] est mémorisé.
  Future<bool> connect(String mac) async {
    if (mac.isEmpty) return false;
    try {
      return await PrintBluetoothThermal.connect(macPrinterAddress: mac);
    } catch (_) {
      return false;
    }
  }

  Future<bool> get isConnected async {
    try {
      return await PrintBluetoothThermal.connectionStatus;
    } catch (_) {
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      await PrintBluetoothThermal.disconnect;
    } catch (_) {}
  }

  /// Imprime un reçu de vente.
  /// Retourne `true` si réussi.
  Future<bool> printReceipt(SaleModel sale, AppSettings settings) async {
    final mac = settings.bluetoothPrinterMac;
    if (mac.isEmpty) return false;

    // Connexion auto
    final connected = await connect(mac);
    if (!connected) return false;

    final bytes = _buildEscPos(sale, settings);
    try {
      return await PrintBluetoothThermal.writeBytes(bytes);
    } catch (_) {
      return false;
    }
  }

  /// Génère les octets ESC/POS pour une imprimante 58 mm ou 80 mm.
  Uint8List _buildEscPos(SaleModel sale, AppSettings settings) {
    final buf = <int>[];
    final numFmt = NumberFormat('#,##0.00', 'fr');
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm');
    final sym = settings.currencySymbol.trim();

    // ── Commandes ESC/POS ──────────────────────────────────────────────────
    void esc(List<int> cmd) => buf.addAll(cmd);
    void text(String t) => buf.addAll(t.codeUnits);
    void nl([int n = 1]) { for (var i = 0; i < n; i++) { buf.add(10); } }
    void dash() { text('--------------------------------'); nl(); }

    // Init
    esc([0x1B, 0x40]);
    // Code page Latin-1 pour les accents français
    esc([0x1B, 0x74, 0x02]);

    // ── En-tête ────────────────────────────────────────────────────────────
    esc([0x1B, 0x61, 0x01]); // centrer
    esc([0x1D, 0x21, 0x10]); // double hauteur
    text(settings.businessName); nl();
    esc([0x1D, 0x21, 0x00]); // normal
    if (settings.address.isNotEmpty) { text(settings.address); nl(); }
    if (settings.phone.isNotEmpty)   { text('Tél: ${settings.phone}'); nl(); }
    esc([0x1B, 0x61, 0x00]); // aligner gauche
    nl();
    dash();

    // ── Infos vente ────────────────────────────────────────────────────────
    text('Réf: ${sale.reference}'); nl();
    text('Date: ${dateFmt.format(sale.createdAt)}'); nl();
    if (sale.customerName != null) { text('Client: ${sale.customerName}'); nl(); }
    if (sale.userFullName != null) { text('Caissier: ${sale.userFullName}'); nl(); }
    dash();

    // ── Articles ───────────────────────────────────────────────────────────
    for (final item in sale.items) {
      final name = (item.productName ?? 'Article').padRight(16).substring(0, 16);
      final qty  = '${item.quantity.toInt()}x'.padLeft(4);
      final total = '$sym ${numFmt.format(item.subtotal)}'.padLeft(12);
      text('$name$qty$total'); nl();
    }
    dash();

    // ── Totaux ─────────────────────────────────────────────────────────────
    if (sale.discount > 0) {
      text('Sous-total'.padRight(20) + '$sym ${numFmt.format(sale.totalAmount)}'.padLeft(12)); nl();
      text('Remise'.padRight(20)     + '-$sym ${numFmt.format(sale.discount)}'.padLeft(11)); nl();
    }
    esc([0x1B, 0x45, 0x01]); // gras
    text('TOTAL'.padRight(20) + '$sym ${numFmt.format(sale.finalAmount)}'.padLeft(12)); nl();
    esc([0x1B, 0x45, 0x00]); // normal
    text('Payé'.padRight(20)  + '$sym ${numFmt.format(sale.paidAmount)}'.padLeft(12)); nl();
    if (sale.balance.abs() > 0.01) {
      final label = sale.balance > 0 ? 'Reste' : 'Monnaie';
      text(label.padRight(20) + '$sym ${numFmt.format(sale.balance.abs())}'.padLeft(12)); nl();
    }
    dash();

    // ── Statut ─────────────────────────────────────────────────────────────
    esc([0x1B, 0x61, 0x01]); // centrer
    esc([0x1B, 0x45, 0x01]); // gras
    final statusLabel = switch (sale.status) {
      'PAID'    => '*** PAYÉ ***',
      'PARTIAL' => '*** PAIEMENT PARTIEL ***',
      _         => '*** NON PAYÉ ***',
    };
    text(statusLabel); nl();
    esc([0x1B, 0x45, 0x00]);

    if (settings.receiptFooter.isNotEmpty) {
      nl();
      text(settings.receiptFooter); nl();
    }

    // Avancer papier + coupe
    nl(4);
    esc([0x1D, 0x56, 0x42, 0x00]); // coupe partielle

    return Uint8List.fromList(buf);
  }
}
