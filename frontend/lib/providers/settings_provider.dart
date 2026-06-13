import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pos_connect/data/api/api_client.dart';

const _kKey = 'pos_app_settings';

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
      );
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  final FlutterSecureStorage _storage;

  SettingsNotifier(this._storage) : super(const AppSettings()) {
    _load();
  }

  Future<void> _load() async {
    // Try local cache first for fast startup
    final raw = await _storage.read(key: _kKey);
    if (raw != null) {
      try {
        state = AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    // Then sync from API (authoritative source for multi-device support)
    try {
      final res = await dio.get('/api/config/');
      if (res.statusCode == 200) {
        final apiSettings = AppSettings.fromApiJson(
            res.data as Map<String, dynamic>);
        state = apiSettings;
        // Update local cache silently
        await _storage.write(key: _kKey, value: jsonEncode(apiSettings.toJson()));
      }
    } catch (_) {
      // Network unavailable — local cache is already applied above
    }
  }

  Future<void> save(AppSettings settings) async {
    state = settings;
    // Save to API (primary — shared across all devices)
    try {
      await dio.put('/api/config/', data: settings.toApiJson());
    } catch (_) {
      // Offline — local cache will sync on next load
    }
    // Always update local cache as fallback
    await _storage.write(key: _kKey, value: jsonEncode(settings.toJson()));
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier(const FlutterSecureStorage());
});
