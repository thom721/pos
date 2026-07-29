import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/data/models/client_sabotage_model.dart';
import 'package:pos_connect/data/repositories/client_sabotage_repository.dart';

final clientSabotageRepositoryProvider = Provider((ref) => ClientSabotageRepository());

final clientsSabotageProvider = FutureProvider.autoDispose<List<ClientSabotageModel>>((ref) async {
  final repo = ref.read(clientSabotageRepositoryProvider);
  return repo.getClients();
});
