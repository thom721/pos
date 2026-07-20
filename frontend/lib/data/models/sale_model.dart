List<SaleItemModel> _deduplicateById(Iterable<SaleItemModel> items) {
  final seen = <String>{};
  return items.where((i) => i.id.isNotEmpty && seen.add(i.id)).toList();
}

List<SalePaymentModel> _deduplicatePaymentsById(Iterable<SalePaymentModel> payments) {
  final seen = <String>{};
  return payments.where((p) => p.id.isNotEmpty && seen.add(p.id)).toList();
}

class SaleItemModel {
  final String id;
  final String? productId;
  final String? label;
  final double quantity;
  final double unitPrice;
  final double? originalPrice;
  final double subtotal;
  final String? productName;
  final double returnedQty;

  SaleItemModel({
    required this.id,
    this.productId,
    this.label,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
    this.originalPrice,
    this.productName,
    this.returnedQty = 0,
  });

  /// Nom à afficher : label (plat resto) > nom du produit > fallback
  String get displayName => label ?? productName ?? productId ?? '—';

  // Rabais par article si le prix a été réduit
  double get itemDiscount {
    if (originalPrice == null || originalPrice! <= unitPrice) return 0;
    return (originalPrice! - unitPrice) * quantity;
  }

  bool get hasDiscount => itemDiscount > 0;

  factory SaleItemModel.fromJson(Map<String, dynamic> json) => SaleItemModel(
        id: json['id']?.toString() ?? '',
        productId: json['product_id']?.toString(),
        label: json['label']?.toString(),
        quantity: double.tryParse(json['quantity']?.toString() ?? '0') ?? 0,
        unitPrice: double.tryParse(json['unit_price']?.toString() ?? '0') ?? 0,
        originalPrice: json['original_price'] != null
            ? double.tryParse(json['original_price'].toString())
            : null,
        subtotal: double.tryParse(json['subtotal']?.toString() ?? '0') ?? 0,
        productName: json['product']?['name']?.toString(),
        returnedQty: double.tryParse(json['returned_qty']?.toString() ?? '0') ?? 0,
      );
}

class SalePaymentModel {
  final String id;
  final double amount;
  final String method;
  final DateTime createdAt;

  SalePaymentModel({
    required this.id,
    required this.amount,
    required this.method,
    required this.createdAt,
  });

  factory SalePaymentModel.fromJson(Map<String, dynamic> json) =>
      SalePaymentModel(
        id: json['id']?.toString() ?? '',
        amount: double.tryParse(json['amount']?.toString() ?? '0') ?? 0,
        method: json['method']?.toString() ?? '',
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal() ??
            DateTime.now(),
      );
}

class SaleModel {
  final String id;
  final String reference;
  final double totalAmount;
  final double discount;
  final double finalAmount;
  final double paidAmount;
  final String status;
  final DateTime createdAt;
  final String? customerName;
  final String? customerPhone;
  final String? customerId;
  final String? userFullName;
  final String? warehouseId;
  final List<SaleItemModel> items;
  final List<SalePaymentModel> payments;

  SaleModel({
    required this.id,
    required this.reference,
    required this.totalAmount,
    required this.discount,
    required this.finalAmount,
    required this.paidAmount,
    required this.status,
    required this.createdAt,
    this.customerName,
    this.customerPhone,
    this.customerId,
    this.userFullName,
    this.warehouseId,
    required this.items,
    required this.payments,
  });

  double get balance => finalAmount - paidAmount;

  factory SaleModel.fromJson(Map<String, dynamic> json) => SaleModel(
        id: json['id']?.toString() ?? '',
        reference: json['reference']?.toString() ?? '',
        totalAmount:
            double.tryParse(json['total_amount']?.toString() ?? '0') ?? 0,
        discount: double.tryParse(json['discount']?.toString() ?? '0') ?? 0,
        finalAmount:
            double.tryParse(json['final_amount']?.toString() ?? '0') ?? 0,
        paidAmount:
            double.tryParse(json['paid_amount']?.toString() ?? '0') ?? 0,
        status: json['status']?.toString() ?? 'UNPAID',
        createdAt:
            DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal() ??
                DateTime.now(),
        customerName: json['customer']?['name']?.toString(),
        customerPhone: json['customer']?['phone']?.toString(),
        customerId: json['customer']?['id']?.toString(),
        userFullName: json['user'] != null
            ? '${json['user']['fname']} ${json['user']['lname']}'
            : null,
        warehouseId: json['warehouse_id']?.toString(),
        items: _deduplicateById(
            (json['items'] as List? ?? []).map((e) => SaleItemModel.fromJson(e as Map<String, dynamic>))),
        payments: _deduplicatePaymentsById(
            (json['payments'] as List? ?? []).map((e) => SalePaymentModel.fromJson(e as Map<String, dynamic>))),
      );
}
