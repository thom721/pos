import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_connect/core/permissions.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart' show extractAnyError;
import 'package:pos_connect/data/models/restaurant_model.dart';
import 'package:pos_connect/data/repositories/restaurant_repository.dart';
import 'package:pos_connect/providers/permission_provider.dart';
import 'package:pos_connect/providers/restaurant_provider.dart';
import 'package:pos_connect/providers/settings_provider.dart';

// ── Predefined room characteristics ──────────────────────────────────────────

const _kAttrKeys = [
  'Type de chambre',
  'Nombre de lits',
  'Type de lit',
  'Climatisation',
  'Vue',
  'Étage',
];

const _kAttrValues = <String, List<String>>{
  'Type de chambre': ['Standard', 'Deluxe', 'Suite', 'Familiale', 'VIP', 'Junior Suite'],
  'Nombre de lits':  ['1', '2', '3', '4'],
  'Type de lit':     ['Simple', 'Double', 'Queen Size', 'King Size', 'Superposés', 'Mixte'],
  'Climatisation':   ['AC', 'Ventilateur', 'Non climatisée'],
  'Vue':             ['Rue', 'Jardin', 'Piscine', 'Mer', 'Montagne', 'Cour'],
  'Étage':           ['RDC', '1er', '2e', '3e', '4e', '5e+'],
};

const _kCustom = '— Personnalisé…';

class _AttrEntry {
  String key;
  String value;
  bool customKey;
  bool customValue;
  _AttrEntry({required this.key, required this.value})
      : customKey   = !_kAttrKeys.contains(key),
        customValue = !(_kAttrValues[key]?.contains(value) ?? false);
}

// ── Screen ────────────────────────────────────────────────────────────────────

class TablesScreen extends ConsumerWidget {
  const TablesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tablesAsync = ref.watch(tablesProvider);
    final canCreate   = ref.watch(hasPermissionProvider(Perm.tablesCreate));
    final isHotel     = ref.watch(settingsProvider).businessType == 'hotel';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text(
          isHotel ? 'Chambres' : 'Plan de salle',
          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        actions: [
          if (!isHotel)
            IconButton(
              icon: const Icon(Icons.restaurant_menu_rounded, color: AppColors.primary),
              tooltip: 'Vue cuisine',
              onPressed: () => context.push('/restaurant/kitchen'),
            ),
          if (isHotel)
            IconButton(
              icon: const Icon(Icons.cleaning_services_rounded, color: AppColors.primary),
              tooltip: 'Housekeeping',
              onPressed: () => context.push('/restaurant/kitchen'),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
            onPressed: () => ref.invalidate(tablesProvider),
          ),
        ],
      ),
      body: tablesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 40),
              const SizedBox(height: 12),
              Text(extractAnyError(e), style: const TextStyle(color: AppColors.error)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(tablesProvider),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
        data: (tables) => tables.isEmpty
            ? _EmptyState(
                isHotel: isHotel,
                onAdd: canCreate ? () => _showAddDialog(context, ref, isHotel: isHotel) : null,
              )
            : _TableGrid(tables: tables, isHotel: isHotel),
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _showAddDialog(context, ref, isHotel: isHotel),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: Text(isHotel ? 'Ajouter une chambre' : 'Ajouter une table'),
            )
          : null,
    );
  }

  Future<void> _showAddDialog(BuildContext context, WidgetRef ref, {required bool isHotel}) async {
    final nameCtrl    = TextEditingController();
    final nightCtrl   = TextEditingController();
    final dayCtrl     = TextEditingController();
    final momentCtrl  = TextEditingController();
    int capacity = isHotel ? 2 : 4;
    final attrs  = <_AttrEntry>[];
    String? priceError;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 440, maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isHotel ? 'Nouvelle chambre' : 'Nouvelle table',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: isHotel ? 'Numéro / nom de la chambre' : 'Nom de la table',
                      hintText: isHotel ? 'Chambre 101, Suite A…' : 'Table 1, Terrasse A…',
                      border: const OutlineInputBorder(),
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 20),
                  Row(children: [
                    const Icon(Icons.people_outline_rounded, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Text(
                      isHotel ? 'Capacité (personnes) :' : 'Capacité :',
                      style: const TextStyle(fontSize: 15),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                      onPressed: () => setState(() { if (capacity > 1) capacity--; }),
                      color: AppColors.primary,
                    ),
                    SizedBox(
                      width: 36,
                      child: Text('$capacity',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      onPressed: () => setState(() => capacity++),
                      color: AppColors.primary,
                    ),
                  ]),
                  if (isHotel) ...[
                    const SizedBox(height: 16),
                    const Text('Tarifs (au moins un requis)',
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: nightCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() => priceError = null),
                          decoration: const InputDecoration(
                            labelText: 'Prix / nuit',
                            hintText: '0.00',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.nights_stay_outlined, size: 18),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: dayCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() => priceError = null),
                          decoration: const InputDecoration(
                            labelText: 'Prix / jour',
                            hintText: '0.00',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.wb_sunny_outlined, size: 18),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: momentCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() => priceError = null),
                          decoration: const InputDecoration(
                            labelText: 'Prix / moment',
                            hintText: '0.00',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.access_time_rounded, size: 18),
                            isDense: true,
                          ),
                        ),
                      ),
                    ]),
                    if (priceError != null) ...[
                      const SizedBox(height: 6),
                      Text(priceError!,
                          style: const TextStyle(color: AppColors.error, fontSize: 12)),
                    ],
                    const SizedBox(height: 20),
                    _AttrSection(attrs: attrs, onChanged: () => setState(() {})),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          if (nameCtrl.text.trim().isEmpty) return;
                          final pNight  = double.tryParse(nightCtrl.text.trim())  ?? 0.0;
                          final pDay    = double.tryParse(dayCtrl.text.trim())    ?? 0.0;
                          final pMoment = double.tryParse(momentCtrl.text.trim()) ?? 0.0;
                          if (isHotel && pNight == 0 && pDay == 0 && pMoment == 0) {
                            setState(() => priceError = 'Veuillez saisir au moins un tarif.');
                            return;
                          }
                          Navigator.pop(ctx);
                          try {
                            await RestaurantRepository().createTable(
                              name: nameCtrl.text.trim(),
                              capacity: capacity,
                              price: pNight,
                              pricePerDay: pDay,
                              pricePerMoment: pMoment,
                              attributes: attrs
                                  .where((a) => a.key.trim().isNotEmpty)
                                  .map((a) => RoomAttr(key: a.key.trim(), value: a.value.trim()))
                                  .toList(),
                            );
                            ref.invalidate(tablesProvider);
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(extractAnyError(e)),
                                backgroundColor: AppColors.error,
                              ));
                            }
                          }
                        },
                        child: const Text('Créer'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Grid ──────────────────────────────────────────────────────────────────────

class _TableGrid extends ConsumerWidget {
  final List<RestaurantTableModel> tables;
  final bool isHotel;
  const _TableGrid({required this.tables, required this.isHotel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: isHotel ? 200 : 180,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: isHotel ? 0.85 : 1.0,
        ),
        itemCount: tables.length,
        itemBuilder: (_, i) => _TableCard(table: tables[i], isHotel: isHotel),
      ),
    );
  }
}

