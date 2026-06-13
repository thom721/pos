import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/paginated_response.dart';
import 'package:pos_connect/data/models/debt_model.dart';

class DebtRepository {
  Future<PaginatedResponse<DebtModel>> getDebts({
    int page = 1,
    int limit = 20,
    String? partnerType,
    String? status,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'limit': limit,
      if (partnerType != null) 'partner_type': partnerType,
      if (status != null) 'status': status,
    };
    final res = await dio.get('/api/debts/', queryParameters: params);
    return PaginatedResponse.fromJson(res.data, DebtModel.fromJson);
  }
}
