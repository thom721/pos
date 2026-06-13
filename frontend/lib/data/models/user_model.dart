import 'package:pos_connect/core/permissions.dart';

class UserModel {
  final String id;
  final String username;
  final String fname;
  final String lname;
  final List<String> roles;
  final List<String> permissions;
  final bool mustChangePassword;

  const UserModel({
    required this.id,
    required this.username,
    required this.fname,
    required this.lname,
    this.roles = const [],
    this.permissions = const [],
    this.mustChangePassword = false,
  });

  String get fullName => '$fname $lname'.trim();

  // ---------------------------------------------------------------------------
  // Permission checks
  // ---------------------------------------------------------------------------

  bool get isAdmin =>
      roles.contains('admin') || permissions.contains('all');

  bool hasPermission(String permission) {
    // Wildcard bypass
    if (permissions.contains('all')) return true;

    // Direct match
    if (permissions.contains(permission)) return true;

    // Role-derived permissions
    for (final role in roles) {
      final rolePerms = rolePermissions[role] ?? {};
      if (rolePerms.contains('all') || rolePerms.contains(permission)) {
        return true;
      }
    }
    return false;
  }

  bool hasRole(String role) => roles.contains(role);

  /// Convenience getters used in the UI
  bool get canManageUsers     => hasPermission(Perm.usersCreate);
  bool get canViewAllReports  => hasPermission(Perm.reportsReadAll);
  bool get canUpdateConfig    => hasPermission(Perm.configUpdate);
  bool get canManageStock     => hasPermission(Perm.stockAdjust);
  bool get canCreateSale      => hasPermission(Perm.salesCreate);
  bool get canCancelSale      => hasPermission(Perm.salesCancel);
  bool get canManagePurchases => hasPermission(Perm.purchasesCreate);

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id']?.toString() ?? '',
        username: json['username']?.toString() ?? '',
        fname: json['fname']?.toString() ?? '',
        lname: json['lname']?.toString() ?? '',
        roles: _toStringList(json['roles']),
        permissions: _toStringList(json['permissions']),
        mustChangePassword: json['must_change_password'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'fname': fname,
        'lname': lname,
        'roles': roles,
        'permissions': permissions,
        'must_change_password': mustChangePassword,
      };

  static List<String> _toStringList(dynamic value) {
    if (value is List) return value.map((e) => e.toString()).toList();
    return const [];
  }
}

class AuthToken {
  final String accessToken;
  final String tokenType;
  final Map<String, dynamic>? user;

  AuthToken({
    required this.accessToken,
    required this.tokenType,
    this.user,
  });

  factory AuthToken.fromJson(Map<String, dynamic> json) => AuthToken(
        accessToken: json['access_token']?.toString() ?? '',
        tokenType: json['token_type']?.toString() ?? 'bearer',
        user: json['user'] as Map<String, dynamic>?,
      );
}
