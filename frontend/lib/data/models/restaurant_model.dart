class MenuItemModel {
  final String id;
  final String name;
  final String? description;
  final double price;
  final String? categoryId;
  final String? categoryName;
  final String? productId;
  final bool available;
  final String? imageUrl;

  const MenuItemModel({
    required this.id,
    required this.name,
    this.description,
    required this.price,
    this.categoryId,
    this.categoryName,
    this.productId,
    required this.available,
    this.imageUrl,
  });

  factory MenuItemModel.fromJson(Map<String, dynamic> j) => MenuItemModel(
        id:           j['id'] as String,
        name:         j['name'] as String,
        description:  j['description'] as String?,
        price:        (j['price'] as num?)?.toDouble() ?? 0.0,
        categoryId:   j['category_id'] as String?,
        categoryName: j['category_name'] as String?,
        productId:    j['product_id'] as String?,
        available:    j['available'] as bool? ?? true,
        imageUrl:     j['image_url'] as String?,
      );
}

// Kept for backward compat, not actively used in UI
class IngredientModel {
  final String id;
  final String name;
  final String? productId;
  final String? categoryId;
  const IngredientModel(
      {required this.id,
      required this.name,
      this.productId,
      this.categoryId});
  factory IngredientModel.fromJson(Map<String, dynamic> j) => IngredientModel(
      id: j['id'] as String,
      name: j['name'] as String,
      productId: j['product_id'] as String?,
      categoryId: j['category_id'] as String?);
}

class ModifierOptionModel {
  final String id;
  final String name;
  final double extraPrice;
  const ModifierOptionModel(
      {required this.id, required this.name, required this.extraPrice});
  factory ModifierOptionModel.fromJson(Map<String, dynamic> j) =>
      ModifierOptionModel(
        id:         j['id'] as String,
        name:       j['name'] as String,
        extraPrice: (j['extra_price'] as num?)?.toDouble() ?? 0.0,
      );
}

class ModifierGroupModel {
  final String id;
  final String name;
  final String? productId;
  final String? menuItemId;
  final String? categoryId;
  final bool required;
  final bool multiSelect;
  final List<ModifierOptionModel> options;

  const ModifierGroupModel({
    required this.id,
    required this.name,
    this.productId,
    this.menuItemId,
    this.categoryId,
    required this.required,
    required this.multiSelect,
    required this.options,
  });

  factory ModifierGroupModel.fromJson(Map<String, dynamic> j) =>
      ModifierGroupModel(
        id:          j['id'] as String,
        name:        j['name'] as String,
        productId:   j['product_id'] as String?,
        menuItemId:  j['menu_item_id'] as String?,
        categoryId:  j['category_id'] as String?,
        required:    j['required'] as bool? ?? false,
        multiSelect: j['multi_select'] as bool? ?? true,
        options: (j['options'] as List<dynamic>? ?? [])
            .map((e) =>
                ModifierOptionModel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class RestaurantWaiterModel {
  final String id;
  final String name;
  final String username;

  const RestaurantWaiterModel({
    required this.id,
    required this.name,
    required this.username,
  });

  factory RestaurantWaiterModel.fromJson(Map<String, dynamic> j) =>
      RestaurantWaiterModel(
        id:       j['id'] as String,
        name:     j['name'] as String? ?? '',
        username: j['username'] as String? ?? '',
      );
}

class RestaurantTableModel {
  final String id;
  final String name;
  final int capacity;
  final String status; // free | occupied | reserved
  final String? waiterId;
  final String? waiterName;

  const RestaurantTableModel({
    required this.id,
    required this.name,
    required this.capacity,
    required this.status,
    this.waiterId,
    this.waiterName,
  });

  bool get isFree     => status == 'free';
  bool get isOccupied => status == 'occupied';
  bool get isReserved => status == 'reserved';

  factory RestaurantTableModel.fromJson(Map<String, dynamic> j) =>
      RestaurantTableModel(
        id:         j['id'] as String,
        name:       j['name'] as String,
        capacity:   j['capacity'] as int? ?? 4,
        status:     j['status'] as String? ?? 'free',
        waiterId:   j['waiter_id'] as String?,
        waiterName: j['waiter_name'] as String?,
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
  final String? tableId;
  final String? tableName;
  final String? waiterName;
  final String status; // open | sent_to_kitchen | ready | closed
  final List<RestaurantOrderItemModel> items;
  final double subtotal;
  final double tip;
  final double total;
  final int covers;
  final String? notes;
  final DateTime? createdAt;

  const RestaurantOrderModel({
    required this.id,
    this.tableId,
    this.tableName,
    this.waiterName,
    required this.status,
    required this.items,
    required this.subtotal,
    required this.tip,
    required this.total,
    required this.covers,
    this.notes,
    this.createdAt,
  });

  bool get sentToKitchen => status == 'sent_to_kitchen';
  bool get isReady       => status == 'ready';
  bool get hasTable      => tableId != null && tableId!.isNotEmpty;

  factory RestaurantOrderModel.fromJson(Map<String, dynamic> j) =>
      RestaurantOrderModel(
        id:          j['id'] as String,
        tableId:     j['table_id'] as String?,
        tableName:   j['table_name'] as String?,
        waiterName:  j['waiter_name'] as String?,
        status:      j['status'] as String? ?? 'open',
        subtotal:    (j['subtotal'] as num?)?.toDouble() ?? 0.0,
        tip:         (j['tip'] as num?)?.toDouble() ?? 0.0,
        total:       (j['total'] as num?)?.toDouble() ?? 0.0,
        covers:      j['covers'] as int? ?? 1,
        notes:       j['notes'] as String?,
        createdAt:   j['created_at'] != null
            ? DateTime.tryParse(j['created_at'].toString())
            : null,
        items: (j['items'] as List<dynamic>? ?? [])
            .map((e) => RestaurantOrderItemModel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
