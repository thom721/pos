class CategoryModel {
  final String id;
  final String name;
  final String? description;

  CategoryModel({required this.id, required this.name, this.description});

  factory CategoryModel.fromJson(Map<String, dynamic> json) => CategoryModel(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        description: json['description']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (description != null) 'description': description,
      };
}

class ProductModel {
  final String id;
  final String name;
  final String? barcode;
  final String? description;
  final double salePrice;
  final double purchasePrice;
  final int alertStock;
  final CategoryModel? category;
  final int? stock;
  final String? imageUrl;
  final bool isActive;
  final String? warehouseId;

  ProductModel({
    required this.id,
    required this.name,
    this.barcode,
    this.description,
    required this.salePrice,
    required this.purchasePrice,
    required this.alertStock,
    this.category,
    this.stock,
    this.imageUrl,
    this.isActive = true,
    this.warehouseId,
  });

  bool get isLowStock => stock != null && stock! <= alertStock;

  factory ProductModel.fromJson(Map<String, dynamic> json) => ProductModel(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        barcode: json['barcode']?.toString(),
        description: json['description']?.toString(),
        salePrice: double.tryParse(json['sale_price']?.toString() ?? '0') ?? 0,
        purchasePrice:
            double.tryParse(json['purchase_price']?.toString() ?? '0') ?? 0,
        alertStock: int.tryParse(json['alert_stock']?.toString() ?? '0') ?? 0,
        category: json['category'] != null
            ? CategoryModel.fromJson(json['category'])
            : null,
        stock: json['stock'] != null
            ? (json['stock'] as num?)?.toInt()
            : null,
        imageUrl: json['image_url']?.toString(),
        isActive: json['is_active'] != false,
        warehouseId: json['warehouse_id']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'barcode': barcode,
        'sale_price': salePrice,
        'purchase_price': purchasePrice,
        'alert_stock': alertStock,
        'category': category?.toJson(),
        'stock': stock,
        'image_url': imageUrl,
        if (warehouseId != null) 'warehouse_id': warehouseId,
      };
}
