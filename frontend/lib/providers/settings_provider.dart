import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_connect/core/constants.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/providers/auth_provider.dart';
import 'package:pos_connect/providers/license_provider.dart';
import 'package:pos_connect/data/models/warehouse_model.dart';
import 'package:pos_connect/providers/warehouse_provider.dart';
import 'package:pos_connect/services/logo_cache_service.dart';

const _kKeyPrefix = 'pos_app_settings';

/// Colonnes disponibles pour le tableau "Détail des ventes" (écran + CSV + PDF).
const kReportColumnDefs = [
  ('reference', 'Référence'),
  ('date', 'Date'),
  ('client', 'Client'),
  ('cashier', 'Caissier'),
  ('total', 'Total'),
  ('paid', 'Payé'),
  ('discount', 'Remise'),
  ('credit', 'Crédit'),
  ('status', 'Statut'),
  ('category', 'Catégorie'),
  ('product', 'Produit'),
];

/// État actuel préservé pour qui n'a jamais touché ce réglage —
/// catégorie/produit désactivés par défaut.
const kDefaultReportColumns = [
  'reference', 'date', 'client', 'cashier', 'total', 'paid',
  'discount', 'credit', 'status',
];

class AppSettings {
  final String businessName;
  final String businessType; // commerce | restaurant | business | hotel
  final String currency;     // HTG | USD | EUR
  final String currencySymbol;
  final String phone;
  final String email;
  final String address;
  final String logoPath;
  final double taxRate;
  final bool showTax;
  final String receiptFooter;
  // Exchange rates: 1 foreign unit = X HTG (taux du jour)
  final double rateUsd;
  final double rateEur;
  // Printer configuration
  final String posPrinterName;
  final bool posAutoPrint;
  final String docPrinterName;
  final bool docAutoPrint;
  // Bluetooth thermal printer
  final String bluetoothPrinterMac;
  final String bluetoothPrinterName;
  // Paper width in mm — device-specific, stored locally only
  final int paperWidth; // 80 | 58 | 48
  // Receipt text darkness 1–5 — device-specific, stored locally only
  final int receiptDarkness; // 1=pâle … 5=noir pur
  // Hotel mode — check-in fields config [{label, required, onReceipt}]
  final List<Map<String, dynamic>> hotelCheckinFields;
  // Règles métier
  final bool allowSaleEdit;      // Modifier une vente après enregistrement
  final bool allowCashierCredit; // Caissier peut créer une dette (paiement partiel)
  // Colonnes affichées dans le tableau "Détail des ventes" (écran + CSV + PDF)
  final List<String> reportColumns;
  // Produits composés : "manual" (ajustement page Produits) ou "purchase_receipt"
  final String compositeStockTrigger;
  // Système de Sabotage — champs additionnels du client [{label, required}]
  // (nom/prenom/telephone/adresse sont toujours obligatoires, jamais ici)
  final List<Map<String, dynamic>> clientSabotageFields;
  // Fidélisation — crédit en % du montant de la vente sur un solde client
  // utilisable comme moyen de paiement sur une vente future.
  final bool loyaltyEnabled;
  final double loyaltyPercent;
  // Alerte email stock bas — envoyée aux rôles listés quand un produit
  // franchit son seuil d'alerte (Product.alert_stock) vers le bas.
  final bool lowStockAlertEnabled;
  final List<String> lowStockAlertRoles;

  const AppSettings({
    this.businessName = 'Mon Commerce',
    this.businessType = 'commerce',
    this.currency = 'HTG',
    this.currencySymbol = 'HTG ',
    this.phone = '',
    this.email = '',
    this.address = '',
    this.logoPath = '',
    this.taxRate = 0.0,
    this.showTax = false,
    this.receiptFooter = 'Merci pour votre achat !',
    this.rateUsd = 130.0,
    this.rateEur = 140.0,
    this.posPrinterName = '',
    this.posAutoPrint = false,
    this.docPrinterName = '',
    this.docAutoPrint = false,
    this.bluetoothPrinterMac = '',
    this.bluetoothPrinterName = '',
    this.paperWidth = 80,
    this.receiptDarkness = 4,
    this.hotelCheckinFields = const [],
    this.allowSaleEdit = false,
    this.allowCashierCredit = false,
    this.reportColumns = kDefaultReportColumns,
    this.compositeStockTrigger = 'manual',
    this.clientSabotageFields = const [],
    this.loyaltyEnabled = false,
    this.loyaltyPercent = 0.0,
    this.lowStockAlertEnabled = false,
    this.lowStockAlertRoles = const [],
  });

