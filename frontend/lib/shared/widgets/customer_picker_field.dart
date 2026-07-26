import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/models/customer_model.dart';
import 'package:pos_connect/data/repositories/customer_repository.dart';
import 'package:pos_connect/providers/customer_provider.dart';

/// Champ client cliquable avec recherche et bouton "+ Ajouter un nouveau".
/// Utilisé dans proforma, facture et caisse.
class CustomerPickerField extends ConsumerWidget {
  final String? selectedId;
  final String? selectedName;
  final void Function(String? id, String? name) onChanged;
  final String label;
  final String emptyLabel;
  final bool isDense;

  const CustomerPickerField({
    super.key,
    required this.selectedId,
    required this.selectedName,
    required this.onChanged,
    this.label = 'Client',
    this.emptyLabel = 'Sans client',
    this.isDense = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customersAsync = ref.watch(customersProvider);

    return GestureDetector(
      onTap: () async {
        final customers = customersAsync.asData?.value.data ?? [];
        final result = await showDialog<({String? id, String? name})>(
          context: context,
          builder: (ctx) => UncontrolledProviderScope(
            container: ProviderScope.containerOf(context),
            child: _CustomerPickerDialog(
              customers: customers,
              selectedId: selectedId,
            ),
          ),
        );
        if (result != null) onChanged(result.id, result.name);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.person_outline, size: 20),
          isDense: isDense,
          contentPadding: isDense
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selectedName ?? emptyLabel,
                style: TextStyle(
                  fontSize: 14,
                  color: selectedId == null
                      ? Theme.of(context).hintColor
                      : null,
                ),
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Dialogue de sélection ─────────────────────────────────────────────────

class _CustomerPickerDialog extends ConsumerStatefulWidget {
  final List<CustomerModel> customers;
  final String? selectedId;

  const _CustomerPickerDialog({
    required this.customers,
    required this.selectedId,
  });

  @override
  ConsumerState<_CustomerPickerDialog> createState() =>
      _CustomerPickerDialogState();
}

class _CustomerPickerDialogState
    extends ConsumerState<_CustomerPickerDialog> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  late List<CustomerModel> _all;

  @override
  void initState() {
    super.initState();
    _all = widget.customers;
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<CustomerModel> get _filtered => _query.isEmpty
      ? _all
      : _all
          .where((c) =>
              c.name.toLowerCase().contains(_query) ||
              c.phone.toLowerCase().contains(_query))
          .toList();

  void _select(String? id, String? name) =>
      Navigator.pop(context, (id: id, name: name));

  Future<void> _addNew() async {
    final created = await showDialog<CustomerModel>(
      context: context,
      builder: (ctx) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: const _QuickCreateCustomerDialog(),
      ),
    );
    if (created != null && mounted) {
      ref.invalidate(customersProvider);
      _select(created.id, created.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
      title: const Text('Sélectionner un client'),
      content: SizedBox(
        width: 400,
        height: 440,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Rechercher...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => _searchCtrl.clear(),
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  // Option "Sans client"
                  _CustomerTile(
                    name: 'Sans client',
                    subtitle: null,
                    selected: widget.selectedId == null,
                    icon: Icons.person_off_outlined,
                    onTap: () => _select(null, null),
                  ),
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'Aucun client trouvé',
                          style: TextStyle(
                              color: Theme.of(context).hintColor,
                              fontSize: 13),
                        ),
                      ),
                    )
                  else
                    ...filtered.map((c) => _CustomerTile(
                          name: c.name,
                          subtitle: c.phone.isNotEmpty ? c.phone : null,
                          selected: c.id == widget.selectedId,
                          onTap: () => _select(c.id, c.name),
                        )),
                ],
              ),
            ),
            const Divider(height: 1),
            // Bouton "+ Ajouter un nouveau client"
            ListTile(
              dense: true,
              leading: Icon(Icons.person_add_alt_1_rounded,
                  color: AppColors.primary, size: 20),
              title: Text(
                '+ Ajouter un nouveau client',
                style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
              onTap: _addNew,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
      ],
    );
  }
}

class _CustomerTile extends StatelessWidget {
  final String name;
  final String? subtitle;
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;

  const _CustomerTile({
    required this.name,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.icon = Icons.person_outline,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(
        icon,
        size: 20,
        color: selected ? AppColors.primary : null,
      ),
      title: Text(
        name,
        style: TextStyle(
          fontSize: 13,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          color: selected ? AppColors.primary : null,
        ),
      ),
      subtitle: subtitle != null
          ? Text(subtitle!, style: const TextStyle(fontSize: 11))
          : null,
      trailing: selected
          ? Icon(Icons.check_rounded, size: 16, color: AppColors.primary)
          : null,
      onTap: onTap,
    );
  }
}

// ── Dialogue de création rapide ────────────────────────────────────────────

class _QuickCreateCustomerDialog extends ConsumerStatefulWidget {
  const _QuickCreateCustomerDialog();

  @override
  ConsumerState<_QuickCreateCustomerDialog> createState() =>
      _QuickCreateCustomerDialogState();
}

class _QuickCreateCustomerDialogState
    extends ConsumerState<_QuickCreateCustomerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final created = await CustomerRepository().createCustomer({
        'name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'address': '',
        'credit_limit': 0,
      });
      if (mounted) Navigator.pop(context, created);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Erreur lors de la création. Réessayez.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouveau client'),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.red, fontSize: 12)),
                ),
              TextFormField(
                controller: _nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'Nom *', isDense: true),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Champ requis' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneCtrl,
                decoration: const InputDecoration(
                    labelText: 'Téléphone', isDense: true),
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Créer'),
        ),
      ],
    );
  }
}
