import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_connect/core/constants.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/providers/auth_provider.dart';

const _kKeyPrefix = 'pos_app_settings';

class AppSettings {
  final String businessName;
  final String businessType; // commerce | restaurant | depot
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
  final int paperWidth; // 80 | 58

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
      );

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
      );
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  final Ref _ref;
  final FlutterSecureStorage _storage;

  SettingsNotifier(this._ref, this._storage) : super(const AppSettings()) {
    _ref.listen<AuthState>(authProvider, (prev, next) {
      // Reload settings whenever the authenticated user changes
      if (prev?.user?.id != next.user?.id) {
        _load();
      }
    });
    _load();
  }

  /// Returns a tenant-scoped cache key so different tenants never share local cache.
  Future<String> _cacheKey() async {
    final prefs = await SharedPreferences.getInstance();
    final tenantRaw = prefs.getString(AppConstants.tenantKey);
    if (tenantRaw != null) {
      try {
        final tenant = jsonDecode(tenantRaw) as Map<String, dynamic>;
        final id = tenant['id'] as String?;
        if (id != null && id.isNotEmpty) return '${_kKeyPrefix}_$id';
      } catch (_) {}
    }
    // Local mode or no tenant: use user-scoped key from auth state
    final userId = _ref.read(authProvider).user?.id;
    if (userId != null && userId.isNotEmpty) return '${_kKeyPrefix}_$userId';
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
    // Sync from API (authoritative for shared fields only)
    try {
      final res = await dio.get('/api/config/');
      if (res.statusCode == 200) {
        final apiSettings = AppSettings.fromApiJson(res.data as Map<String, dynamic>);
        // Preserve device-specific fields that the API doesn't know about
        state = apiSettings.copyWith(
          bluetoothPrinterMac: local?.bluetoothPrinterMac ?? state.bluetoothPrinterMac,
          bluetoothPrinterName: local?.bluetoothPrinterName ?? state.bluetoothPrinterName,
          paperWidth: local?.paperWidth ?? state.paperWidth,
        );
        await _storage.write(key: key, value: jsonEncode(state.toJson()));
      }
    } catch (_) {
      // Network unavailable — local cache already applied above
    }
  }

  Future<void> save(AppSettings settings) async {
    state = settings;
    try {
      await dio.put('/api/config/', data: settings.toApiJson());
    } catch (_) {}
    final key = await _cacheKey();
    try {
      await _storage.write(key: key, value: jsonEncode(settings.toJson()));
    } catch (_) {}
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier(ref, const FlutterSecureStorage());
});
