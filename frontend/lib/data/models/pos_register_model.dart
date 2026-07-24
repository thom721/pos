class PosRegisterModel {
  final String id;
  final String name;
  final String deviceId;
  final bool isActive;
  final bool isInitial;
  final String? warehouseId;
  final DateTime? trialEndsAt;
  final DateTime? subscriptionEndsAt;

  const PosRegisterModel({
    required this.id,
    required this.name,
    required this.deviceId,
    required this.isActive,
    this.isInitial = false,
    this.warehouseId,
    this.trialEndsAt,
    this.subscriptionEndsAt,
  });

  factory PosRegisterModel.fromJson(Map<String, dynamic> json) =>
      PosRegisterModel(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        deviceId: json['device_id']?.toString() ?? '',
        isActive: json['is_active'] as bool? ?? true,
        isInitial: json['is_initial'] as bool? ?? false,
        warehouseId: json['warehouse_id']?.toString(),
        trialEndsAt: json['trial_ends_at'] != null
            ? DateTime.tryParse(json['trial_ends_at'] as String)
            : null,
        subscriptionEndsAt: json['subscription_ends_at'] != null
            ? DateTime.tryParse(json['subscription_ends_at'] as String)
            : null,
      );

  /// Date d'expiration effective : subscription_ends_at en priorité, sinon trial_ends_at.
  DateTime? get effectiveExpiry => subscriptionEndsAt ?? trialEndsAt;

  /// Jours restants jusqu'à l'expiration (-∞ si pas de date).
  int? get daysLeft {
    final exp = effectiveExpiry;
    if (exp == null) return null;
    return exp.difference(DateTime.now()).inDays;
  }

  bool get isTrial => subscriptionEndsAt == null && trialEndsAt != null;
}
