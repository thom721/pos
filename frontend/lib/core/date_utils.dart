// Haiti = UTC-5, pas de changement d'heure (America/Port_au_Prince)
const Duration _kHaitiOffset = Duration(hours: -5);

/// Convertit un DateTime UTC → heure locale de Port-au-Prince.
/// Le DateTime retourné contient les valeurs locales haïtiennes
/// (pas de timezone Dart attachée, utilisé pour l'affichage).
DateTime toHaitiTime(DateTime dt) {
  final utc = dt.toUtc();
  final local = utc.add(_kHaitiOffset);
  return DateTime(local.year, local.month, local.day,
      local.hour, local.minute, local.second, local.millisecond);
}

/// Heure actuelle à Port-au-Prince.
DateTime haitiNow() => toHaitiTime(DateTime.now().toUtc());

/// Début du jour courant (minuit) à Port-au-Prince, exprimé en UTC.
/// À utiliser pour les filtres SQLite et API (les dates y sont stockées en UTC).
/// Minuit haïtien = 05:00 UTC (UTC-5).
DateTime haitiTodayStartUtc() {
  final h = haitiNow();
  return DateTime.utc(h.year, h.month, h.day, 5, 0, 0);
}

/// Parse une date ISO renvoyée par l'API FastAPI.
/// FastAPI/SQLAlchemy retourne des datetimes UTC naïfs (sans 'Z').
/// Appende 'Z' si absent, puis convertit vers l'heure de Port-au-Prince.
DateTime parseApiDate(String? s, {DateTime? fallback}) {
  if (s == null || s.isEmpty) return fallback ?? haitiNow();
  final utc = (s.contains('Z') || s.contains('+')) ? s : '${s}Z';
  final parsed = DateTime.tryParse(utc);
  if (parsed == null) return fallback ?? haitiNow();
  return toHaitiTime(parsed);
}
