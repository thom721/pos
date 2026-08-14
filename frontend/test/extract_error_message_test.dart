import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_connect/data/api/api_client.dart';

DioException _err(int status, Map<String, dynamic> data) {
  final req = RequestOptions(path: '/test');
  return DioException(
    requestOptions: req,
    response: Response(requestOptions: req, statusCode: status, data: data),
  );
}

void main() {
  group('extractErrorMessage', () {
    test('prefere "message" a "detail" quand les deux sont presents (bug device_pending_approval)', () {
      final e = _err(403, {
        'detail': 'device_pending_approval',
        'message': "Cet appareil doit être approuvé par un administrateur avant de pouvoir ouvrir une caisse.",
      });
      expect(extractErrorMessage(e),
          "Cet appareil doit être approuvé par un administrateur avant de pouvoir ouvrir une caisse.");
    });

    test('retombe sur "detail" quand "message" est absent (HTTPException classique)', () {
      final e = _err(400, {'detail': 'Le nom est requis'});
      expect(extractErrorMessage(e), 'Le nom est requis');
    });

    test('code HTTP generique si ni detail ni message ne sont utilisables', () {
      final e = _err(500, {});
      expect(extractErrorMessage(e), contains('Erreur interne du serveur'));
    });

    test('ignore les phrases HTTP generiques et retombe sur le code HTTP', () {
      final e = _err(404, {'detail': 'Not Found'});
      expect(extractErrorMessage(e), 'Ressource introuvable.');
    });
  });
}
