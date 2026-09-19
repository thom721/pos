import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:pos_connect/data/api/api_client.dart' show kBackgroundOptions;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:pos_connect/data/models/sale_model.dart';
import 'package:pos_connect/services/local_db_service.dart';

// ── Item ─────────────────────────────────────────────────────────────────────

class OfflineQueueItem {
  final String id;
  final String method;
  final String path;
  final dynamic data;
  final DateTime timestamp;
  final int retries;

  const OfflineQueueItem({
    required this.id,
    required this.method,
    required this.path,
    required this.data,
    required this.timestamp,
    this.retries = 0,
  });

  OfflineQueueItem copyWith({int? retries}) => OfflineQueueItem(
        id: id,
        method: method,
        path: path,
        data: data,
        timestamp: timestamp,
        retries: retries ?? this.retries,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'method': method,
        'path': path,
        'data': data,
        'timestamp': timestamp.toIso8601String(),
        'retries': retries,
      };

  factory OfflineQueueItem.fromJson(Map<String, dynamic> json) =>
      OfflineQueueItem(
        id: json['id'] as String,
        method: json['method'] as String,
        path: json['path'] as String,
        data: json['data'],
        timestamp: DateTime.parse(json['timestamp'] as String),
        retries: (json['retries'] as int?) ?? 0,
      );
}

// ── Service ───────────────────────────────────────────────────────────────────

class OfflineQueueService {
  static final OfflineQueueService instance = OfflineQueueService._();
  OfflineQueueService._();

  static const _prefKey = 'offline_ops_queue_v1';
  bool _draining = false;

  // Paths never queued offline (auth + sync endpoints)
  static const _skipPaths = [
    '/api/auth',
    '/api/login',
    '/api/public',
    '/api/sync',
    '/api/setup',
  ];

  // ── Persistence ────────────────────────────────────────────────────────────

  Future<List<OfflineQueueItem>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getStringList(_prefKey) ?? [];
    final items = raw.map((s) {
      try {
        return OfflineQueueItem.fromJson(jsonDecode(s) as Map<String, dynamic>);
      } catch (_) {
        return null;
      }
    }).whereType<OfflineQueueItem>().toList();

