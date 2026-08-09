import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/providers/auth_provider.dart';
import 'package:pos_connect/services/license_service.dart';

/// Refreshes whenever auth state changes (login / logout).
final licenseProvider = FutureProvider<LicenseStatus>((ref) async {
  ref.watch(authProvider); // rebuild on login/logout
  return LicenseService.check();
});

/// Bumped every 5 min par settings_provider.dart::_refreshAll() — les écrans
/// de facturation (montants, dates d'expiration) le watchent pour rester à
/// jour sans bouton "Actualiser" manuel (voir billing_screen.dart).
final billingEpochProvider = StateProvider<int>((ref) => 0);
