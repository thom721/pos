import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/models/supplier_model.dart';
import 'package:pos_connect/data/repositories/supplier_repository.dart';
import 'package:pos_connect/providers/supplier_provider.dart';

class SuppliersScreen extends ConsumerWidget {
  const SuppliersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliersAsync = ref.watch(suppliersProvider);

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
                    hintText: 'Rechercher un fournisseur...',
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                  ),
                  onChanged: (v) =>
                      ref.read(supplierSearchProvider.notifier).state = v,
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => const _SupplierFormDialog(),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Nouveau fournisseur'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: suppliersAsync.when(
            data: (suppliers) => suppliers.data.isEmpty
                ? const Center(
                    child: Text('Aucun fournisseur trouvé',
                        style:
                            TextStyle(color: AppColors.textSecondary)))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: suppliers.data.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) =>
                        _SupplierCard(supplier: suppliers.data[i]),
                  ),
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
                child: Text('Erreur: $e',
                    style: const TextStyle(color: AppColors.error))),
          ),
        ),
      ],
    );
  }
}

class _SupplierCard extends ConsumerWidget {
  final SupplierModel supplier;

  const _SupplierCard({required this.supplier});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.warning.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.local_shipping_rounded,
              color: AppColors.warning, size: 22),
        ),
        title: Text(supplier.name,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (supplier.phone != null)
              Text(supplier.phone!,
                  style: const TextStyle(fontSize: 12)),
            if (supplier.email != null)
              Text(supplier.email!,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.edit_outlined,
              color: AppColors.textSecondary, size: 18),
          onPressed: () => showDialog(
            context: context,
            builder: (_) => _SupplierFormDialog(supplier: supplier),
          ),
        ),
      ),
    );
  }
}

class _SupplierFormDialog extends ConsumerStatefulWidget {
  final SupplierModel? supplier;

  const _SupplierFormDialog({this.supplier});

  @override
  ConsumerState<_SupplierFormDialog> createState() =>
      _SupplierFormDialogState();
}

class _SupplierFormDialogState
    extends ConsumerState<_SupplierFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _addressCtrl;
  bool _loading = false;
  String? _error;

  bool get isEdit => widget.supplier != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.supplier?.name ?? '');
    _phoneCtrl =
        TextEditingController(text: widget.supplier?.phone ?? '');
    _emailCtrl =
        TextEditingController(text: widget.supplier?.email ?? '');
    _addressCtrl =
        TextEditingController(text: widget.supplier?.address ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(isEdit ? 'Modifier le fournisseur' : 'Nouveau fournisseur'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nom *'),
                validator: (v) => v!.isEmpty ? 'Requis' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                  controller: _phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Téléphone')),
              const SizedBox(height: 12),
              TextFormField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email')),
              const SizedBox(height: 12),
              TextFormField(
                  controller: _addressCtrl,
                  decoration: const InputDecoration(labelText: 'Adresse')),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: const TextStyle(color: AppColors.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        ElevatedButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
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
      final data = {
        'name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        'email': _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        'address': _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
      };
      final repo = SupplierRepository();
      if (isEdit) {
        await repo.updateSupplier(widget.supplier!.id, data);
      } else {
        await repo.createSupplier(data);
      }
      ref.invalidate(suppliersProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Erreur lors de l\'enregistrement. Réessayez.';
      });
    }
  }
}
