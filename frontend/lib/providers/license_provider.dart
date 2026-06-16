import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/providers/auth_provider.dart';
import 'package:pos_connect/services/license_service.dart';

/// Refreshes whenever auth state changes (login / logout).
final licenseProvider = FutureProvider<LicenseStatus>((ref) async {
  ref.watch(authProvider); // rebuild on login/logout
  return LicenseService.check();
});
