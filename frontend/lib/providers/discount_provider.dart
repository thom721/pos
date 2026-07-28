import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/data/models/discount_model.dart';
import 'package:pos_connect/data/repositories/discount_repository.dart';

final discountRepositoryProvider = Provider((ref) => DiscountRepository());

final discountsProvider = FutureProvider.autoDispose<List<DiscountModel>>((ref) async {
  final repo = ref.read(discountRepositoryProvider);
  return repo.getDiscounts();
});
