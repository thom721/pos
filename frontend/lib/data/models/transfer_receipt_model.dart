import 'package:pos_connect/core/date_utils.dart' show parseApiDate;

/// Reçu d'un transfert de stock vers un entrepôt (depuis un dépôt classique
/// ou un autre entrepôt) — exploitable pour l'impression d'audit.
class TransferReceiptModel {
  final String movementId;
  final String productName;
  final double quantity;
  final String sourceName;
  final String? sourceAddress;
  final String targetName;
  final String? targetAddress;
  final String? reason;
  final DateTime createdAt;

  TransferReceiptModel({
    required this.movementId,
    required this.productName,
    required this.quantity,
    required this.sourceName,
    this.sourceAddress,
    required this.targetName,
    this.targetAddress,
    this.reason,
    required this.createdAt,
  });

  factory TransferReceiptModel.fromJson(Map<String, dynamic> json) =>
      TransferReceiptModel(
        movementId: json['movement_id']?.toString() ?? '',
        productName: json['product_name']?.toString() ?? '',
        quantity: double.tryParse(json['quantity']?.toString() ?? '0') ?? 0,
        sourceName: json['source_name']?.toString() ?? '',
        sourceAddress: json['source_address']?.toString(),
        targetName: json['target_name']?.toString() ?? '',
        targetAddress: json['target_address']?.toString(),
        reason: json['reason']?.toString(),
        createdAt: parseApiDate(json['created_at']?.toString()),
      );
}