  AppSettings copyWith({
    String? businessName,
    String? businessType,
    String? currency,
    String? currencySymbol,
    String? phone,
    String? email,
    String? address,
    String? logoPath,
    double? taxRate,
    bool? showTax,
    String? receiptFooter,
    double? rateUsd,
    double? rateEur,
    String? posPrinterName,
    bool? posAutoPrint,
    String? docPrinterName,
    bool? docAutoPrint,
    String? bluetoothPrinterMac,
    String? bluetoothPrinterName,
    int? paperWidth,
    int? receiptDarkness,
    List<Map<String, dynamic>>? hotelCheckinFields,
    bool? allowSaleEdit,
    bool? allowCashierCredit,
    List<String>? reportColumns,
    String? compositeStockTrigger,
    List<Map<String, dynamic>>? clientSabotageFields,
    bool? loyaltyEnabled,
    double? loyaltyPercent,
    bool? lowStockAlertEnabled,
    List<String>? lowStockAlertRoles,
  }) =>
      AppSettings(
        businessName: businessName ?? this.businessName,
        businessType: businessType ?? this.businessType,
        currency: currency ?? this.currency,
        currencySymbol: currencySymbol ?? this.currencySymbol,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        address: address ?? this.address,
        logoPath: logoPath ?? this.logoPath,
        taxRate: taxRate ?? this.taxRate,
        showTax: showTax ?? this.showTax,
        receiptFooter: receiptFooter ?? this.receiptFooter,
        rateUsd: rateUsd ?? this.rateUsd,
        rateEur: rateEur ?? this.rateEur,
        posPrinterName: posPrinterName ?? this.posPrinterName,
        posAutoPrint: posAutoPrint ?? this.posAutoPrint,
        docPrinterName: docPrinterName ?? this.docPrinterName,
        docAutoPrint: docAutoPrint ?? this.docAutoPrint,
        bluetoothPrinterMac: bluetoothPrinterMac ?? this.bluetoothPrinterMac,
        bluetoothPrinterName: bluetoothPrinterName ?? this.bluetoothPrinterName,
        paperWidth: paperWidth ?? this.paperWidth,
        receiptDarkness: receiptDarkness ?? this.receiptDarkness,
        hotelCheckinFields: hotelCheckinFields ?? this.hotelCheckinFields,
        allowSaleEdit: allowSaleEdit ?? this.allowSaleEdit,
        allowCashierCredit: allowCashierCredit ?? this.allowCashierCredit,
        reportColumns: reportColumns ?? this.reportColumns,
        compositeStockTrigger: compositeStockTrigger ?? this.compositeStockTrigger,
        clientSabotageFields: clientSabotageFields ?? this.clientSabotageFields,
        loyaltyEnabled: loyaltyEnabled ?? this.loyaltyEnabled,
        loyaltyPercent: loyaltyPercent ?? this.loyaltyPercent,
        lowStockAlertEnabled: lowStockAlertEnabled ?? this.lowStockAlertEnabled,
        lowStockAlertRoles: lowStockAlertRoles ?? this.lowStockAlertRoles,
      );

  // Serialize to API (snake_case)
  Map<String, dynamic> toApiJson() => {
        'business_name': businessName,
        'business_type': businessType,
        'currency': currency,
        'currency_symbol': currencySymbol,
        'phone': phone,
        'email': email,
        'address': address,
        'logo_path': logoPath,
        'tax_rate': taxRate,
        'show_tax': showTax,
        'receipt_footer': receiptFooter,
        'rate_usd': rateUsd,
        'rate_eur': rateEur,
        'pos_printer_name': posPrinterName,
        'pos_auto_print': posAutoPrint,
        'doc_printer_name': docPrinterName,
        'doc_auto_print': docAutoPrint,
        'bluetooth_printer_mac': bluetoothPrinterMac,
        'bluetooth_printer_name': bluetoothPrinterName,
        if (hotelCheckinFields.isNotEmpty)
          'hotel_checkin_fields': hotelCheckinFields
              .map((f) => {
                    'label':      f['label']     ?? '',
                    'required':   f['required']  ?? false,
                    'on_receipt': f['onReceipt'] ?? false,
                  })
              .toList(),
        'allow_sale_edit':      allowSaleEdit,
        'allow_cashier_credit': allowCashierCredit,
        'report_columns': reportColumns,
        'composite_stock_trigger': compositeStockTrigger,
        if (clientSabotageFields.isNotEmpty)
          'client_sabotage_fields': clientSabotageFields
              .map((f) => {'label': f['label'] ?? '', 'required': f['required'] ?? false})
              .toList(),
        'loyalty_enabled': loyaltyEnabled,
        'loyalty_percent': loyaltyPercent,
        'low_stock_alert_enabled': lowStockAlertEnabled,
        'low_stock_alert_roles': lowStockAlertRoles,
      };