// ── Card ──────────────────────────────────────────────────────────────────────

class _TableCard extends ConsumerWidget {
  final RestaurantTableModel table;
  final bool isHotel;
  const _TableCard({required this.table, required this.isHotel});

  Color get _color {
    if (table.isOccupied) return AppColors.warning;
    if (table.isReserved) return AppColors.info;
    return AppColors.success;
  }

  IconData get _icon {
    if (isHotel) {
      if (table.isOccupied) return Icons.king_bed_rounded;
      if (table.isReserved) return Icons.event_available_rounded;
      return Icons.king_bed_outlined;
    }
    if (table.isOccupied) return Icons.people_rounded;
    if (table.isReserved) return Icons.event_available_rounded;
    return Icons.chair_rounded;
  }

  String get _label {
    if (table.isOccupied) return isHotel ? 'Occupée'    : 'Occupée';
    if (table.isReserved) return isHotel ? 'Réservée'   : 'Réservée';
    return isHotel ? 'Disponible' : 'Libre';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canEdit   = ref.watch(hasPermissionProvider(Perm.tablesUpdate));
    final canDelete = ref.watch(hasPermissionProvider(Perm.tablesDelete));
    return GestureDetector(
      onTap: () => _openOrder(context),
      onLongPress: (canEdit || canDelete)
          ? () => _showOptions(context, ref, canEdit: canEdit, canDelete: canDelete)
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _color, width: 2),
          boxShadow: [BoxShadow(color: _color.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(_icon, color: _color, size: 26),
              ),
              const SizedBox(height: 6),
              Text(table.name,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_label,
                    style: TextStyle(color: _color, fontSize: 10, fontWeight: FontWeight.w600)),
              ),
              if (isHotel) ...[
                if (table.attributes.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 3,
                    alignment: WrapAlignment.center,
                    children: table.attributes.take(2).map((a) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Text(a.value,
                          style: const TextStyle(fontSize: 9, color: AppColors.textSecondary)),
                    )).toList(),
                  ),
                ],
                const SizedBox(height: 4),
                _PriceChips(table: table),
              ] else if (!isHotel) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.people_outline_rounded, size: 12, color: AppColors.textSecondary),
                    const SizedBox(width: 2),
                    Text('${table.capacity}',
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
              ],
              if (table.waiterName != null) ...[
                const SizedBox(height: 3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.person_outline_rounded, size: 11, color: AppColors.primary),
                    const SizedBox(width: 2),
                    Flexible(
                      child: Text(
                        table.waiterName!,
                        style: const TextStyle(fontSize: 10, color: AppColors.primary),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openOrder(BuildContext context) async {
    if (table.isOccupied) {
      try {
        final order = await RestaurantRepository().getTableOrder(table.id);
        if (order != null && context.mounted) {
          context.push('/restaurant/commande/${order.id}');
          return;
        }
      } catch (_) {}
    }
    if (context.mounted) {
      context.push('/restaurant/commandes', extra: table.id);
    }
  }

  Future<void> _showOptions(BuildContext context, WidgetRef ref,
      {bool canEdit = false, bool canDelete = false}) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canEdit) ...[
              ListTile(
                leading: const Icon(Icons.edit_rounded, color: AppColors.primary),
                title: Text(isHotel ? 'Modifier la chambre' : 'Modifier la table'),
                onTap: () async {
                  Navigator.pop(context);
                  await _showEditDialog(context, ref);
                },
              ),
              if (!isHotel) ListTile(
                leading: const Icon(Icons.person_pin_rounded, color: AppColors.info),
                title: const Text('Assigner un serveur'),
                subtitle: table.waiterName != null
                    ? Text(table.waiterName!, style: const TextStyle(color: AppColors.primary))
                    : const Text('Aucun serveur assigné'),
                onTap: () async {
                  Navigator.pop(context);
                  await _showAssignWaiterDialog(context, ref);
                },
              ),
              if (table.isFree) ListTile(
                leading: const Icon(Icons.event_available_rounded, color: AppColors.info),
                title: Text(isHotel ? 'Marquer comme réservée' : 'Marquer comme réservée'),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    await RestaurantRepository().updateTable(table.id, status: 'reserved');
                    ref.invalidate(tablesProvider);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(extractAnyError(e)), backgroundColor: AppColors.error),
                      );
                    }
                  }
                },
              ),
            ],
            if (canDelete) ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
              title: Text(
                isHotel ? 'Supprimer la chambre' : 'Supprimer',
                style: const TextStyle(color: AppColors.error),
              ),
              onTap: () async {
                Navigator.pop(context);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text(isHotel ? 'Supprimer la chambre' : 'Supprimer la table'),
                    content: Text('Supprimer "${table.name}" ?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Supprimer', style: TextStyle(color: AppColors.error)),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  try {
                    await RestaurantRepository().deleteTable(table.id);
                    ref.invalidate(tablesProvider);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(extractAnyError(e)), backgroundColor: AppColors.error),
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

  Future<void> _showAssignWaiterDialog(BuildContext context, WidgetRef ref) async {
    List<RestaurantWaiterModel>? waiters;
    try {
      waiters = await RestaurantRepository().getWaiters();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(extractAnyError(e)), backgroundColor: AppColors.error),
        );
      }
      return;
    }
    if (!context.mounted) return;

    String? selectedId = table.waiterId;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Serveur — ${table.name}'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ignore: deprecated_member_use
                RadioListTile<String?>(
                  value: null,
                  groupValue: selectedId,
                  title: const Text('Aucun serveur'),
                  onChanged: (v) => setState(() => selectedId = v),
                ),
                // ignore: deprecated_member_use
                ...waiters!.map((w) => RadioListTile<String?>(
                  value: w.id,
                  groupValue: selectedId,
                  title: Text(w.name.isNotEmpty ? w.name : w.username),
                  subtitle: w.name.isNotEmpty ? Text(w.username) : null,
                  onChanged: (v) => setState(() => selectedId = v),
                )),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await RestaurantRepository().assignWaiter(table.id, selectedId);
                  ref.invalidate(tablesProvider);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(extractAnyError(e)), backgroundColor: AppColors.error),
                    );
                  }
                }
              },
              child: const Text('Confirmer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditDialog(BuildContext context, WidgetRef ref) async {
    final nameCtrl   = TextEditingController(text: table.name);
    final nightCtrl  = TextEditingController(
        text: table.price > 0 ? table.price.toStringAsFixed(2) : '');
    final dayCtrl    = TextEditingController(
        text: table.pricePerDay > 0 ? table.pricePerDay.toStringAsFixed(2) : '');
    final momentCtrl = TextEditingController(
        text: table.pricePerMoment > 0 ? table.pricePerMoment.toStringAsFixed(2) : '');
    int capacity = table.capacity;
    final attrs  = table.attributes
        .map((a) => _AttrEntry(key: a.key, value: a.value))
        .toList();
    String? priceError;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 440, maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isHotel ? 'Modifier la chambre' : 'Modifier la table',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: isHotel ? 'Numéro / nom de la chambre' : 'Nom de la table',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(children: [
                    const Icon(Icons.people_outline_rounded, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Text(
                      isHotel ? 'Capacité (personnes) :' : 'Capacité :',
                      style: const TextStyle(fontSize: 15),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                      onPressed: () => setState(() { if (capacity > 1) capacity--; }),
                      color: AppColors.primary,
                    ),
                    SizedBox(
                      width: 36,
                      child: Text('$capacity',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      onPressed: () => setState(() => capacity++),
                      color: AppColors.primary,
                    ),
                  ]),
                  if (isHotel) ...[
                    const SizedBox(height: 16),
                    const Text('Tarifs (au moins un requis)',
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: nightCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() => priceError = null),
                          decoration: const InputDecoration(
                            labelText: 'Prix / nuit',
                            hintText: '0.00',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.nights_stay_outlined, size: 18),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: dayCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() => priceError = null),
                          decoration: const InputDecoration(
                            labelText: 'Prix / jour',
                            hintText: '0.00',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.wb_sunny_outlined, size: 18),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: momentCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() => priceError = null),
                          decoration: const InputDecoration(
                            labelText: 'Prix / moment',
                            hintText: '0.00',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.access_time_rounded, size: 18),
                            isDense: true,
                          ),
                        ),
                      ),
                    ]),
                    if (priceError != null) ...[
                      const SizedBox(height: 6),
                      Text(priceError!,
                          style: const TextStyle(color: AppColors.error, fontSize: 12)),
                    ],
                    const SizedBox(height: 20),
                    _AttrSection(attrs: attrs, onChanged: () => setState(() {})),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          final pNight  = double.tryParse(nightCtrl.text.trim())  ?? 0.0;
                          final pDay    = double.tryParse(dayCtrl.text.trim())    ?? 0.0;
                          final pMoment = double.tryParse(momentCtrl.text.trim()) ?? 0.0;
                          if (isHotel && pNight == 0 && pDay == 0 && pMoment == 0) {
                            setState(() => priceError = 'Veuillez saisir au moins un tarif.');
                            return;
                          }
                          Navigator.pop(ctx);
                          try {
                            await RestaurantRepository().updateTable(
                              table.id,
                              name: nameCtrl.text.trim(),
                              capacity: capacity,
                              price:         isHotel ? pNight  : null,
                              pricePerDay:   isHotel ? pDay    : null,
                              pricePerMoment: isHotel ? pMoment : null,
                              attributes: isHotel
                                  ? attrs
                                      .where((a) => a.key.trim().isNotEmpty)
                                      .map((a) => RoomAttr(key: a.key.trim(), value: a.value.trim()))
                                      .toList()
                                  : null,
                            );
                            ref.invalidate(tablesProvider);
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(extractAnyError(e)), backgroundColor: AppColors.error),
                              );
                            }
                          }
                        },
                        child: const Text('Enregistrer'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Price chips (hotel card) ───────────────────────────────────────────────────

class _PriceChips extends StatelessWidget {
  final RestaurantTableModel table;
  const _PriceChips({required this.table});

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    if (table.price > 0) {
      chips.add(_chip('${table.price.toStringAsFixed(0)}/nuit'));
    }
    if (table.pricePerDay > 0) {
      chips.add(_chip('${table.pricePerDay.toStringAsFixed(0)}/jour'));
    }
    if (table.pricePerMoment > 0) {
      chips.add(_chip('${table.pricePerMoment.toStringAsFixed(0)}/mom.'));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 3,
      runSpacing: 2,
      alignment: WrapAlignment.center,
      children: chips,
    );
  }

  Widget _chip(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: AppColors.primary.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(label,
        style: const TextStyle(fontSize: 9, color: AppColors.primary, fontWeight: FontWeight.w600)),
  );
}

