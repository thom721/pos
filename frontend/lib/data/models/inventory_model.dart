class InventoryPreviewItem {
  final String productId;
  final String productName;
  final String? barcode;
  final String category;
  final String categoryId;
  final double expectedQty;

  InventoryPreviewItem({
    required this.productId,
    required this.productName,
    this.barcode,
    required this.category,
    required this.categoryId,
    required this.expectedQty,
  });

  factory InventoryPreviewItem.fromJson(Map<String, dynamic> json) =>
      InventoryPreviewItem(
        productId: json['product_id']?.toString() ?? '',
        productName: json['product_name']?.toString() ?? '',
        barcode: json['barcode']?.toString(),
        category: json['category']?.toString() ?? '',
        categoryId: json['category_id']?.toString() ?? '',
        expectedQty:
            double.tryParse(json['expected_qty']?.toString() ?? '0') ?? 0,
      );
}

class InventoryResultItem {
  final String productId;
  final String productName;
  final String? barcode;
  final double expectedQty;
  final double countedQty;
  final double diff;

  InventoryResultItem({
    required this.productId,
    required this.productName,
    this.barcode,
    required this.expectedQty,
    required this.countedQty,
    required this.diff,
  });

  factory InventoryResultItem.fromJson(Map<String, dynamic> json) =>
      InventoryResultItem(
        productId: json['product_id']?.toString() ?? '',
        productName: json['product_name']?.toString() ?? '',
        barcode: json['barcode']?.toString(),
        expectedQty:
            double.tryParse(json['expected_qty']?.toString() ?? '0') ?? 0,
        countedQty:
            double.tryParse(json['counted_qty']?.toString() ?? '0') ?? 0,
        diff: double.tryParse(json['diff']?.toString() ?? '0') ?? 0,
      );
}

class InventoryModel {
  final String id;
  final String reference;
  final String inventoryType;
  final String status;
  final String? notes;
  final int totalProducts;
  final int discrepancyCount;
  final DateTime createdAt;
  final List<InventoryResultItem> items;

  InventoryModel({
    required this.id,
    required this.reference,
    required this.inventoryType,
    required this.status,
    this.notes,
    required this.totalProducts,
    required this.discrepancyCount,
    required this.createdAt,
    required this.items,
  });

  factory InventoryModel.fromJson(Map<String, dynamic> json) => InventoryModel(
        id: json['id']?.toString() ?? '',
        reference: json['reference']?.toString() ?? '',
        inventoryType: json['inventory_type']?.toString() ?? 'full',
        status: json['status']?.toString() ?? 'confirmed',
        notes: json['notes']?.toString(),
        totalProducts:
            int.tryParse(json['total_products']?.toString() ?? '0') ?? 0,
        discrepancyCount:
            int.tryParse(json['discrepancy_count']?.toString() ?? '0') ?? 0,
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
            DateTime.now(),
        items: (json['items'] as List? ?? [])
            .map((e) => InventoryResultItem.fromJson(e))
            .toList(),
      );
}

class CategoryItem {
  final String id;
  final String name;
  CategoryItem({required this.id, required this.name});
  factory CategoryItem.fromJson(Map<String, dynamic> json) => CategoryItem(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
      );
}