    // Filet de sécurité : un item rejoué qui échouait encore était ré-ajouté
    // en double par OfflineInterceptor (voir drain() — corrigé, mais des
    // doublons ont pu s'accumuler avant ce correctif). On dédoublonne par
    // contenu (method+path+data) plutôt que par id — chaque opération réelle
    // (vente, client…) embarque son propre id local dans data, donc deux
    // opérations légitimement identiques restent bien distinctes.
    final seen = <String>{};
    final deduped = <OfflineQueueItem>[];
    for (final item in items) {
      final key = '${item.method} ${item.path} ${jsonEncode(item.data)}';
      if (seen.add(key)) deduped.add(item);
    }
    if (deduped.length != items.length) {
      debugPrint('[OfflineQueue] ${items.length - deduped.length} doublon(s) supprimé(s)');
      await _save(deduped);
    }
    return deduped;
  }

  Future<void> _save(List<OfflineQueueItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefKey,
      items.map((i) => jsonEncode(i.toJson())).toList(),
    );
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<int> pendingCount() async => (await _load()).length;

  /// Snapshot en lecture des opérations en attente — pour l'écran de
  /// diagnostic (features/debug/offline_queue_screen.dart). Nettoie aussi
  /// les doublons éventuels au passage (voir _load).
  Future<List<OfflineQueueItem>> peekAll() => _load();

  /// Supprime définitivement UNE opération de la file — action manuelle et
  /// délibérée uniquement (jamais automatique, voir drain()). À utiliser
  /// seulement quand on est certain que l'opération est irrécupérable
  /// (ex: référence une donnée qui n'existe plus) ou déjà traitée
  /// manuellement côté serveur.
  Future<void> removeOne(String id) async {
    final items = await _load();
    items.removeWhere((i) => i.id == id);
    await _save(items);
  }

  /// Called by [OfflineInterceptor] when a mutation fails due to no connection.
  Future<void> enqueue(RequestOptions req) async {
    final path = req.path;
    if (_skipPaths.any((s) => path.startsWith(s))) return;

    final items = await _load();
    items.add(OfflineQueueItem(
      id:        const Uuid().v4(),
      method:    req.method,
      path:      path,
      data:      req.data,
      timestamp: DateTime.now(),
    ));
    await _save(items);
    debugPrint('[OfflineQueue] queued ${req.method} $path  (total: ${items.length})');
  }

  /// Replay all queued items. Returns the number successfully replayed.
  ///
  /// Rien n'est jamais abandonné : une opération hors-ligne représente une
  /// vente/un paiement réel qui doit finir par atteindre le serveur — la
  /// perdre silencieusement après N essais serait une perte de donnée
  /// métier. Un item qui échoue reste en file indéfiniment (compteur
  /// [OfflineQueueItem.retries] gardé uniquement à titre diagnostique) et
  /// sera rejoué au prochain appel de [drain].
  ///
  /// On vérifie d'abord la connectivité réseau réelle (pas seulement le
  /// résultat de la requête) : sans ça, chaque cycle de synchro hors-ligne
  /// tentait quand même tous les items un par un, pour échouer à coup sûr —
  /// bruit inutile dans les logs et dans le compteur de retries.
  ///
  /// Non réentrant : plusieurs déclencheurs (push WebSocket, timer de
  /// secours, retour au premier plan, bouton "synchroniser") peuvent
  /// appeler drain() en même temps. Sans garde, deux appels concurrents
  /// liraient/écriraient la file en parallèle — c'est ce qui provoquait
  /// l'explosion de doublons (voir aussi le flag skipOfflineQueue ci-dessous).
  Future<int> drain(Dio apiDio) async {
    if (_draining) return 0;
    _draining = true;
    try {
      final items = await _load();
      if (items.isEmpty) return 0;

      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none) && connectivity.length == 1) {
        debugPrint('[OfflineQueue] pas de réseau — synchro reportée (${items.length} en attente)');
        return 0;
      }

      int replayed = 0;
      final remaining = <OfflineQueueItem>[];

      for (final item in items) {
        dynamic responseData;
        try {
          final res = await apiDio.request<dynamic>(
            item.path,
            data: item.data,
            options: Options(method: item.method,
                // skipOfflineQueue: sans ce flag, un échec ICI (ex: toujours
                // hors ligne) était réinterprété par OfflineInterceptor comme
                // une TOUTE NOUVELLE mutation ratée et ré-enfilé en double —
                // en plus de l'item déjà conservé ci-dessous. Sur des cycles
                // répétés (chaque tentative crée un nouveau doublon d'origine),
                // la file grossissait sans limite.
                extra: {...?kBackgroundOptions.extra, 'skipOfflineQueue': true}),
          );
          responseData = res.data;
        } catch (e) {
          final next = item.copyWith(retries: item.retries + 1);
          debugPrint('[OfflineQueue] échec #${next.retries} ${item.method} ${item.path} — conservé en file');
          remaining.add(next);
          continue;
        }

        // Le serveur a confirmé l'opération — elle est synchronisée, quoi
        // qu'il arrive ensuite. _handleSyncResponse ne fait que mettre à
        // jour le cache SQLite local (référence, id serveur…) ; une erreur
        // à cette étape (ex: écriture SQLite) ne doit JAMAIS faire repasser
        // une vente déjà synchronisée en attente — avant ce correctif, ce
        // try/catch commun aurait re-mis l'item en file dans ce cas, alors
        // que la vente existait déjà côté serveur.
        replayed++;
        debugPrint('[OfflineQueue] replayed ${item.method} ${item.path}');
        try {
          await _handleSyncResponse(item, responseData);
        } catch (e) {
          debugPrint('[OfflineQueue] post-traitement local échoué pour '
              '${item.method} ${item.path} (déjà synchronisé côté serveur) : $e');
        }
      }

      await _save(remaining);
      return replayed;
    } finally {
      _draining = false;
    }
  }

  /// Met à jour le SQLite local après une sync réussie.
  Future<void> _handleSyncResponse(OfflineQueueItem item, dynamic responseData) async {
    if (responseData is! Map) return;

    // Vente créée offline → remplace intégralement la ligne locale
    // provisoire (référence "HL-xxxxxxxx", loyalty_earned estimé) avec la
    // vente complète renvoyée par le serveur (voir routes/sales.py::store_sale)
    // — auparavant "reference" était cherché à la racine de la réponse, qui
    // ne l'a jamais contenu (seulement sale_id) : markSaleSynced n'était donc
    // jamais appelé pour une vente réellement mise en file d'attente hors-
    // ligne, laissant sa référence locale figée jusqu'au prochain sync complet.
    if (item.method == 'POST' && item.path == '/api/sales/') {
      final clientId = (item.data is Map) ? item.data['client_id'] as String? : null;
      final saleJson = responseData['sale'] as Map<String, dynamic>?;
      if (clientId != null && saleJson != null) {
        final saleModel = SaleModel.fromJson(saleJson);
        await LocalDbService.instance.upsertSales([saleModel]);
        debugPrint('[OfflineQueue] sale $clientId synced → ${saleModel.reference}');
      }
    }

    // Client créé offline → marquer comme synchronisé
    if (item.method == 'POST' && item.path == '/api/customers/') {
      final localId  = (item.data is Map) ? item.data['local_id'] as String? : null;
      final serverId = responseData['id'] as String?;
      if (localId != null && serverId != null) {
        await LocalDbService.instance.markCustomerSynced(localId, serverId);
        debugPrint('[OfflineQueue] customer $localId synced → $serverId');
      }
    }

    // Achat créé offline → marquer comme synchronisé
    if (item.method == 'POST' && item.path == '/api/purchases/') {
      final clientId  = (item.data is Map) ? item.data['client_id'] as String? : null;
      final reference = responseData['reference'] as String?;
      if (clientId != null && reference != null) {
        await LocalDbService.instance.markPurchaseSynced(clientId, reference);
        debugPrint('[OfflineQueue] purchase $clientId synced → $reference');
      }
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }
}
