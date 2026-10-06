import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Décalage entre l'heure du serveur et celle de l'appareil (serveur − appareil),
/// mesuré à la dernière réponse réseau.
final ValueNotifier<Duration?> clockSkew = ValueNotifier<Duration?>(null);

/// Dernière heure du serveur reçue, gardée sur l'appareil pour vérifier hors-ligne.
final ValueNotifier<DateTime?> lastServerDate = ValueNotifier<DateTime?>(null);

/// Vrai quand l'heure de l'appareil est fausse : la caisse doit être bloquée.
final ValueNotifier<bool> clockSuspect = ValueNotifier<bool>(false);

/// Seuil au-delà duquel l'heure est considérée fausse.
const Duration clockSkewTolerance = Duration(minutes: 2);

const _kLastServerDate = 'clock_last_server_utc';
Timer? _watchTimer;

const _months = {
  'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
  'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
};

/// Lit une date RFC 1123 (ex: `Mon, 06 Oct 2026 13:09:52 GMT`).
DateTime? parseHttpDate(String? value) {
  if (value == null) return null;
  final m = RegExp(r'^\w{3}, (\d{2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$')
      .firstMatch(value.trim());
  if (m == null) return null;
  final month = _months[m.group(2)];
  if (month == null) return null;
  return DateTime.utc(
    int.parse(m.group(3)!), month, int.parse(m.group(1)!),
    int.parse(m.group(4)!), int.parse(m.group(5)!), int.parse(m.group(6)!),
  );
}

/// Charge la dernière heure serveur mémorisée (pour contrôler hors-ligne).
Future<void> loadLastServerDate() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLastServerDate);
    lastServerDate.value = raw == null ? null : DateTime.tryParse(raw);
  } catch (_) {}
  refreshClockState();
}

/// Mémorise la dernière heure serveur (jamais en arrière : on garde la plus récente).
Future<void> _persistLastServerDate(DateTime server) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastServerDate, server.toIso8601String());
  } catch (_) {}
}

/// Appelé à chaque réponse réseau : mesure le décalage et mémorise l'heure serveur.
void recordServerDate(String? headerValue) {
  final server = parseHttpDate(headerValue);
  if (server == null) return;
  clockSkew.value = server.difference(DateTime.now().toUtc());
  final prev = lastServerDate.value;
  if (prev == null || server.isAfter(prev)) {
    lastServerDate.value = server;
    _persistLastServerDate(server);
  }
  refreshClockState();
}

/// Recalcule l'état : hors-ligne, seule une heure reculée par rapport à la dernière synchro est détectable.
void refreshClockState() {
  final now = DateTime.now().toUtc();
  final skew = clockSkew.value;
  final last = lastServerDate.value;
  final wrongOnline = skew != null && skew.abs() > clockSkewTolerance;
  final wentBack = last != null && now.isBefore(last.subtract(clockSkewTolerance));
  clockSuspect.value = wrongOnline || wentBack;
}

/// Surveille l'horloge en continu (le retour arrière hors-ligne est vu sans requête).
void startClockWatch() {
  _watchTimer ??= Timer.periodic(const Duration(seconds: 30), (_) => refreshClockState());
}

/// Bannière affichée en haut de l'application quand l'heure de l'appareil est fausse.
class ClockWarningBanner extends StatefulWidget {
  const ClockWarningBanner({super.key});

  @override
  State<ClockWarningBanner> createState() => _ClockWarningBannerState();
}

class _ClockWarningBannerState extends State<ClockWarningBanner> {
  @override
  void initState() {
    super.initState();
    loadLastServerDate();
    startClockWatch();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: clockSuspect,
      builder: (context, suspect, _) {
        if (!suspect) return const SizedBox.shrink();
        final skew = clockSkew.value;
        final detail = skew != null && skew.abs() > clockSkewTolerance
            ? "L'heure de cet appareil est ${skew.isNegative ? 'en avance' : 'en retard'} "
                "d'environ ${skew.inMinutes.abs()} min."
            : "L'heure de cet appareil est antérieure à la dernière synchronisation.";
        return Material(
          color: Colors.orange.shade800,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.schedule_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$detail Encaissement bloqué : corrigez la date et l\'heure de l\'appareil.',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
