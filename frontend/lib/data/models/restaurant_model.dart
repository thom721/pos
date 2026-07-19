class RestaurantTableModel {
  final String id;
  final String name;
  final int capacity;
  final String status; // free | occupied | reserved

  const RestaurantTableModel({
    required this.id,
    required this.name,
    required this.capacity,
    required this.status,
  });

  bool get isFree     => status == 'free';
  bool get isOccupied => status == 'occupied';
  bool get isReserved => status == 'reserved';

  factory RestaurantTableModel.fromJson(Map<String, dynamic> j) =>
      RestaurantTableModel(
        id:       j['id'] as String,
        name:     j['name'] as String,
        capacity: j['capacity'] as int? ?? 4,
        status:   j['status'] as String? ?? 'free',
      );
}

class RestaurantOrderItemModel {
  final String id;
  final String productId;
  final String productName;
  final double quantity;
  final double unitPrice;
  final String? notes;
  final String status; // pending | preparing | ready

  const RestaurantOrderItemModel({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    this.notes,
    required this.status,
  });

  double get subtotal => quantity * unitPrice;

  factory RestaurantOrderItemModel.fromJson(Map<String, dynamic> j) =>
      RestaurantOrderItemModel(
        id:          j['id'] as String,
        productId:   j['product_id'] as String,
        productName: j['product_name'] as String? ?? '',
        quantity:    (j['quantity'] as num).toDouble(),
        unitPrice:   (j['unit_price'] as num).toDouble(),
        notes:       j['notes'] as String?,
        status:      j['status'] as String? ?? 'pending',
      );
}

class RestaurantOrderModel {
  final String id;
  final String tableId;
  final String? tableName;
  final String status; // open | sent_to_kitchen | ready | closed
  final List<RestaurantOrderItemModel> items;
  final double total;
  final String? notes;

  const RestaurantOrderModel({
    required this.id,
    required this.tableId,
    this.tableName,
    required this.status,
    required this.items,
    required this.total,
    this.notes,
  });

  bool get sentToKitchen => status == 'sent_to_kitchen';
  bool get isReady       => status == 'ready';

  factory RestaurantOrderModel.fromJson(Map<String, dynamic> j) =>
      RestaurantOrderModel(
        id:        j['id'] as String,
        tableId:   j['table_id'] as String,
        tableName: j['table_name'] as String?,
        status:    j['status'] as String? ?? 'open',
        total:     (j['total'] as num?)?.toDouble() ?? 0.0,
        notes:     j['notes'] as String?,
        items: (j['items'] as List<dynamic>? ?? [])
            .map((e) => RestaurantOrderItemModel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
