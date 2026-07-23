import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/data/models/debt_model.dart';
import 'package:pos_connect/data/models/paginated_response.dart';
import 'package:pos_connect/data/repositories/debt_repository.dart';
import 'package:pos_connect/providers/sync_provider.dart';

final debtRepositoryProvider = Provider((ref) => DebtRepository());

class DebtListParams {
  final String? partnerType;
  final String? status;

  const DebtListParams({this.partnerType, this.status});

  @override
  bool operator ==(Object other) =>
      other is DebtListParams &&
      partnerType == other.partnerType &&
      status == other.status;

  @override
  int get hashCode => Object.hash(partnerType, status);
}

final debtListParamsProvider = StateProvider((ref) => const DebtListParams());

final debtsProvider =
    FutureProvider.autoDispose<PaginatedResponse<DebtModel>>((ref) async {
  ref.watch(syncEpochProvider); // rebuild après chaque sync SQLite
  final params = ref.watch(debtListParamsProvider);
  final repo = ref.read(debtRepositoryProvider);
  return repo.getDebts(
    partnerType: params.partnerType,
    status: params.status,
  );
});
