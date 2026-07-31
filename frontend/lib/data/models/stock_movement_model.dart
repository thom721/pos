import 'package:pos_connect/core/date_utils.dart' show parseApiDate;

class StockMovementModel {
  final String id;
  final String type; // IN | OUT
  final double quantity;
  final String? sourceType;
  final String? note;
  final DateTime createdAt;
  final String? productName;
  final String? userFullName;

  StockMovementModel({
    required this.id,
    required this.type,
    required this.quantity,
    this.sourceType,
    this.note,
    required this.createdAt,
    this.productName,
    this.userFullName,
  });

  factory StockMovementModel.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    final product = json['product'] as Map<String, dynamic>?;
    return StockMovementModel(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      quantity: double.tryParse(json['quantity']?.toString() ?? '0') ?? 0,
      sourceType: json['source_type']?.toString(),
      note: json['note']?.toString(),
      createdAt: parseApiDate(json['created_at']?.toString()),
      productName: product?['name']?.toString(),
      userFullName: user != null
          ? '${user['fname'] ?? ''} ${user['lname'] ?? ''}'.trim()
          : null,
    );
  }

  String get sourceLabel {
    switch (sourceType) {
      case 'entrepot_receipt':
        return 'Réception';
      case 'entrepot_adjustment':
        return 'Ajustement manuel';
      case 'entrepot_distribution':
        return 'Distribution';
      case 'purchase_receipt':
        return 'Réception d\'achat';
      default:
        return sourceType ?? '';
    }
  }
}