  // Parse from API response (snake_case)
  factory AppSettings.fromApiJson(Map<String, dynamic> j) => AppSettings(
        businessName: j['business_name'] as String? ?? 'Mon Commerce',
        businessType: j['business_type'] as String? ?? 'commerce',
        currency: j['currency'] as String? ?? 'HTG',
        currencySymbol: j['currency_symbol'] as String? ?? 'HTG ',
        phone: j['phone'] as String? ?? '',
        email: j['email'] as String? ?? '',
        address: j['address'] as String? ?? '',
        logoPath: j['logo_path'] as String? ?? '',
        taxRate: (j['tax_rate'] as num?)?.toDouble() ?? 0.0,
        showTax: j['show_tax'] as bool? ?? false,
        receiptFooter: j['receipt_footer'] as String? ?? 'Merci pour votre achat !',
        rateUsd: (j['rate_usd'] as num?)?.toDouble() ?? 130.0,
        rateEur: (j['rate_eur'] as num?)?.toDouble() ?? 140.0,
        posPrinterName: j['pos_printer_name'] as String? ?? '',
        posAutoPrint: j['pos_auto_print'] as bool? ?? false,
        docPrinterName: j['doc_printer_name'] as String? ?? '',
        docAutoPrint: j['doc_auto_print'] as bool? ?? false,
        bluetoothPrinterMac: j['bluetooth_printer_mac'] as String? ?? '',
        bluetoothPrinterName: j['bluetooth_printer_name'] as String? ?? '',
        hotelCheckinFields: _parseCheckinFields(j['hotel_checkin_fields']),
        allowSaleEdit:      j['allow_sale_edit']      as bool? ?? false,
        allowCashierCredit: j['allow_cashier_credit'] as bool? ?? false,
        reportColumns: _parseReportColumns(j['report_columns']),
        compositeStockTrigger: _parseCompositeStockTrigger(j['composite_stock_trigger']),
        clientSabotageFields: _parseSabotageFields(j['client_sabotage_fields']),
        loyaltyEnabled: j['loyalty_enabled'] as bool? ?? false,
        loyaltyPercent: (j['loyalty_percent'] as num?)?.toDouble() ?? 0.0,
        lowStockAlertEnabled: j['low_stock_alert_enabled'] as bool? ?? false,
        lowStockAlertRoles: _parseStringList(j['low_stock_alert_roles']),
      );

  static List<String> _parseStringList(dynamic raw) {
    if (raw == null || raw is! List) return const [];
    return raw.map((e) => e.toString()).toList();
  }

  /// Une chaîne vide (pas seulement null) doit retomber sur 'manual' — sinon
  /// le DropdownButtonFormField de la page Paramètres plante (aucun item ne
  /// correspond à '').
  static String _parseCompositeStockTrigger(dynamic raw) {
    final v = raw as String?;
    return (v == null || v.isEmpty) ? 'manual' : v;
  }

  static List<Map<String, dynamic>> _parseSabotageFields(dynamic raw) {
    if (raw == null || raw is! List) return [];
    return raw.map((e) {
      final m = e as Map<String, dynamic>;
      return <String, dynamic>{'label': m['label'] ?? '', 'required': m['required'] ?? false};
    }).toList();
  }

  static List<String> _parseReportColumns(dynamic raw) {
    if (raw == null || raw is! List || raw.isEmpty) return kDefaultReportColumns;
    return raw.map((e) => e.toString()).toList();
  }

