import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/data/models/return_model.dart';
import 'package:pos_connect/data/repositories/return_repository.dart';

final _repo = ReturnRepository();

// ── State ──────────────────────────────────────────────────────────────────

class ReturnsState {
  final List<ReturnModel> saleReturns;
  final List<ReturnModel> purchaseReturns;
  final bool loading;
  final String? error;

  const ReturnsState({
    this.saleReturns = const [],
    this.purchaseReturns = const [],
    this.loading = false,
    this.error,
  });

  ReturnsState copyWith({
    List<ReturnModel>? saleReturns,
    List<ReturnModel>? purchaseReturns,
    bool? loading,
    String? error,
  }) =>
      ReturnsState(
        saleReturns: saleReturns ?? this.saleReturns,
        purchaseReturns: purchaseReturns ?? this.purchaseReturns,
        loading: loading ?? this.loading,
        error: error,
      );
}

// ── Notifier ───────────────────────────────────────────────────────────────

class ReturnsNotifier extends StateNotifier<ReturnsState> {
  ReturnsNotifier() : super(const ReturnsState()) {
    fetch();
  }

  Future<void> fetch() async {
    state = state.copyWith(loading: true);
    try {
      final all = await _repo.getReturns(limit: 100);
      state = state.copyWith(
        loading: false,
        saleReturns: all.where((r) => r.returnType == 'sale').toList(),
        purchaseReturns: all.where((r) => r.returnType == 'purchase').toList(),
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<bool> createSaleReturn({
    required String saleId,
    required List<Map<String, dynamic>> items,
    required double refundAmount,
    String? reason,
  }) async {
    try {
      await _repo.createSaleReturn(
        saleId: saleId,
        items: items,
        refundAmount: refundAmount,
        reason: reason,
      );
      await fetch();
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<bool> createPurchaseReturn({
    required String purchaseId,
    required List<Map<String, dynamic>> items,
    String? reason,
  }) async {
    try {
      await _repo.createPurchaseReturn(
        purchaseId: purchaseId,
        items: items,
        reason: reason,
      );
      await fetch();
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }
}

final returnsProvider =
    StateNotifierProvider<ReturnsNotifier, ReturnsState>(
        (_) => ReturnsNotifier());