// ── Attributes editor section ─────────────────────────────────────────────────

class _AttrSection extends StatelessWidget {
  final List<_AttrEntry> attrs;
  final VoidCallback onChanged;
  const _AttrSection({required this.attrs, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.tune_rounded, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          const Text('Caractéristiques',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const Spacer(),
          TextButton.icon(
            onPressed: () {
              attrs.add(_AttrEntry(key: _kAttrKeys.first, value: _kAttrValues[_kAttrKeys.first]!.first));
              onChanged();
            },
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Ajouter', style: TextStyle(fontSize: 13)),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary, padding: EdgeInsets.zero),
          ),
        ]),
        const SizedBox(height: 8),
        if (attrs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Aucune caractéristique. Appuyez sur + Ajouter.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary.withValues(alpha: 0.7)),
            ),
          ),
        ...List.generate(attrs.length, (i) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _AttrRow(
            entry: attrs[i],
            onDelete: () { attrs.removeAt(i); onChanged(); },
            onChanged: onChanged,
          ),
        )),
      ],
    );
  }
}

class _AttrRow extends StatefulWidget {
  final _AttrEntry entry;
  final VoidCallback onDelete;
  final VoidCallback onChanged;
  const _AttrRow({required this.entry, required this.onDelete, required this.onChanged});

