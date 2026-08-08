class WarehouseModel {
  final String id;
  final String name;
  final String? description;
  final String? address;
  final bool isActive;
  final bool isDefault;
  /// True sur le serveur local qui a revendiqué ce dépôt lors de l'installation.
  final bool isClaimed;
  /// Entrepôt central (stock de transit) — n'est pas un dépôt de vente,
  /// masqué du sélecteur "Tous les business" (voir app_shell.dart).
  final bool isEntrepot;
  /// Abonnement de l'entrepôt — NULL = jamais payé (pas d'essai gratuit).
  /// Toujours null pour un dépôt classique (non renvoyé par l'API dépôts).
  final DateTime? subscriptionEndsAt;

  const WarehouseModel({
    required this.id,
    required this.name,
    this.description,
    this.address,
    required this.isActive,
    required this.isDefault,
    this.isClaimed = false,
    this.isEntrepot = false,
    this.subscriptionEndsAt,
  });

  bool get isSubscriptionActive =>
      subscriptionEndsAt != null && subscriptionEndsAt!.isAfter(DateTime.now());

  factory WarehouseModel.fromJson(Map<String, dynamic> json) => WarehouseModel(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        description: json['description']?.toString(),
        address: json['address']?.toString(),
        isActive: json['is_active'] as bool? ?? true,
        isDefault: json['is_default'] as bool? ?? false,
        isClaimed: json['is_claimed'] as bool? ?? false,
        isEntrepot: json['is_entrepot'] as bool? ?? false,
        subscriptionEndsAt: json['subscription_ends_at'] != null
            ? DateTime.tryParse(json['subscription_ends_at'].toString())
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'address': address,
        'is_active': isActive,
        'is_default': isDefault,
        'is_claimed': isClaimed,
        'is_entrepot': isEntrepot,
        'subscription_ends_at': subscriptionEndsAt?.toIso8601String(),
      };

  @override
  bool operator ==(Object other) => other is WarehouseModel && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
