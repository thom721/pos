import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

/// Journal fichier minimal pour le cycle de vie de la connexion WebSocket
/// (connexion, push reçu, reconnexion) — un exe Windows release Flutter
/// tourne en subsystem GUI, pas console : lancer pos_connect.exe depuis
/// cmd.exe n'affiche AUCUNE sortie debugPrint, même connecté (constaté en
/// prod). Sans fichier, impossible de diagnostiquer à distance pourquoi un
/// push WS n'arrive pas à un client précis.
class WsDebugLog {
  WsDebugLog._();
  static File? _file;
  static const _maxBytes = 2 * 1024 * 1024; // 2 Mo — tronqué au-delà

  static Future<File?> _getFile() async {
    if (kIsWeb) return null;
    if (_file != null) return _file;
    // getApplicationSupportDirectory() peut echouer ou resoudre un chemin
    // impossible a deviner selon la machine — plusieurs replis plutot que
    // d'abandonner silencieusement (constate en prod : fichier introuvable,
    // sans aucune indication de pourquoi ni d'alternative).
    final candidates = <Future<Directory> Function()>[
      getApplicationSupportDirectory,
      getTemporaryDirectory,
    ];
    for (final getDir in candidates) {
      try {
        final dir = await getDir();
        final f = File('${dir.path}/ws_debug.log');
        if (!await f.exists()) await f.create(recursive: true);
        _file = f;
        return f;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  /// Chemin du fichier, pour l'afficher à l'utilisateur (ex: écran Profil).
  static Future<String?> path() async => (await _getFile())?.path;

  static Future<void> log(String message) async {
    try {
      final f = await _getFile();
      if (f == null) return;
      if (await f.length() > _maxBytes) await f.writeAsString('');
      final ts = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      await f.writeAsString('[$ts] $message\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // Best-effort — ne jamais faire échouer l'appelant pour un log.
    }
  }
}