  static List<Map<String, dynamic>> _parseCheckinFields(dynamic raw) {
    if (raw == null) return [];
    if (raw is! List) return [];
    return raw.map((e) {
      final m = e as Map<String, dynamic>;
      return <String, dynamic>{
        'label':      m['label']      ?? m['label']      ?? '',
        'required':   m['required']   ?? false,
        'onReceipt':  m['on_receipt'] ?? m['onReceipt']  ?? false,
      };
    }).toList();
  }

  // Serialize for local cache (camelCase — backward compat)
  Map<String, dynamic> toJson() => {
        'businessName': businessName,
        'businessType': businessType,
        'currency': currency,
        'currencySymbol': currencySymbol,
        'phone': phone,
        'email': email,
        'address': address,
        'logoPath': logoPath,
        'taxRate': taxRate,
        'showTax': showTax,
        'receiptFooter': receiptFooter,
        'rateUsd': rateUsd,
        'rateEur': rateEur,
        'posPrinterName': posPrinterName,
        'posAutoPrint': posAutoPrint,
        'docPrinterName': docPrinterName,
        'docAutoPrint': docAutoPrint,
        'bluetoothPrinterMac': bluetoothPrinterMac,
        'bluetoothPrinterName': bluetoothPrinterName,
        'paperWidth': paperWidth,
        'receiptDarkness': receiptDarkness,
        'hotelCheckinFields': hotelCheckinFields,
        'allowSaleEdit':      allowSaleEdit,
        'allowCashierCredit': allowCashierCredit,
        'reportColumns': reportColumns,
        'compositeStockTrigger': compositeStockTrigger,
        'clientSabotageFields': clientSabotageFields,
        'loyaltyEnabled': loyaltyEnabled,
        'loyaltyPercent': loyaltyPercent,
        'lowStockAlertEnabled': lowStockAlertEnabled,
        'lowStockAlertRoles': lowStockAlertRoles,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        businessName: j['businessName'] as String? ?? 'Mon Commerce',
        businessType: j['businessType'] as String? ?? 'commerce',
        currency: j['currency'] as String? ?? 'HTG',
        currencySymbol: j['currencySymbol'] as String? ?? 'HTG ',
        phone: j['phone'] as String? ?? '',
        email: j['email'] as String? ?? '',
        address: j['address'] as String? ?? '',
        logoPath: j['logoPath'] as String? ?? '',
        taxRate: (j['taxRate'] as num?)?.toDouble() ?? 0.0,
        showTax: j['showTax'] as bool? ?? false,
        receiptFooter: j['receiptFooter'] as String? ?? 'Merci pour votre achat !',
        rateUsd: (j['rateUsd'] as num?)?.toDouble() ?? 130.0,
        rateEur: (j['rateEur'] as num?)?.toDouble() ?? 140.0,
        posPrinterName: j['posPrinterName'] as String? ?? '',
        posAutoPrint: j['posAutoPrint'] as bool? ?? false,
        docPrinterName: j['docPrinterName'] as String? ?? '',
        docAutoPrint: j['docAutoPrint'] as bool? ?? false,
        bluetoothPrinterMac: j['bluetoothPrinterMac'] as String? ?? '',
        bluetoothPrinterName: j['bluetoothPrinterName'] as String? ?? '',
        paperWidth: (j['paperWidth'] as num?)?.toInt() ?? 80,
        receiptDarkness: (j['receiptDarkness'] as num?)?.toInt() ?? 4,
        hotelCheckinFields: _parseCheckinFields(j['hotelCheckinFields']),
        allowSaleEdit:      j['allowSaleEdit']      as bool? ?? false,
        allowCashierCredit: j['allowCashierCredit'] as bool? ?? false,
        reportColumns: _parseReportColumns(j['reportColumns']),
        compositeStockTrigger: _parseCompositeStockTrigger(j['compositeStockTrigger']),
        clientSabotageFields: _parseSabotageFields(j['clientSabotageFields']),
        loyaltyEnabled: j['loyaltyEnabled'] as bool? ?? false,
        loyaltyPercent: (j['loyaltyPercent'] as num?)?.toDouble() ?? 0.0,
        lowStockAlertEnabled: j['lowStockAlertEnabled'] as bool? ?? false,
        lowStockAlertRoles: _parseStringList(j['lowStockAlertRoles']),
      );
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  final Ref _ref;
  final FlutterSecureStorage _storage;
  Timer? _syncTimer;

