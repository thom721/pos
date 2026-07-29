class DepotModel {
  final String id;
  final String clientId;
  final double amount;
  final String? warehouseId;
  final String? note;

  DepotModel({
    required this.id,
    required this.clientId,
    required this.amount,
    this.warehouseId,
    this.note,
  });

  factory DepotModel.fromJson(Map<String, dynamic> json) => DepotModel(
        id: json['id']?.toString() ?? '',
        clientId: json['client_id']?.toString() ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        warehouseId: json['warehouse_id']?.toString(),
        note: json['note']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'client_id': clientId,
        'amount': amount,
        if (warehouseId != null) 'warehouse_id': warehouseId,
        if (note != null) 'note': note,
      };
}
