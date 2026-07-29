import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart' show extractAnyError;
import 'package:pos_connect/data/models/client_sabotage_model.dart';
import 'package:pos_connect/data/repositories/client_sabotage_repository.dart';
import 'package:pos_connect/providers/client_sabotage_provider.dart';
import 'package:pos_connect/providers/settings_provider.dart';

final _fmt = NumberFormat.currency(locale: 'fr_HT', symbol: 'HTG ', decimalDigits: 2);

class ClientsSabotageScreen extends ConsumerStatefulWidget {
  const ClientsSabotageScreen({super.key});

  @override
  ConsumerState<ClientsSabotageScreen> createState() => _ClientsSabotageScreenState();
}

class _ClientsSabotageScreenState extends ConsumerState<ClientsSabotageScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final clientsAsync = ref.watch(clientsSabotageProvider);

    return Column(
      children: [
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Rechercher un client (nom, téléphone, n° de compte)...',
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => _showForm(context),
                icon: const Icon(Icons.person_add_rounded, size: 18),
                label: const Text('Nouveau client'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: clientsAsync.when(
            data: (clients) {
              final filtered = _search.isEmpty
                  ? clients
                  : clients.where((c) =>
                      c.fullName.toLowerCase().contains(_search) ||
                      c.telephone.contains(_search) ||
                      c.accountNumber.contains(_search)).toList();
              if (filtered.isEmpty) {
                return const Center(
                  child: Text('Aucun client trouvé', style: TextStyle(color: AppColors.textSecondary)),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _ClientCard(client: filtered[i]),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
                child: Text('Erreur: ${extractAnyError(e)}', style: const TextStyle(color: AppColors.error))),
          ),
        ),
      ],
    );
  }

  void _showForm(BuildContext context, [ClientSabotageModel? client]) {
    showDialog(context: context, builder: (_) => ClientSabotageFormDialog(client: client));
  }
}

class _ClientCard extends ConsumerWidget {
  final ClientSabotageModel client;
  const _ClientCard({required this.client});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withOpacity(0.1),
          child: Text(
            client.fullName.isNotEmpty ? client.fullName.substring(0, 1).toUpperCase() : '?',
            style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
          ),
        ),
        title: Text(client.fullName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(client.telephone, style: const TextStyle(fontSize: 12)),
            Text('N° de compte : ${client.accountNumber}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('Solde', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            Text(_fmt.format(client.balance),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary)),
          ],
        ),
        onTap: () => showDialog(context: context, builder: (_) => ClientSabotageFormDialog(client: client)),
      ),
    );
  }
}

class ClientSabotageFormDialog extends ConsumerStatefulWidget {
  final ClientSabotageModel? client;
  const ClientSabotageFormDialog({super.key, this.client});

  @override
  ConsumerState<ClientSabotageFormDialog> createState() => _ClientSabotageFormDialogState();
}

class _ClientSabotageFormDialogState extends ConsumerState<ClientSabotageFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nomCtrl;
  late final TextEditingController _prenomCtrl;
  late final TextEditingController _telephoneCtrl;
  late final TextEditingController _adresseCtrl;
  late final Map<String, TextEditingController> _extraCtrls;
  bool _loading = false;
  String? _error;

  bool get isEdit => widget.client != null;

  @override
  void initState() {
    super.initState();
    _nomCtrl = TextEditingController(text: widget.client?.nom ?? '');
    _prenomCtrl = TextEditingController(text: widget.client?.prenom ?? '');
    _telephoneCtrl = TextEditingController(text: widget.client?.telephone ?? '');
    _adresseCtrl = TextEditingController(text: widget.client?.adresse ?? '');

    final configuredFields = ref.read(settingsProvider).clientSabotageFields;
    _extraCtrls = {
      for (final f in configuredFields)
        (f['label'] as String? ?? ''): TextEditingController(
          text: widget.client?.extraFields[f['label'] as String? ?? ''] ?? '',
        ),
    };
  }

  @override
  void dispose() {
    _nomCtrl.dispose();
    _prenomCtrl.dispose();
    _telephoneCtrl.dispose();
    _adresseCtrl.dispose();
    for (final c in _extraCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final configuredFields = ref.watch(settingsProvider).clientSabotageFields;

    return AlertDialog(
      title: Text(isEdit ? 'Modifier le client' : 'Nouveau client'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isEdit) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('N° de compte : ${widget.client!.accountNumber}',
                        style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.primary)),
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _nomCtrl,
                  decoration: const InputDecoration(labelText: 'Nom *'),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Requis' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _prenomCtrl,
                  decoration: const InputDecoration(labelText: 'Prénom *'),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Requis' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _telephoneCtrl,
                  decoration: const InputDecoration(labelText: 'Téléphone *'),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Requis' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _adresseCtrl,
                  decoration: const InputDecoration(labelText: 'Adresse *'),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Requis' : null,
                ),
                for (final f in configuredFields) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _extraCtrls[f['label'] as String? ?? ''],
                    decoration: InputDecoration(
                      labelText: (f['required'] as bool? ?? false)
                          ? '${f['label']} *'
                          : f['label'] as String? ?? '',
                    ),
                    validator: (v) => (f['required'] as bool? ?? false) && (v == null || v.trim().isEmpty)
                        ? 'Requis'
                        : null,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: AppColors.error)),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        ElevatedButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text(isEdit ? 'Enregistrer' : 'Créer'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final extra = <String, String>{
        for (final entry in _extraCtrls.entries)
          if (entry.value.text.trim().isNotEmpty) entry.key: entry.value.text.trim(),
      };
      final data = {
        'nom': _nomCtrl.text.trim(),
        'prenom': _prenomCtrl.text.trim(),
        'telephone': _telephoneCtrl.text.trim(),
        'adresse': _adresseCtrl.text.trim(),
        if (extra.isNotEmpty) 'extra_fields': extra,
      };
      final repo = ClientSabotageRepository();
      if (isEdit) {
        await repo.updateClient(widget.client!.id, data);
      } else {
        await repo.createClient(data);
      }
      ref.invalidate(clientsSabotageProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = extractAnyError(e);
      });
    }
  }
}
