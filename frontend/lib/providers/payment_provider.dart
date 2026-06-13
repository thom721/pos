import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/payment_model.dart';

final paymentHistoryProvider = FutureProvider.autoDispose
    .family<List<PaymentModel>, (String, String)>((ref, args) async {
  final (referenceType, referenceId) = args;
  final res = await dio.get('/api/payments/', queryParameters: {
    'reference_type': referenceType,
    'reference_id': referenceId,
  });
  final data = res.data as List? ?? [];
  return data
      .map((e) => PaymentModel.fromJson(e as Map<String, dynamic>))
      .toList();
});
