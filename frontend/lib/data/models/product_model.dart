class CategoryModel {
  final String id;
  final String name;

  CategoryModel({required this.id, required this.name});

  factory CategoryModel.fromJson(Map<String, dynamic> json) => CategoryModel(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

class ProductModel {
  final String id;
  final String name;
  final String? barcode;
  final double salePrice;
  final double purchasePrice;
  final int alertStock;
  final CategoryModel? category;
  final int? stock;
  final String? imageUrl;

  ProductModel({
    required this.id,
    required this.name,
    this.barcode,
    required this.salePrice,
    required this.purchasePrice,
    required this.alertStock,
    this.category,
    this.stock,
    this.imageUrl,
  });

  bool get isLowStock => stock != null && stock! <= alertStock;

  factory ProductModel.fromJson(Map<String, dynamic> json) => ProductModel(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        barcode: json['barcode']?.toString(),
        salePrice: double.tryParse(json['sale_price']?.toString() ?? '0') ?? 0,
        purchasePrice:
            double.tryParse(json['purchase_price']?.toString() ?? '0') ?? 0,
        alertStock: int.tryParse(json['alert_stock']?.toString() ?? '0') ?? 0,
        category: json['category'] != null
            ? CategoryModel.fromJson(json['category'])
            : null,
        stock: json['stock'] != null
            ? int.tryParse(json['stock'].toString())
            : null,
        imageUrl: json['image_url']?.toString(),
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
      };
}
