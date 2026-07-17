class PosRegisterModel {
  final String id;
  final String name;
  final String deviceId;
  final bool isActive;
  final String? warehouseId;

  const PosRegisterModel({
    required this.id,
    required this.name,
    required this.deviceId,
    required this.isActive,
    this.warehouseId,
  });

  factory PosRegisterModel.fromJson(Map<String, dynamic> json) =>
      PosRegisterModel(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        deviceId: json['device_id']?.toString() ?? '',
        isActive: json['is_active'] as bool? ?? true,
        warehouseId: json['warehouse_id']?.toString(),
      );
}
