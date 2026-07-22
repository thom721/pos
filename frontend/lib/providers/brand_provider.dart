import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/data/api/api_client.dart';

/// Logo URL de la plateforme. Null = utiliser le logo asset par défaut.
final brandProvider = FutureProvider<String?>((ref) async {
  try {
    final res = await dio.get('/api/public/brand');
    final url = res.data['logo_url'] as String?;
    return (url != null && url.trim().isNotEmpty) ? url.trim() : null;
  } catch (_) {
    return null;
  }
});
