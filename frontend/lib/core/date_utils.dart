import 'package:timezone/timezone.dart' as tz;

// Haiti applique un DST (UTC-5 en hiver, UTC-4 en été) — utiliser la vraie
// base de données IANA (via package:timezone) plutôt qu'un offset fixe.
// initializeTimeZones() doit avoir été appelé au démarrage de l'app (main.dart).
tz.Location get _haiti => tz.getLocation('America/Port-au-Prince');

/// Convertit un DateTime UTC → heure locale de Port-au-Prince (DST-aware).
/// Le DateTime retourné contient les valeurs locales haïtiennes
/// (pas de timezone Dart attachée, utilisé pour l'affichage).
DateTime toHaitiTime(DateTime dt) {
  final utc = dt.isUtc ? dt : dt.toUtc();
  final local = tz.TZDateTime.from(utc, _haiti);
  return DateTime(local.year, local.month, local.day,
      local.hour, local.minute, local.second, local.millisecond);
}

/// Heure actuelle à Port-au-Prince.
DateTime haitiNow() => toHaitiTime(DateTime.now().toUtc());

/// Début du jour courant (minuit) à Port-au-Prince, exprimé en UTC.
/// À utiliser pour les filtres SQLite et API (les dates y sont stockées en UTC).
DateTime haitiTodayStartUtc() {
  final h = haitiNow();
  final localMidnight = tz.TZDateTime(_haiti, h.year, h.month, h.day);
  return localMidnight.toUtc();
}

/// Parse une date ISO renvoyée par l'API FastAPI.
/// Le backend envoie désormais des datetimes naïfs déjà en heure locale
/// Haiti (now_local(), sans 'Z') — on les utilise directement, sans
/// conversion supplémentaire. Les strings qui portent encore un offset/'Z'
/// (legacy) sont converties depuis UTC par précaution.
DateTime parseApiDate(String? s, {DateTime? fallback}) {
  if (s == null || s.isEmpty) return fallback ?? haitiNow();
  final parsed = DateTime.tryParse(s);
  if (parsed == null) return fallback ?? haitiNow();
  if (s.contains('Z') || RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(s)) {
    return toHaitiTime(parsed);
  }
  return parsed;
}
