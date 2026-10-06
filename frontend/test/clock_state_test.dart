import 'package:flutter_test/flutter_test.dart';
import 'package:pos_connect/core/clock_check.dart';

void main() {
  tearDown(() {
    clockSkew.value = null;
    lastServerDate.value = null;
    refreshClockState();
  });

  test('hors-ligne : une heure reculée par rapport à la dernière synchro bloque', () {
    lastServerDate.value = DateTime.now().toUtc().add(const Duration(hours: 1));
    refreshClockState();
    expect(clockSuspect.value, isTrue);
  });

  test('hors-ligne : une heure cohérente avec la dernière synchro ne bloque pas', () {
    lastServerDate.value = DateTime.now().toUtc().subtract(const Duration(days: 2));
    refreshClockState();
    expect(clockSuspect.value, isFalse);
  });

  test('en ligne : un décalage au-delà de 2 minutes bloque', () {
    clockSkew.value = const Duration(minutes: 10);
    refreshClockState();
    expect(clockSuspect.value, isTrue);
  });

  test('en ligne : un petit décalage ne bloque pas', () {
    clockSkew.value = const Duration(seconds: 30);
    refreshClockState();
    expect(clockSuspect.value, isFalse);
  });
}
