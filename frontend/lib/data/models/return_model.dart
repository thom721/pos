class ReturnItemModel {
  final String productName;
  final double quantity;
  final double unitPrice;
  final double subtotal;

  ReturnItemModel({
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
  });

  factory ReturnItemModel.fromJson(Map<String, dynamic> j) => ReturnItemModel(
        productName: j['product_name']?.toString() ?? '',
        quantity: (j['quantity'] as num?)?.toDouble() ?? 0,
        unitPrice: (j['unit_price'] as num?)?.toDouble() ?? 0,
        subtotal: (j['subtotal'] as num?)?.toDouble() ?? 0,
      );
}

class ReturnModel {
  final String id;
  final String returnType; // 'sale' | 'purchase'
  final String docReference;
  final double totalReturned;
  final double refundAmount;
  final String? reason;
  final DateTime createdAt;
  final List<ReturnItemModel> items;

  ReturnModel({
    required this.id,
    required this.returnType,
    required this.docReference,
    required this.totalReturned,
    required this.refundAmount,
    this.reason,
    required this.createdAt,
    required this.items,
  });

  factory ReturnModel.fromJson(Map<String, dynamic> j) => ReturnModel(
        id: j['id']?.toString() ?? '',
        returnType: j['return_type']?.toString() ?? 'sale',
        docReference: j['doc_reference']?.toString() ?? '',
        totalReturned: (j['total_returned'] as num?)?.toDouble() ?? 0,
        refundAmount: (j['refund_amount'] as num?)?.toDouble() ?? 0,
        reason: j['reason']?.toString(),
        createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '') ?? DateTime.now(),
        items: (j['items'] as List? ?? [])
            .map((e) => ReturnItemModel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
