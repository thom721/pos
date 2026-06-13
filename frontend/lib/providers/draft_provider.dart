import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _kDraftsKey = 'pos_drafts_v1';

class DraftItem {
  final String productId;
  final String productName;
  final double salePrice;
  final double? customPrice;
  final double quantity;

  const DraftItem({
    required this.productId,
    required this.productName,
    required this.salePrice,
    this.customPrice,
    required this.quantity,
  });

  double get displayPrice => customPrice ?? salePrice;
  double get lineTotal => displayPrice * quantity;

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'productName': productName,
        'salePrice': salePrice,
        if (customPrice != null) 'customPrice': customPrice,
        'quantity': quantity,
      };

  factory DraftItem.fromJson(Map<String, dynamic> j) => DraftItem(
        productId: j['productId'] as String,
        productName: j['productName'] as String,
        salePrice: (j['salePrice'] as num).toDouble(),
        customPrice: j['customPrice'] != null
            ? (j['customPrice'] as num).toDouble()
            : null,
        quantity: (j['quantity'] as num).toDouble(),
      );
}

class DraftCart {
  final String id;
  final DateTime savedAt;
  final List<DraftItem> items;
  final double discount;
  final String? customerId;
  final String? customerName;
  final String paymentMethod;

  const DraftCart({
    required this.id,
    required this.savedAt,
    required this.items,
    required this.discount,
    this.customerId,
    this.customerName,
    required this.paymentMethod,
  });

  double get itemCount => items.fold(0.0, (s, i) => s + i.quantity);
  double get total => items.fold(0.0, (s, i) => s + i.lineTotal) - discount;

  String get label {
    final count = itemCount;
    final base = '$count article${count != 1 ? 's' : ''}';
    return customerName != null ? '$base — $customerName' : base;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'savedAt': savedAt.toIso8601String(),
        'items': items.map((i) => i.toJson()).toList(),
        'discount': discount,
        if (customerId != null) 'customerId': customerId,
        if (customerName != null) 'customerName': customerName,
        'paymentMethod': paymentMethod,
      };

  factory DraftCart.fromJson(Map<String, dynamic> j) => DraftCart(
        id: j['id'] as String,
        savedAt: DateTime.parse(j['savedAt'] as String),
        items: (j['items'] as List)
            .map((e) => DraftItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        discount: (j['discount'] as num).toDouble(),
        customerId: j['customerId'] as String?,
        customerName: j['customerName'] as String?,
        paymentMethod: j['paymentMethod'] as String? ?? 'CASH',
      );
}

class DraftsNotifier extends StateNotifier<List<DraftCart>> {
  DraftsNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kDraftsKey);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List;
      state = list
          .map((e) => DraftCart.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {}
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kDraftsKey, jsonEncode(state.map((d) => d.toJson()).toList()));
  }

  Future<void> saveDraft({
    required List<DraftItem> items,
    required double discount,
    required String paymentMethod,
    String? customerId,
    String? customerName,
  }) async {
    if (items.isEmpty) return;
    state = [
      ...state,
      DraftCart(
        id: const Uuid().v4(),
        savedAt: DateTime.now(),
        items: items,
        discount: discount,
        customerId: customerId,
        customerName: customerName,
        paymentMethod: paymentMethod,
      ),
    ];
    await _persist();
  }

  Future<void> removeDraft(String id) async {
    state = state.where((d) => d.id != id).toList();
    await _persist();
  }
}

final draftsProvider =
    StateNotifierProvider<DraftsNotifier, List<DraftCart>>(
  (_) => DraftsNotifier(),
);
