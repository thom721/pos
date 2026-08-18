class LowStockProductModel {
  final String id;
  final String name;
  final double stock;
  final int alertStock;

  LowStockProductModel({
    required this.id,
    required this.name,
    required this.stock,
    required this.alertStock,
  });

  factory LowStockProductModel.fromJson(Map<String, dynamic> json) =>
      LowStockProductModel(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        stock: (json['stock'] as num?)?.toDouble() ?? 0,
        alertStock: (json['alert_stock'] as num?)?.toInt() ?? 0,
      );
}
