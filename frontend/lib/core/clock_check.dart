import 'package:flutter/material.dart';

/// Décalage entre l'heure du serveur et celle de l'appareil (serveur − appareil).
/// Renseigné à chaque réponse réseau, à partir de l'en-tête HTTP `Date`.
final ValueNotifier<Duration?> clockSkew = ValueNotifier<Duration?>(null);

/// Seuil au-delà duquel les synchronisations peuvent créer des erreurs.
const Duration clockSkewTolerance = Duration(minutes: 2);

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

/// Met à jour le décalage à partir de la date renvoyée par le serveur.
void recordServerDate(String? headerValue) {
  final server = parseHttpDate(headerValue);
  if (server == null) return;
  clockSkew.value = server.difference(DateTime.now().toUtc());
}

/// Bannière affichée en haut de l'application quand l'heure de l'appareil est fausse.
class ClockWarningBanner extends StatelessWidget {
  const ClockWarningBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration?>(
      valueListenable: clockSkew,
      builder: (context, skew, _) {
        if (skew == null || skew.abs() <= clockSkewTolerance) {
          return const SizedBox.shrink();
        }
        final minutes = skew.inMinutes.abs();
        final ahead = skew.isNegative ? 'en avance' : 'en retard';
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
                      "L'heure de cet appareil est $ahead d'environ $minutes min. "
                      "Corrigez la date et l'heure pour éviter des erreurs de synchronisation.",
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