  SettingsNotifier(this._ref, this._storage) : super(const AppSettings()) {
    // Reload when the authenticated user changes
    _ref.listen<AuthState>(authProvider, (prev, next) {
      if (prev?.user?.id != next.user?.id) {
        _load();
        if (next.user != null) {
          _startSyncTimer();
        } else {
          _syncTimer?.cancel();
        }
      }
    });
    // Reload when the active warehouse changes (each depot has its own config)
    _ref.listen<WarehouseModel?>(activeWarehouseProvider, (prev, next) {
      if (prev?.id != next?.id) {
        _load();
      }
    });
    _load();
    _startSyncTimer();
  }

  /// Filet de sécurité si le WebSocket temps-réel (app.dart) est déconnecté —
  /// sur Android/bureau, reload() est normalement déclenché instantanément
  /// à chaque mutation serveur (paiement approuvé, permissions modifiées,
  /// etc.) via le push WebSocket, pas par ce timer.
  void _startSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _refreshAll();
    });
  }

  /// Rafraîchit en arrière-plan : config, rôles utilisateur, licence et tenant.
  Future<void> _refreshAll() async {
    if (_ref.read(authProvider).user == null) return;
    await _load();
    await _ref.read(authProvider.notifier).refreshCurrentUser();
    _ref.invalidate(licenseProvider);
    _ref.invalidate(tenantProvider);
    _ref.read(billingEpochProvider.notifier).state++;
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  /// Returns a (tenant + warehouse)-scoped cache key so each depot has its own local cache.
  Future<String> _cacheKey() async {
    final prefs = await SharedPreferences.getInstance();
    final warehouseId = _ref.read(activeWarehouseProvider)?.id;
    final tenantRaw = prefs.getString(AppConstants.tenantKey);
    if (tenantRaw != null) {
      try {
        final tenant = jsonDecode(tenantRaw) as Map<String, dynamic>;
        final tenantId = tenant['id'] as String?;
        if (tenantId != null && tenantId.isNotEmpty) {
          if (warehouseId != null && warehouseId.isNotEmpty) {
            return '${_kKeyPrefix}_${tenantId}_$warehouseId';
          }
          return '${_kKeyPrefix}_$tenantId';
        }
      } catch (_) {}
    }
    // Local mode: scope by user + warehouse
    final userId = _ref.read(authProvider).user?.id;
    if (userId != null && userId.isNotEmpty) {
      if (warehouseId != null && warehouseId.isNotEmpty) {
        return '${_kKeyPrefix}_${userId}_$warehouseId';
      }
      return '${_kKeyPrefix}_$userId';
    }
    return _kKeyPrefix;
  }

  Future<void> _load() async {
    // Skip if not authenticated yet — the listener will re-trigger after login.
    final authState = _ref.read(authProvider);
    if (authState.user == null) return;

    final key = await _cacheKey();
    // Apply local cache first for fast startup
    final raw = await _storage.read(key: key);
    AppSettings? local;
    if (raw != null) {
      try {
        local = AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        state = local;
      } catch (_) {}
    }
    // Paramètres device-only depuis la clé fixe (non-scopée par warehouse)
    // → lus UNE FOIS, jamais écrasés par la race condition du double _load().
    int? devicePaperWidth;
    int? deviceReceiptDarkness;
    String? deviceBtMac;
    String? deviceBtName;
    bool? deviceAutoPrint;
    try {
      final prefs = await SharedPreferences.getInstance();
      devicePaperWidth      = prefs.getInt('device_paper_width');
      deviceReceiptDarkness = prefs.getInt('device_receipt_darkness');
      deviceBtMac           = prefs.getString('device_bt_mac');
      deviceBtName          = prefs.getString('device_bt_name');
      deviceAutoPrint       = prefs.getBool('device_pos_auto_print');
    } catch (_) {}

    // Sync from API (authoritative for shared fields only)
    try {
      var warehouseId = _ref.read(activeWarehouseProvider)?.id;
      // If active warehouse isn't resolved yet, use the user's first assigned
      // warehouse so the backend returns the right business_type immediately.
      if (warehouseId == null) {
        final ids = _ref.read(authProvider).user?.warehouseIds ?? [];
        if (ids.isNotEmpty) warehouseId = ids.first;
      }
      final queryParams = warehouseId != null ? '?warehouse_id=$warehouseId' : '';
      final res = await dio.get('/api/config/$queryParams');
      if (res.statusCode == 200) {
        final apiSettings = AppSettings.fromApiJson(res.data as Map<String, dynamic>);
        // Paramètres device-only : clé fixe > clé scopée > état courant
        state = apiSettings.copyWith(
          bluetoothPrinterMac:  deviceBtMac           ?? local?.bluetoothPrinterMac  ?? state.bluetoothPrinterMac,
          bluetoothPrinterName: deviceBtName           ?? local?.bluetoothPrinterName ?? state.bluetoothPrinterName,
          paperWidth:           devicePaperWidth        ?? local?.paperWidth           ?? state.paperWidth,
          receiptDarkness:      deviceReceiptDarkness   ?? local?.receiptDarkness      ?? state.receiptDarkness,
          posAutoPrint:         deviceAutoPrint          ?? local?.posAutoPrint         ?? state.posAutoPrint,
        );
        await _storage.write(key: key, value: jsonEncode(state.toJson()));
        // Rafraîchit le cache local du logo dès qu'on est en ligne — les
        // impressions (PDF, Bluetooth) l'utilisent en priorité et restent
        // ainsi disponibles hors ligne (voir LogoCacheService).
        if (state.logoPath.isNotEmpty) {
          unawaited(LogoCacheService.instance.getLogoBytes(state.logoPath));
        }
      }
    } catch (_) {
      // Network unavailable — local cache already applied above
      // Appliquer quand même les valeurs device-only sur le cache local
      if (devicePaperWidth != null || deviceReceiptDarkness != null ||
          deviceBtMac != null || deviceBtName != null || deviceAutoPrint != null) {
        state = state.copyWith(
          bluetoothPrinterMac:  deviceBtMac          ?? state.bluetoothPrinterMac,
          bluetoothPrinterName: deviceBtName          ?? state.bluetoothPrinterName,
          paperWidth:           devicePaperWidth       ?? state.paperWidth,
          receiptDarkness:      deviceReceiptDarkness  ?? state.receiptDarkness,
          posAutoPrint:         deviceAutoPrint         ?? state.posAutoPrint,
        );
      }
    }

    // Si businessName est toujours le placeholder, utiliser le nom du tenant
    // (stocké lors du login dans SharedPreferences) comme fallback.
    if (state.businessName == 'Mon Commerce' || state.businessName.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final tenantRaw = prefs.getString(AppConstants.tenantKey);
        if (tenantRaw != null) {
          final tenant = jsonDecode(tenantRaw) as Map<String, dynamic>;
          final tenantName = tenant['business_name'] as String?;
          if (tenantName != null && tenantName.isNotEmpty) {
            state = state.copyWith(businessName: tenantName);
          }
        }
      } catch (_) {}
    }
  }

  /// Recharge config + user + licence + tenant (appelé au resume de l'app,
  /// et par app.dart à chaque push WebSocket "sync" — voir _triggerSync()).
  Future<void> reload() => _refreshAll();

  Future<void> save(AppSettings settings) async {
    state = settings;
    try {
      final warehouseId = _ref.read(activeWarehouseProvider)?.id;
      final queryParams = warehouseId != null ? '?warehouse_id=$warehouseId' : '';
      await dio.put('/api/config/$queryParams', data: settings.toApiJson());
    } catch (_) {}
    // Paramètres partagés → clé scopée par tenant/warehouse
    final key = await _cacheKey();
    try {
      await _storage.write(key: key, value: jsonEncode(settings.toJson()));
    } catch (_) {}
    // Paramètres device-only (papier, imprimante BT) → clé fixe non-scopée
    // pour éviter la race condition entre les deux _load() au démarrage.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('device_paper_width', settings.paperWidth);
      await prefs.setInt('device_receipt_darkness', settings.receiptDarkness);
      await prefs.setString('device_bt_mac', settings.bluetoothPrinterMac);
      await prefs.setString('device_bt_name', settings.bluetoothPrinterName);
      await prefs.setBool('device_pos_auto_print', settings.posAutoPrint);
    } catch (_) {}
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier(ref, const FlutterSecureStorage());
});
