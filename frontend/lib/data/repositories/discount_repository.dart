import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/discount_model.dart';

class DiscountRepository {
  Future<List<DiscountModel>> getDiscounts() async {
    final res = await dio.get('/api/discounts/');
    final raw = res.data is Map
        ? (res.data['data'] as List? ?? [])
        : (res.data as List? ?? []);
    return raw
        .map((e) => DiscountModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<DiscountModel> createDiscount(Map<String, dynamic> data) async {
    final res = await dio.post('/api/discounts/', data: data);
    return DiscountModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<DiscountModel> updateDiscount(String id, Map<String, dynamic> data) async {
    final res = await dio.put('/api/discounts/$id', data: data);
    return DiscountModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> deleteDiscount(String id) async {
    await dio.delete('/api/discounts/$id');
  }
}
