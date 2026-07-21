import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart' show extractAnyError;
import 'package:pos_connect/data/models/restaurant_model.dart';
import 'package:pos_connect/data/repositories/restaurant_repository.dart';

const _kSuggestions = [
  'Nettoyer la chambre',
  'Changer les draps',
  'Apporter des serviettes',
  'Réapprovisionner mini-bar',
  'Réparation à signaler',
];

class HousekeepingScreen extends ConsumerStatefulWidget {
  const HousekeepingScreen({super.key});

  @override
  ConsumerState<HousekeepingScreen> createState() => _HousekeepingScreenState();
}

class _HousekeepingScreenState extends ConsumerState<HousekeepingScreen> {
  List<RestaurantTableModel> _rooms = [];
  Map<String, RestaurantOrderModel?> _orderByRoom = {};
  Map<String, List<HousekeepingTaskModel>> _tasksByRoom = {};
  bool _loading = true;

  final _repo = RestaurantRepository();

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _isRoom(RestaurantTableModel t) =>
      t.price > 0 ||
      t.pricePerDay > 0 ||
      t.pricePerMoment > 0 ||
      t.attributes.isNotEmpty;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final tables = await _repo.getTables();
      final orders = await _repo.getOpenOrders();
      final tasks = await _repo.getHousekeepingTasks();

      final rooms = tables.where(_isRoom).toList();

      final orderByRoom = <String, RestaurantOrderModel?>{};
      for (final r in rooms) {
        orderByRoom[r.id] =
            orders.where((o) => o.tableId == r.id).firstOrNull;
      }

      final tasksByRoom = <String, List<HousekeepingTaskModel>>{};
      for (final r in rooms) {
        tasksByRoom[r.id] = tasks.where((t) => t.tableId == r.id).toList();
      }

