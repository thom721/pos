class WarehouseModel {
  final String id;
  final String name;
  final String? description;
  final bool isActive;
  final bool isDefault;
  /// True sur le serveur local qui a revendiqué ce dépôt lors de l'installation.
  final bool isClaimed;

  const WarehouseModel({
    required this.id,
    required this.name,
    this.description,
    required this.isActive,
    required this.isDefault,
    this.isClaimed = false,
  });

  factory WarehouseModel.fromJson(Map<String, dynamic> json) => WarehouseModel(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        description: json['description']?.toString(),
        isActive: json['is_active'] as bool? ?? true,
        isDefault: json['is_default'] as bool? ?? false,
        isClaimed: json['is_claimed'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'is_active': isActive,
        'is_default': isDefault,
        'is_claimed': isClaimed,
      };

  @override
  bool operator ==(Object other) => other is WarehouseModel && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
