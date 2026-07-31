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

class WarehousePriceModel {
  final String warehouseId;
  final String warehouseName;
  final double? salePrice; // null = utilise le prix par défaut du produit

  WarehousePriceModel({
    required this.warehouseId,
    required this.warehouseName,
    this.salePrice,
  });

  factory WarehousePriceModel.fromJson(Map<String, dynamic> json) =>
      WarehousePriceModel(
        warehouseId: json['warehouse_id']?.toString() ?? '',
        warehouseName: json['warehouse_name']?.toString() ?? '',
        salePrice: json['sale_price'] != null
            ? (json['sale_price'] as num?)?.toDouble()
            : null,
      );
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
  final bool isLocked;
  final String? warehouseId;
  // Produit composé (ex: "Caisse" = 12 x "Boîte") — componentProductId
  // référence le produit dont le stock est réellement suivi ; ce produit-ci
  // n'a alors plus de stock propre (dérivé du composant côté serveur).
  final String? componentProductId;
  final double? componentQuantity;

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
    this.isLocked = false,
    this.warehouseId,
    this.componentProductId,
    this.componentQuantity,
  });

  bool get isLowStock => stock != null && stock! <= alertStock;
  bool get isComposite => componentProductId != null && componentQuantity != null;

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
        isLocked: json['is_locked'] == true,
        warehouseId: json['warehouse_id']?.toString(),
        componentProductId: json['component_product_id']?.toString(),
        componentQuantity: json['component_quantity'] != null
            ? (json['component_quantity'] as num?)?.toDouble()
            : null,
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
        'is_locked': isLocked,
        if (warehouseId != null) 'warehouse_id': warehouseId,
        'component_product_id': componentProductId,
        'component_quantity': componentQuantity,
      };
}
