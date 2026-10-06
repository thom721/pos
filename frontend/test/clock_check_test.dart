import 'package:flutter_test/flutter_test.dart';
import 'package:pos_connect/core/clock_check.dart';

void main() {
  test('parse une date RFC 1123 du serveur', () {
    final d = parseHttpDate('Mon, 06 Oct 2026 13:09:52 GMT');
    expect(d, DateTime.utc(2026, 10, 6, 13, 9, 52));
  });

  test('refuse une valeur absente ou mal formée', () {
    expect(parseHttpDate(null), isNull);
    expect(parseHttpDate('pas une date'), isNull);
    expect(parseHttpDate('Mon, 06 Foo 2026 13:09:52 GMT'), isNull);
  });
}
