import 'package:pos_connect/core/date_utils.dart' show haitiNow;

class PosRegisterModel {
  final String id;
  final String name;
  final String deviceId;
  final bool isActive;
  final bool isDeviceApproved;
  final bool isInitial;
  final String? warehouseId;
  final DateTime? trialEndsAt;
  final DateTime? subscriptionStartedAt;
  final DateTime? subscriptionEndsAt;
  final String? dedicatedUserId;
  final String? dedicatedUserName;
  final String? appVersion;
  final int? appBuild;

  const PosRegisterModel({
    required this.id,
    required this.name,
    required this.deviceId,
    required this.isActive,
    this.isDeviceApproved = true,
    this.isInitial = false,
    this.warehouseId,
    this.trialEndsAt,
    this.subscriptionStartedAt,
    this.subscriptionEndsAt,
    this.dedicatedUserId,
    this.dedicatedUserName,
    this.appVersion,
    this.appBuild,
  });

  factory PosRegisterModel.fromJson(Map<String, dynamic> json) =>
      PosRegisterModel(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        deviceId: json['device_id']?.toString() ?? '',
        isActive: json['is_active'] as bool? ?? true,
        isDeviceApproved: json['is_device_approved'] as bool? ?? true,
        isInitial: json['is_initial'] as bool? ?? false,
        warehouseId: json['warehouse_id']?.toString(),
        trialEndsAt: json['trial_ends_at'] != null
            ? DateTime.tryParse(json['trial_ends_at'] as String)
            : null,
        subscriptionStartedAt: json['subscription_started_at'] != null
            ? DateTime.tryParse(json['subscription_started_at'] as String)
            : null,
        subscriptionEndsAt: json['subscription_ends_at'] != null
            ? DateTime.tryParse(json['subscription_ends_at'] as String)
            : null,
        dedicatedUserId: json['dedicated_user_id']?.toString(),
        dedicatedUserName: json['dedicated_user_name']?.toString(),
        appVersion: json['app_version']?.toString(),
        appBuild: (json['app_build'] as num?)?.toInt(),
      );

  /// Date d'expiration effective : subscription_ends_at en priorité, sinon trial_ends_at.
  DateTime? get effectiveExpiry => subscriptionEndsAt ?? trialEndsAt;

  /// Jours restants jusqu'à l'expiration (-∞ si pas de date).
  int? get daysLeft {
    final exp = effectiveExpiry;
    if (exp == null) return null;
    return exp.toUtc().difference(haitiNow().toUtc()).inDays;
  }

  bool get isTrial => subscriptionEndsAt == null && trialEndsAt != null;
}
