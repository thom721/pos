import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart' show extractAnyError;
import 'package:pos_connect/data/models/client_sabotage_model.dart';
import 'package:pos_connect/data/repositories/retrait_repository.dart';
import 'package:pos_connect/providers/client_sabotage_provider.dart';

final _fmt = NumberFormat.currency(locale: 'fr_HT', symbol: 'HTG ', decimalDigits: 2);

class RetraitScreen extends ConsumerStatefulWidget {
  const RetraitScreen({super.key});

  @override
  ConsumerState<RetraitScreen> createState() => _RetraitScreenState();
}

class _RetraitScreenState extends ConsumerState<RetraitScreen> {
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
    final amount = double.parse(_amountCtrl.text.trim());
    // Défense en profondeur — le serveur bloque de toute façon un solde négatif
    // (règle métier : record_retrait), mais on évite l'aller-retour réseau inutile.
    if (amount > _selectedClient!.balance) {
      setState(() => _error = 'Solde insuffisant (disponible : ${_fmt.format(_selectedClient!.balance)})');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });
    try {
      await RetraitRepository().createRetrait({
        'client_id': _selectedClient!.id,
        'amount': amount,
        if (_noteCtrl.text.trim().isNotEmpty) 'note': _noteCtrl.text.trim(),
      });
      ref.invalidate(clientsSabotageProvider);
      setState(() {
        _success = 'Retrait enregistré pour ${_selectedClient!.fullName}';
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
              const Text('Nouveau retrait', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),
              clientsAsync.when(
                data: (clients) => DropdownButtonFormField<ClientSabotageModel>(
                  initialValue: _selectedClient,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Client *'),
                  items: clients
                      .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text('${c.fullName} — ${c.telephone} — Cpt ${c.accountNumber}'),
                          ))
                      .toList(),
                  onChanged: (c) => setState(() => _selectedClient = c),
                  validator: (v) => v == null ? 'Sélectionnez un client' : null,
                ),
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Erreur: ${extractAnyError(e)}',
                    style: const TextStyle(color: AppColors.error)),
              ),
              if (_selectedClient != null) ...[
                const SizedBox(height: 8),
                Text('Solde disponible : ${_fmt.format(_selectedClient!.balance)}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
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
                      : const Icon(Icons.money_off_rounded),
                  label: const Text('Enregistrer le retrait'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
