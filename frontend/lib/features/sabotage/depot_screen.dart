import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart' show extractAnyError;
import 'package:pos_connect/data/models/client_sabotage_model.dart';
import 'package:pos_connect/data/repositories/depot_repository.dart';
import 'package:pos_connect/providers/client_sabotage_provider.dart';

final _fmt = NumberFormat.currency(locale: 'fr_HT', symbol: 'HTG ', decimalDigits: 2);

class DepotScreen extends ConsumerStatefulWidget {
  const DepotScreen({super.key});

  @override
  ConsumerState<DepotScreen> createState() => _DepotScreenState();
}

class _DepotScreenState extends ConsumerState<DepotScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  ClientSabotageModel? _selectedClient;
  bool _loading = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _selectedClient == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });
    try {
      await DepotRepository().createDepot({
        'client_id': _selectedClient!.id,
        'amount': double.parse(_amountCtrl.text.trim()),
        if (_noteCtrl.text.trim().isNotEmpty) 'note': _noteCtrl.text.trim(),
      });
      ref.invalidate(clientsSabotageProvider);
      setState(() {
        _success = 'Dépôt enregistré pour ${_selectedClient!.fullName}';
        _amountCtrl.clear();
        _noteCtrl.clear();
        _selectedClient = null;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = extractAnyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final clientsAsync = ref.watch(clientsSabotageProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Nouveau dépôt', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),
              clientsAsync.when(
                data: (clients) => _ClientPickerField(
                  clients: clients,
                  selected: _selectedClient,
                  onSelected: (c) => setState(() => _selectedClient = c),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Erreur: ${extractAnyError(e)}',
                    style: const TextStyle(color: AppColors.error)),
              ),
              if (_selectedClient != null) ...[
                const SizedBox(height: 8),
                Text('Solde actuel : ${_fmt.format(_selectedClient!.balance)}',
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Montant *'),
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  if (n == null || n <= 0) return 'Montant invalide';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteCtrl,
                decoration: const InputDecoration(labelText: 'Note (optionnel)'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.error)),
              ],
              if (_success != null) ...[
                const SizedBox(height: 12),
                Text(_success!, style: const TextStyle(color: AppColors.success)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: (_loading || _selectedClient == null) ? null : _submit,
                  icon: _loading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.savings_rounded),
                  label: const Text('Enregistrer le dépôt'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClientPickerField extends StatelessWidget {
  final List<ClientSabotageModel> clients;
  final ClientSabotageModel? selected;
  final ValueChanged<ClientSabotageModel?> onSelected;

  const _ClientPickerField({required this.clients, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<ClientSabotageModel>(
      initialValue: selected,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Client *'),
      items: clients
          .map((c) => DropdownMenuItem(
                value: c,
                child: Text('${c.fullName} — ${c.telephone} — Cpt ${c.accountNumber}'),
              ))
          .toList(),
      onChanged: onSelected,
      validator: (v) => v == null ? 'Sélectionnez un client' : null,
    );
  }
}
