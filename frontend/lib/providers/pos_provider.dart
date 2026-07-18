import 'package:dio/dio.dart' show DioException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/data/models/product_model.dart';
import 'package:pos_connect/data/models/sale_model.dart';
import 'package:pos_connect/data/repositories/sale_repository.dart';
import 'package:pos_connect/providers/draft_provider.dart';

class CartItem {
  final ProductModel product;
  double quantity;
  double? _customPrice;

  CartItem({required this.product, this.quantity = 1});

  double get unitPrice => _customPrice ?? product.salePrice;
  set unitPrice(double v) => _customPrice = v;

  bool get isPriceModified =>
      _customPrice != null && _customPrice != product.salePrice;
  double get subtotal => unitPrice * quantity;

  // Catalog price total (before any per-item price reduction)
  double get catalogSubtotal => product.salePrice * quantity;

  // Discount from price modification: (catalogPrice - unitPrice) * qty
  double get itemDiscount {
    final diff = product.salePrice - unitPrice;
    return diff > 0 ? diff * quantity : 0;
  }
}

class PosState {
  final List<CartItem> items;
  final String? customerId;
  final double discount;
  final double paidAmount;
  final String paymentMethod;
  final bool isProcessing;
  final String? successMessage;
  final String? error;
  // Non-null when editing an existing sale
  final SaleModel? editingSale;

  const PosState({
    this.items = const [],
    this.customerId,
    this.discount = 0,
    this.paidAmount = 0,
    this.paymentMethod = 'CASH',
    this.isProcessing = false,
    this.successMessage,
    this.error,
    this.editingSale,
  });

  bool get isEditMode => editingSale != null;

  // Catalog subtotal: catalog price × qty for all items
  double get catalogSubtotal => items.fold(0, (s, i) => s + i.catalogSubtotal);

  // Auto-calculated discounts from per-item price reductions
  double get itemsDiscount => items.fold(0, (s, i) => s + i.itemDiscount);

  // Displayed subtotal = catalog prices (before any discount)
  double get subtotal => catalogSubtotal;

  // Final total = catalog - per-item discounts - global cash discount
  double get total => catalogSubtotal - itemsDiscount - discount;

  double get balance => total - paidAmount;

  PosState copyWith({
    List<CartItem>? items,
    String? customerId,
    double? discount,
    double? paidAmount,
    String? paymentMethod,
    bool? isProcessing,
    String? successMessage,
    String? error,
    SaleModel? editingSale,
  }) =>
      PosState(
        items: items ?? this.items,
        customerId: customerId ?? this.customerId,
        discount: discount ?? this.discount,
        paidAmount: paidAmount ?? this.paidAmount,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        isProcessing: isProcessing ?? this.isProcessing,
        successMessage: successMessage,
        error: error,
        editingSale: editingSale ?? this.editingSale,
      );
}

class PosNotifier extends StateNotifier<PosState> {
  final SaleRepository _repo;

  PosNotifier(this._repo) : super(const PosState());

  void addProduct(ProductModel product) {
    final existing = state.items.indexWhere((i) => i.product.id == product.id);
    if (existing >= 0) {
      final updated = List<CartItem>.from(state.items);
      updated[existing].quantity += 1;
      state = state.copyWith(items: updated);
    } else {
      state = state.copyWith(
        items: [...state.items, CartItem(product: product)],
      );
    }
  }

  void removeItem(String productId) {
    state = state.copyWith(
      items: state.items.where((i) => i.product.id != productId).toList(),
    );
  }

  void updateQuantity(String productId, double qty) {
    if (qty <= 0) {
      removeItem(productId);
      return;
    }
    final updated = state.items.map((i) {
      if (i.product.id == productId) i.quantity = qty;
      return i;
    }).toList();
    state = state.copyWith(items: updated);
  }

  void updateItemPrice(String productId, double newPrice) {
    final updated = state.items.map((i) {
      if (i.product.id == productId) i.unitPrice = newPrice;
      return i;
    }).toList();
    state = state.copyWith(items: updated);
  }

  void setDiscount(double d) => state = state.copyWith(discount: d);
  void setPaidAmount(double a) => state = state.copyWith(paidAmount: a);
  void setPaymentMethod(String m) => state = state.copyWith(paymentMethod: m);
  void setCustomer(String? id) => state = state.copyWith(customerId: id);

  void payFull() => state = state.copyWith(paidAmount: state.total);

  void clearCart() => state = const PosState();

