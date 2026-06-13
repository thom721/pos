class PurchaseItemModel {
  final String id;
  final String productId;
  final double orderedQty;
  final double unitPrice;
  final double subtotal;
  final String? productName;

  PurchaseItemModel({
    required this.id,
    required this.productId,
    required this.orderedQty,
    required this.unitPrice,
    required this.subtotal,
    this.productName,
  });

  factory PurchaseItemModel.fromJson(Map<String, dynamic> json) =>
      PurchaseItemModel(
        id: json['id']?.toString() ?? '',
        productId: json['product_id']?.toString() ?? '',
        orderedQty:
            double.tryParse(json['ordered_qty']?.toString() ?? '0') ?? 0,
        unitPrice: double.tryParse(json['unit_price']?.toString() ?? '0') ?? 0,
        subtotal: double.tryParse(json['subtotal']?.toString() ?? '0') ?? 0,
        productName: json['product']?['name']?.toString(),
      );
}

class PurchaseModel {
  final String id;
  final String reference;
  final double totalAmount;
  final double paidAmount;
  final String status;
  final DateTime createdAt;
  final String? supplierName;
  final String? supplierId;
  final String? userFullName;
  final List<PurchaseItemModel> items;

  PurchaseModel({
    required this.id,
    required this.reference,
    required this.totalAmount,
    required this.paidAmount,
    required this.status,
    required this.createdAt,
    this.supplierName,
    this.supplierId,
    this.userFullName,
    required this.items,
  });

  double get balance => totalAmount - paidAmount;

  factory PurchaseModel.fromJson(Map<String, dynamic> json) => PurchaseModel(
        id: json['id']?.toString() ?? '',
        reference: json['reference']?.toString() ?? '',
        totalAmount:
            double.tryParse(json['total_amount']?.toString() ?? '0') ?? 0,
        paidAmount:
            double.tryParse(json['paid_amount']?.toString() ?? '0') ?? 0,
        status: json['status']?.toString() ?? 'pending',
        createdAt:
            DateTime.tryParse(json['created_at']?.toString() ?? '') ??
                DateTime.now(),
        supplierName: json['supplier']?['name']?.toString(),
        supplierId: json['supplier']?['id']?.toString(),
        userFullName: json['user'] != null
            ? '${json['user']['fname']} ${json['user']['lname']}'
            : null,
        items: (json['items'] as List? ?? [])
            .map((e) => PurchaseItemModel.fromJson(e))
            .toList(),
      );
}
