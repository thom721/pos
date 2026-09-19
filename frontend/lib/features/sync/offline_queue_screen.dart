import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/providers/sync_provider.dart';
import 'package:pos_connect/services/offline_queue_service.dart';

/// Écran de diagnostic — liste brute des opérations hors-ligne pas encore
/// synchronisées avec le serveur. Une opération n'est JAMAIS supprimée
/// automatiquement (voir OfflineQueueService.drain) : elle reste ici tant
/// qu'elle n'a pas réussi. Cet écran sert à vérifier ce qui est réellement
/// en attente plutôt que de deviner, et à forcer une resynchro manuelle.
class OfflineQueueScreen extends ConsumerStatefulWidget {
  const OfflineQueueScreen({super.key});

  @override
  ConsumerState<OfflineQueueScreen> createState() => _OfflineQueueScreenState();
}

class _OfflineQueueScreenState extends ConsumerState<OfflineQueueScreen> {
  List<OfflineQueueItem> _items = [];
  bool _loading = true;
  bool _syncing = false;
  final _dateFmt = DateFormat('dd/MM/yyyy HH:mm:ss');

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final items = await OfflineQueueService.instance.peekAll();
    // Plus récent en premier — les plus anciens (souvent les plus
    // problématiques) restent visibles en scrollant.
    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (mounted) setState(() { _items = items; _loading = false; });
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    try {
      final replayed = await OfflineQueueService.instance.drain(dio);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(replayed > 0
              ? '$replayed opération(s) synchronisée(s)'
              : 'Aucune opération synchronisée (toujours hors ligne ou serveur injoignable)'),
        ));
      }
    } finally {
      ref.invalidate(pendingOfflineCountProvider);
      if (mounted) setState(() => _syncing = false);
      await _refresh();
    }
  }

  String _summarize(OfflineQueueItem item) {
    final data = item.data;
    if (data is! Map) return '${item.method} ${item.path}';
    if (item.path == '/api/sales/') {
      final items = data['items'];
      final n = items is List ? items.length : 0;
      final paid = data['paid_amount'];
      return 'Vente — $n article(s) — payé $paid HTG (${data['payment_method'] ?? '?'})';
    }
    if (item.path == '/api/customers/') {
      return 'Client — ${data['name'] ?? data['full_name'] ?? '(sans nom)'}';
    }
    if (item.path == '/api/purchases/') {
      return 'Achat — ${data['total_amount'] ?? '?'} HTG';
    }
    return '${item.method} ${item.path}';
  }

  Future<void> _confirmDelete(OfflineQueueItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer définitivement ?'),
        content: Text(
          'Cette opération n\'a jamais été confirmée par le serveur — '
          'si elle représente une vraie vente/opération, ses données seront '
          'perdues pour toujours si tu continues.\n\n${_summarize(item)}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer quand même'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await OfflineQueueService.instance.removeOne(item.id);
      ref.invalidate(pendingOfflineCountProvider);
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Opérations hors-ligne en attente'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Rafraîchir',
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: AppColors.surface,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_items.length} en attente',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _syncing || _items.isEmpty ? null : _syncNow,
                        icon: _syncing
                            ? const SizedBox(
                                width: 14, height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.sync_rounded, size: 16),
                        label: const Text('Forcer la resynchro'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _items.isEmpty
                      ? const Center(
                          child: Text('Rien en attente — tout est synchronisé',
                              style: TextStyle(color: AppColors.textSecondary)),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (ctx, i) {
                            final item = _items[i];
                            return Card(
                              child: ExpansionTile(
                                title: Text(_summarize(item),
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                  '${_dateFmt.format(item.timestamp)}'
                                  '${item.retries > 0 ? ' — ${item.retries} échec(s)' : ''}',
                                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                ),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        SelectableText(
                                          item.data.toString(),
                                          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                                        ),
                                        const SizedBox(height: 8),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: TextButton.icon(
                                            onPressed: () => _confirmDelete(item),
                                            icon: const Icon(Icons.delete_forever_rounded,
                                                size: 16, color: AppColors.error),
                                            label: const Text('Supprimer définitivement',
                                                style: TextStyle(color: AppColors.error)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