  /// Retourne le sale_id si succès (online ou offline), null si erreur.
  /// [offlineMode] sera true si la vente a été enregistrée localement
  /// mais pas encore envoyée au cloud.
  Future<({String? saleId, bool offline})> checkout({
    String? approvalCode,
    String? warehouseId,
    String? customerName,
  }) async {
    if (state.items.isEmpty || state.isProcessing) return (saleId: null, offline: false);
    state = state.copyWith(isProcessing: true, error: null);
    try {
      final data = await _repo.createSale(
        {
          'customer_id': state.customerId,
          'discount': state.discount,
          'paid_amount': state.paidAmount,
          'payment_method': state.paymentMethod,
          if (approvalCode != null && approvalCode.isNotEmpty)
            'approval_code': approvalCode,
          if (warehouseId != null) 'warehouse_id': warehouseId,
          'items': state.items
              .map((i) => {
                    'product_id': i.product.id,
                    'product_name': i.product.name,
                    'quantity': i.quantity,
                    'unit_price': i.unitPrice,
                    'original_price': i.product.salePrice,
                    'subtotal': i.subtotal,
                  })
              .toList(),
        },
        customerName: customerName,
      );
      state = state.copyWith(isProcessing: false, error: null);
      return (
        saleId: data['sale_id']?.toString(),
        offline: data['offline'] == true,
      );
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response!.data['message'] ?? e.response!.data['detail'])?.toString()
          : null;
      state = state.copyWith(
        isProcessing: false,
        error: msg ?? 'Erreur lors de la vente. Réessayez.',
      );
      return (saleId: null, offline: false);
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        error: 'Erreur lors de la vente. Réessayez.',
      );
      return (saleId: null, offline: false);
    }
  }

  void loadDraft(DraftCart draft) {
    final items = draft.items.map((d) {
      final product = ProductModel(
        id: d.productId,
        name: d.productName,
        salePrice: d.salePrice,
        purchasePrice: 0,
        alertStock: 0,
      );
      final item = CartItem(product: product, quantity: d.quantity);
      if (d.customPrice != null) item.unitPrice = d.customPrice!;
      return item;
    }).toList();
    state = PosState(
      items: items,
      discount: draft.discount,
      customerId: draft.customerId,
      paymentMethod: draft.paymentMethod,
    );
  }

  void loadFromSale(SaleModel sale) {
    final items = sale.items.map((si) {
      final catalogPrice = si.originalPrice ?? si.unitPrice;
      final product = ProductModel(
        id: si.productId,
        name: si.productName ?? 'Produit',
        salePrice: catalogPrice,
        purchasePrice: 0,
        alertStock: 0,
      );
      final item = CartItem(product: product, quantity: si.quantity);
      if (si.unitPrice != catalogPrice) item.unitPrice = si.unitPrice;
      return item;
    }).toList();
    final method = sale.payments.isNotEmpty
        ? (sale.payments.first.method.isEmpty ? 'CASH' : sale.payments.first.method)
        : 'CASH';
    state = PosState(
      items: items,
      discount: sale.discount,
      customerId: sale.customerId,
      paymentMethod: method,
      paidAmount: 0, // additional payment for this modification
      editingSale: sale,
    );
  }

  Future<String?> modifySale() async {
    final s = state;
    if (s.editingSale == null || s.items.isEmpty || s.isProcessing) return null;
    state = s.copyWith(isProcessing: true, error: null);
    try {
      final data = await _repo.updateSale(s.editingSale!.id, {
        'customer_id': s.customerId,
        'discount': s.discount,
        'payment_method': s.paymentMethod,
        'additional_payment': s.paidAmount,
        'items': s.items
            .map((i) => {
                  'product_id': i.product.id,
                  'quantity': i.quantity,
                  'unit_price': i.unitPrice,
                  'subtotal': i.subtotal,
                })
            .toList(),
      });
      state = const PosState(); // clear cart + edit mode
      return data['sale_id']?.toString();
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response!.data['message'] ?? e.response!.data['detail'])?.toString()
          : null;
      state = state.copyWith(
        isProcessing: false,
        error: msg ?? 'Erreur lors de la modification. Réessayez.',
      );
      return null;
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        error: 'Erreur lors de la modification. Réessayez.',
      );
      return null;
    }
  }
}

final posProvider = StateNotifierProvider<PosNotifier, PosState>((ref) {
  return PosNotifier(SaleRepository());
});
