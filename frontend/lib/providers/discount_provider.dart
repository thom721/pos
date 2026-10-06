import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/data/models/discount_model.dart';
import 'package:pos_connect/data/repositories/discount_repository.dart';
import 'package:pos_connect/providers/warehouse_provider.dart';

final discountRepositoryProvider = Provider((ref) => DiscountRepository());

final discountsProvider = FutureProvider.autoDispose<List<DiscountModel>>((ref) async {
  final repo = ref.read(discountRepositoryProvider);
  return repo.getDiscounts();
});

/// Rabais utilisables en caisse : ceux du dépôt actif + ceux de tous les dépôts.
final posDiscountsProvider = FutureProvider.autoDispose<List<DiscountModel>>((ref) async {
  final all = await ref.watch(discountsProvider.future);
  final wh = ref.watch(activeWarehouseProvider)?.id;
  return all
      .where((d) => d.warehouseId == null || wh == null || d.warehouseId == wh)
      .toList();
});
