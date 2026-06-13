import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/providers/auth_provider.dart';

/// Returns true if the current user holds the given permission.
///
/// Usage:
///   final canCreate = ref.watch(hasPermissionProvider(Perm.salesCreate));
///   if (canCreate) { ... }
final hasPermissionProvider = Provider.family<bool, String>((ref, permission) {
  final user = ref.watch(authProvider).user;
  if (user == null) return false;
  return user.hasPermission(permission);
});

/// Returns true if the current user has the given role.
final hasRoleProvider = Provider.family<bool, String>((ref, role) {
  final user = ref.watch(authProvider).user;
  if (user == null) return false;
  return user.hasRole(role);
});

/// Returns true if the current user is an admin.
final isAdminProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).user?.isAdmin ?? false;
});