      if (mounted) {
        setState(() {
          _rooms = rooms;
          _orderByRoom = orderByRoom;
          _tasksByRoom = tasksByRoom;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(extractAnyError(e)),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addTask(String tableId, String description) async {
    try {
      final task = await _repo.createHousekeepingTask(
          tableId: tableId, description: description);
      setState(() {
        _tasksByRoom[tableId] = [...(_tasksByRoom[tableId] ?? []), task];
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(extractAnyError(e)),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  Future<void> _toggleTask(HousekeepingTaskModel task) async {
    if (task.isDone) return;
    try {
      final updated = await _repo.markTaskDone(task.id);
      setState(() {
        final list = _tasksByRoom[task.tableId] ?? [];
        _tasksByRoom[task.tableId] =
            list.map((t) => t.id == task.id ? updated : t).toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(extractAnyError(e)),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  Future<void> _deleteTask(HousekeepingTaskModel task) async {
    try {
      await _repo.deleteHousekeepingTask(task.id);
      setState(() {
        _tasksByRoom[task.tableId] =
            (_tasksByRoom[task.tableId] ?? [])
                .where((t) => t.id != task.id)
                .toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(extractAnyError(e)),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  Future<void> _showAddTaskDialog(RestaurantTableModel room) async {
    final customCtrl = TextEditingController();
    String? picked;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: Text('Tâche — ${room.name}'),
          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Suggestions',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _kSuggestions.map((s) => ChoiceChip(
                      label: Text(s, style: const TextStyle(fontSize: 13)),
                      selected: picked == s,
                      onSelected: (v) {
                        setInner(() {
                          picked = v ? s : null;
                          if (v) customCtrl.clear();
                        });
                      },
                    )).toList(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: customCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Autre tâche…',
                      prefixIcon: Icon(Icons.edit_rounded, size: 18),
                    ),
                    onChanged: (_) => setInner(() => picked = null),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler')),
            FilledButton.icon(
              icon: const Icon(Icons.add_task_rounded, size: 18),
              label: const Text('Ajouter'),
              onPressed: () {
                final desc = customCtrl.text.trim().isNotEmpty
                    ? customCtrl.text.trim()
                    : picked;
                if (desc != null && desc.isNotEmpty) {
                  Navigator.pop(ctx, desc);
                }
              },
            ),
          ],
        ),
      ),
    );

    if (result != null) await _addTask(room.id, result);
  }

  String? _guestName(String tableId) {
    final order = _orderByRoom[tableId];
    if (order?.notes?.startsWith('🏨') ?? false) {
      return order!.notes!.substring(3).trim().split('|').first.trim();
    }
    return null;
  }

  String? _stayDates(String tableId) {
    final order = _orderByRoom[tableId];
    if (order?.notes?.startsWith('🏨') ?? false) {
      final parts = order!.notes!.split('|');
      if (parts.length >= 2) return parts[1].trim();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('Housekeeping',
            style: TextStyle(
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: AppColors.textSecondary),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rooms.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cleaning_services_rounded,
                          size: 56, color: AppColors.divider),
                      SizedBox(height: 12),
                      Text('Aucune chambre configurée',
                          style: TextStyle(color: AppColors.textSecondary)),
                      SizedBox(height: 6),
                      Text(
                        'Ajoutez un tarif ou des attributs à une table\npour la transformer en chambre.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _rooms.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _RoomCard(
                    room: _rooms[i],
                    tasks: _tasksByRoom[_rooms[i].id] ?? [],
                    guestName: _guestName(_rooms[i].id),
                    stayDates: _stayDates(_rooms[i].id),
                    onToggle: _toggleTask,
                    onDelete: _deleteTask,
                    onAddTask: () => _showAddTaskDialog(_rooms[i]),
                  ),
                ),
    );
  }
}

// ── Room card ─────────────────────────────────────────────────────────────────

class _RoomCard extends StatelessWidget {
  final RestaurantTableModel room;
  final List<HousekeepingTaskModel> tasks;
  final String? guestName;
  final String? stayDates;
  final Future<void> Function(HousekeepingTaskModel) onToggle;
  final Future<void> Function(HousekeepingTaskModel) onDelete;
  final VoidCallback onAddTask;

  const _RoomCard({
    required this.room,
    required this.tasks,
    this.guestName,
    this.stayDates,
    required this.onToggle,
    required this.onDelete,
    required this.onAddTask,
  });

  @override
  Widget build(BuildContext context) {
    final isOccupied = room.isOccupied;
    final pending = tasks.where((t) => !t.isDone).length;

    final statusColor = isOccupied ? AppColors.warning : AppColors.success;
    final statusLabel = isOccupied ? 'Occupée' : 'Libre';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.king_bed_rounded,
                      color: statusColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(room.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(statusLabel,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: statusColor)),
                          ),
                        ],
                      ),
                      if (guestName != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '${Icons.person_outline_rounded}  $guestName${stayDates != null ? ' · $stayDates' : ''}',
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (guestName != null && stayDates != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Row(
                            children: [
                              const Icon(Icons.person_outline_rounded,
                                  size: 12, color: AppColors.textSecondary),
                              const SizedBox(width: 3),
                              Text(guestName!,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary)),
                              const SizedBox(width: 6),
                              const Icon(Icons.calendar_today_rounded,
                                  size: 11, color: AppColors.textSecondary),
                              const SizedBox(width: 3),
                              Text(stayDates!,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (pending > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('$pending en attente',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.error)),
                  ),
              ],
            ),
          ),

          // Attributes chips
          if (room.attributes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: room.attributes.map((a) => Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${a.key}: ${a.value}',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.primary)),
                )).toList(),
              ),
            ),

          const Divider(height: 1),

          // Tasks list
          if (tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              child: Row(
                children: const [
                  Icon(Icons.check_circle_outline_rounded,
                      size: 16, color: AppColors.textSecondary),
                  SizedBox(width: 6),
                  Text('Aucune tâche en attente',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            )
          else
            Column(
              children: tasks.map((task) => _TaskRow(
                task: task,
                onToggle: () => onToggle(task),
                onDelete: () => onDelete(task),
              )).toList(),
            ),

          // Add task button
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            child: TextButton.icon(
              onPressed: onAddTask,
              icon: const Icon(Icons.add_task_rounded, size: 16),
              label: const Text('Ajouter une tâche'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Task row ──────────────────────────────────────────────────────────────────

class _TaskRow extends StatelessWidget {
  final HousekeepingTaskModel task;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _TaskRow({
    required this.task,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDone = task.isDone;
    return InkWell(
      onTap: isDone ? null : onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(
              isDone
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: isDone ? AppColors.success : AppColors.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                task.description,
                style: TextStyle(
                  fontSize: 14,
                  color: isDone
                      ? AppColors.textSecondary
                      : AppColors.textPrimary,
                  decoration:
                      isDone ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded,
                  size: 16, color: AppColors.textSecondary),
              onPressed: onDelete,
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ],
        ),
      ),
    );
  }
}
