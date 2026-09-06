import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart' show extractAnyError;
import 'package:pos_connect/data/models/expense_model.dart';
import 'package:pos_connect/data/models/warehouse_model.dart';
import 'package:pos_connect/data/repositories/expense_repository.dart';
import 'package:pos_connect/providers/expense_provider.dart';
import 'package:pos_connect/providers/warehouse_provider.dart';

final _fmt = NumberFormat.currency(locale: 'fr_HT', symbol: 'HTG ', decimalDigits: 2);
final _dateFmt = DateFormat('dd/MM/yyyy');

class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(expensesProvider);

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
                    hintText: 'Rechercher une dépense...',
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                  ),
                  onChanged: (v) =>
                      ref.read(expenseSearchProvider.notifier).state = v,
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => const _ExpenseFormDialog(),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Nouvelle dépense'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: expensesAsync.when(
            data: (expenses) => expenses.data.isEmpty
                ? const Center(
                    child: Text('Aucune dépense enregistrée',
                        style: TextStyle(color: AppColors.textSecondary)))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: expenses.data.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _ExpenseCard(expense: expenses.data[i]),
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
                child: Text('Erreur: ${extractAnyError(e)}',
                    style: const TextStyle(color: AppColors.error))),
          ),
        ),
      ],
    );
  }
}

class _ExpenseCard extends ConsumerWidget {
  final ExpenseModel expense;

  const _ExpenseCard({required this.expense});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.payments_rounded, color: AppColors.error, size: 22),
        ),
        title: Text(expense.description,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                if (expense.category != null && expense.category!.isNotEmpty) expense.category!,
                _dateFmt.format(expense.expenseDate),
                if (expense.warehouseName != null) expense.warehouseName!,
              ].join(' · '),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            if (expense.userName != null)
              Text('Saisi par ${expense.userName}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_fmt.format(expense.amount),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: AppColors.textSecondary, size: 18),
              onPressed: () => showDialog(
                context: context,
                builder: (_) => _ExpenseFormDialog(expense: expense),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 18),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Supprimer cette dépense ?'),
                    content: Text('« ${expense.description} » sera définitivement supprimée.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Annuler')),
                      ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Supprimer')),
                    ],
                  ),
                );
                if (confirm == true) {
                  try {
                    await ExpenseRepository().deleteExpense(expense.id);
                    ref.invalidate(expensesProvider);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(extractAnyError(e))),
                      );
                    }
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpenseFormDialog extends ConsumerStatefulWidget {
  final ExpenseModel? expense;

  const _ExpenseFormDialog({this.expense});

  @override
  ConsumerState<_ExpenseFormDialog> createState() => _ExpenseFormDialogState();
}

class _ExpenseFormDialogState extends ConsumerState<_ExpenseFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _categoryCtrl;
  late final TextEditingController _amountCtrl;
  late DateTime _date;
  String? _warehouseId;
  bool _loading = false;
  String? _error;

  bool get isEdit => widget.expense != null;

  @override
  void initState() {
    super.initState();
    _descriptionCtrl = TextEditingController(text: widget.expense?.description ?? '');
    _categoryCtrl = TextEditingController(text: widget.expense?.category ?? '');
    _amountCtrl = TextEditingController(
        text: widget.expense != null ? widget.expense!.amount.toStringAsFixed(2) : '');
    _date = widget.expense?.expenseDate ?? DateTime.now();
    _warehouseId = widget.expense?.warehouseId;
  }

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    _categoryCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final warehousesAsync = ref.watch(warehouseListProvider);

    return AlertDialog(
      title: Text(isEdit ? 'Modifier la dépense' : 'Nouvelle dépense'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _descriptionCtrl,
                decoration: const InputDecoration(labelText: 'Description *'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Requis' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _categoryCtrl,
                decoration: const InputDecoration(
                    labelText: 'Catégorie', hintText: 'Loyer, transport, fournitures...'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Montant (HTG) *'),
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  if (n == null || n <= 0) return 'Montant invalide';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Date'),
                  child: Text(_dateFmt.format(_date)),
                ),
              ),
              const SizedBox(height: 12),
              warehousesAsync.when(
                data: (warehouses) => DropdownButtonFormField<String?>(
                  initialValue: _warehouseId,
                  decoration: const InputDecoration(labelText: 'Dépôt (optionnel)'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Aucun dépôt en particulier')),
                    ...warehouses.map((WarehouseModel w) =>
                        DropdownMenuItem<String?>(value: w.id, child: Text(w.name))),
                  ],
                  onChanged: (v) => setState(() => _warehouseId = v),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: AppColors.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        ElevatedButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
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
        'description': _descriptionCtrl.text.trim(),
        'category': _categoryCtrl.text.trim().isEmpty ? null : _categoryCtrl.text.trim(),
        'amount': double.parse(_amountCtrl.text),
        'expense_date': _date.toIso8601String(),
        'warehouse_id': _warehouseId,
      };
      final repo = ExpenseRepository();
      if (isEdit) {
        await repo.updateExpense(widget.expense!.id, data);
      } else {
        await repo.createExpense(data);
      }
      ref.invalidate(expensesProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = extractAnyError(e);
      });
    }
  }
}