  @override
  State<_AttrRow> createState() => _AttrRowState();
}

class _AttrRowState extends State<_AttrRow> {
  late final TextEditingController _keyCtrl;
  late final TextEditingController _valCtrl;

  @override
  void initState() {
    super.initState();
    _keyCtrl = TextEditingController(text: widget.entry.customKey   ? widget.entry.key   : '');
    _valCtrl = TextEditingController(text: widget.entry.customValue ? widget.entry.value : '');
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _valCtrl.dispose();
    super.dispose();
  }

  List<String> get _valuesForKey {
    final k = widget.entry.customKey ? '' : widget.entry.key;
    return _kAttrValues[k] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Key ──
        Expanded(
          child: e.customKey
              ? TextField(
                  controller: _keyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Caractéristique',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                  style: const TextStyle(fontSize: 13),
                  onChanged: (v) { e.key = v; widget.onChanged(); },
                )
              : DropdownButtonFormField<String>(
                  value: e.key,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                  items: [
                    ..._kAttrKeys.map((k) => DropdownMenuItem(value: k, child: Text(k))),
                    const DropdownMenuItem(value: _kCustom, child: Text(_kCustom, style: TextStyle(color: Colors.grey))),
                  ],
                  onChanged: (v) => setState(() {
                    if (v == _kCustom) {
                      e.customKey   = true;
                      e.key         = '';
                      e.customValue = true;
                      e.value       = '';
                    } else {
                      e.key         = v!;
                      e.customKey   = false;
                      final vals    = _kAttrValues[v] ?? [];
                      e.value       = vals.isNotEmpty ? vals.first : '';
                      e.customValue = false;
                    }
                    widget.onChanged();
                  }),
                ),
        ),
        const SizedBox(width: 8),
        // ── Value ──
        Expanded(
          child: (e.customKey || e.customValue || _valuesForKey.isEmpty)
              ? TextField(
                  controller: _valCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Valeur',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                  style: const TextStyle(fontSize: 13),
                  onChanged: (v) { e.value = v; widget.onChanged(); },
                )
              : DropdownButtonFormField<String>(
                  value: _valuesForKey.contains(e.value) ? e.value : _valuesForKey.first,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                  items: [
                    ..._valuesForKey.map((v) => DropdownMenuItem(value: v, child: Text(v))),
                    const DropdownMenuItem(value: _kCustom, child: Text(_kCustom, style: TextStyle(color: Colors.grey))),
                  ],
                  onChanged: (v) => setState(() {
                    if (v == _kCustom) {
                      e.customValue = true;
                      e.value       = '';
                      _valCtrl.clear();
                    } else {
                      e.value       = v!;
                      e.customValue = false;
                    }
                    widget.onChanged();
                  }),
                ),
        ),
        const SizedBox(width: 4),
        // ── Delete ──
        IconButton(
          icon: const Icon(Icons.close_rounded, size: 18),
          color: AppColors.error,
          onPressed: widget.onDelete,
          padding: const EdgeInsets.only(top: 2),
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback? onAdd;
  final bool isHotel;
  const _EmptyState({this.onAdd, required this.isHotel});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isHotel ? Icons.king_bed_rounded : Icons.table_restaurant_rounded,
            size: 72,
            color: AppColors.divider,
          ),
          const SizedBox(height: 16),
          Text(
            isHotel ? 'Aucune chambre configurée' : 'Aucune table configurée',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            isHotel
                ? 'Ajoutez vos chambres et leurs caractéristiques'
                : 'Ajoutez vos tables pour commencer à prendre des commandes',
            style: const TextStyle(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: Text(isHotel ? 'Ajouter une chambre' : 'Ajouter une table'),
          ),
        ],
      ),
    );
  }
}
