class WarehouseModel {
  final String id;
  final String name;
  final String? description;
  final bool isActive;
  final bool isDefault;

  const WarehouseModel({
    required this.id,
    required this.name,
    this.description,
    required this.isActive,
    required this.isDefault,
  });

  factory WarehouseModel.fromJson(Map<String, dynamic> json) => WarehouseModel(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        description: json['description']?.toString(),
        isActive: json['is_active'] as bool? ?? true,
        isDefault: json['is_default'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'is_active': isActive,
        'is_default': isDefault,
      };
}
