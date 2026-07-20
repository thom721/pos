import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart' show dio, extractAnyError;
import 'package:pos_connect/data/models/restaurant_model.dart';
import 'package:pos_connect/data/repositories/auth_repository.dart';
import 'package:pos_connect/data/repositories/restaurant_repository.dart';
import 'package:pos_connect/data/repositories/warehouse_repository.dart';
import 'package:pos_connect/providers/restaurant_provider.dart';
import 'package:pos_connect/data/models/warehouse_model.dart';
import 'package:pos_connect/providers/settings_provider.dart';
import 'package:pos_connect/providers/warehouse_provider.dart';
import 'package:pos_connect/shared/widgets/open_session_dialog.dart';

class CommandesScreen extends ConsumerStatefulWidget {
  final String? autoTableId;
  const CommandesScreen({super.key, this.autoTableId});

  @override
  ConsumerState<CommandesScreen> createState() => _CommandesScreenState();
}

class _CommandesScreenState extends ConsumerState<CommandesScreen> {
  String? _deviceId;
  bool _sessionChecked = false;
  bool _hasSession = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initSession());
  }

  Future<void> _initSession() async {
    if (_sessionChecked) return;
    _deviceId ??= await AuthRepository().getOrCreateDeviceId();

    // Warehouse pas encore chargé → essayer depuis l'API (1ère installation ou
    // cache vide) ; si toujours null, le ref.listen() ré-essayera plus tard.
    var wh = ref.read(activeWarehouseProvider);
    if (wh == null) {
      try {
        final list = await WarehouseRepository().listWarehouses();
        await ref.read(activeWarehouseProvider.notifier).initFromList(list);
        wh = ref.read(activeWarehouseProvider);
      } catch (_) {}
      if (wh == null) return;
    }

    try {
      final res = await dio.get('/api/sessions/current', queryParameters: {
        'device_id': _deviceId,
        'warehouse_id': wh.id,
      });
      final session = res.data['session'];
      if (!mounted) return;
      if (session != null) {
        setState(() { _sessionChecked = true; _hasSession = true; });
        if (widget.autoTableId != null) {
          _showNewOrderDialog(context, preselectedTableId: widget.autoTableId);
        }
      } else {
        setState(() { _sessionChecked = true; _hasSession = false; });
        _promptOpenSession(wh);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() { _sessionChecked = true; _hasSession = false; });
      _promptOpenSession(wh);
    }
  }

  void _promptOpenSession([WarehouseModel? wh]) {
    wh ??= ref.read(activeWarehouseProvider);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => OpenSessionDialog(
        deviceId: _deviceId!,
        warehouseId: wh?.id,
        warehouseName: wh?.name,
        onOpened: (_) {
          if (mounted) setState(() => _hasSession = true);
          if (widget.autoTableId != null) {
            _showNewOrderDialog(context, preselectedTableId: widget.autoTableId);
          }
        },
        onCancelled: () {
          if (mounted && context.canPop()) context.pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<WarehouseModel?>(activeWarehouseProvider, (_, next) {
      if (next?.id != null && !_sessionChecked && mounted) {
        _initSession();
      }
    });

    if (!_sessionChecked) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasSession) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_clock_rounded, size: 64, color: AppColors.textSecondary),
              const SizedBox(height: 16),
              const Text('Session de caisse requise',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              const Text('Ouvrez une session pour accéder aux commandes.',
                  style: TextStyle(color: AppColors.textSecondary),
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _promptOpenSession,
                icon: const Icon(Icons.point_of_sale_rounded),
                label: const Text('Ouvrir la caisse'),
              ),
            ],
          ),
        ),
      );
    }

    final ordersAsync = ref.watch(openOrdersProvider);
    final symbol = ref.watch(settingsProvider).currencySymbol;
    final fmt = NumberFormat('#,##0.00');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('Commandes',
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        actions: [
          IconButton(
            icon: const Icon(Icons.table_restaurant_rounded, color: AppColors.textSecondary),
            tooltip: 'Plan de salle',
            onPressed: () => context.push('/restaurant/tables'),
          ),
          IconButton(
            icon: const Icon(Icons.restaurant_rounded, color: AppColors.textSecondary),
            tooltip: 'Vue cuisine',
            onPressed: () => context.push('/restaurant/kitchen'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
            onPressed: () => ref.invalidate(openOrdersProvider),
          ),
        ],
      ),
      body: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 40),
              const SizedBox(height: 12),
              Text(extractAnyError(e),
                  style: const TextStyle(color: AppColors.error), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(openOrdersProvider),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
        data: (orders) => orders.isEmpty
            ? _EmptyState(onNew: () => _showNewOrderDialog(context))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: orders.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _OrderCard(
                  order: orders[i],
                  symbol: symbol,
                  fmt: fmt,
                  onTap: () => context.push('/restaurant/commande/${orders[i].id}'),
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNewOrderDialog(context),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nouvelle commande'),
      ),
    );
  }

  Future<void> _showNewOrderDialog(BuildContext context,
      {String? preselectedTableId}) async {
    List<RestaurantTableModel> tables = [];
    List<RestaurantWaiterModel> waiters = [];
    try {
      final results = await Future.wait([
        RestaurantRepository().getTables(),
        RestaurantRepository().getWaiters(),
      ]);
      tables = results[0] as List<RestaurantTableModel>;
      waiters = results[1] as List<RestaurantWaiterModel>;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(extractAnyError(e)),
          backgroundColor: AppColors.error,
        ));
      }
      return;
    }
    if (!context.mounted) return;

    String? selectedTableId = preselectedTableId;
    String? selectedWaiterId;
    int covers = 2;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 380, maxWidth: 500),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Nouvelle commande',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 20),
                  // Table picker
                  DropdownButtonFormField<String?>(
                    initialValue: selectedTableId,
                    decoration: const InputDecoration(
                      labelText: 'Table (optionnel)',
                      hintText: 'Comptoir / Bar',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.table_restaurant_rounded),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Comptoir / Bar'),
                      ),
                      ...tables
                          .where((t) => t.isFree || t.id == selectedTableId)
                          .map((t) => DropdownMenuItem(
                                value: t.id,
                                child: Text('${t.name}  (${t.capacity} pers.)'),
                              )),
                    ],
                    onChanged: (v) => setDlgState(() => selectedTableId = v),
                  ),
                  const SizedBox(height: 16),
                  // Waiter picker
                  DropdownButtonFormField<String?>(
                    initialValue: selectedWaiterId,
                    decoration: const InputDecoration(
                      labelText: 'Serveur (optionnel)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Non assigné')),
                      ...waiters.map((w) => DropdownMenuItem(
                            value: w.id,
                            child: Text(w.name.isNotEmpty ? w.name : w.username),
                          )),
                    ],
                    onChanged: (v) => setDlgState(() => selectedWaiterId = v),
                  ),
                  const SizedBox(height: 16),
                  // Covers stepper
                  Row(
                    children: [
                      const Icon(Icons.people_outline_rounded,
                          color: AppColors.textSecondary, size: 20),
                      const SizedBox(width: 8),
                      const Text('Couverts :', style: TextStyle(fontSize: 15)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                        color: AppColors.primary,
                        onPressed: () =>
                            setDlgState(() { if (covers > 1) covers--; }),
                      ),
                      SizedBox(
                        width: 36,
                        child: Text('$covers',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 18)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline_rounded),
                        color: AppColors.primary,
                        onPressed: () => setDlgState(() => covers++),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Annuler'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () => Navigator.pop(ctx, true),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Créer'),
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
    if (result != true || !context.mounted) return;

    try {
      // Assign waiter to table first (if both selected)
      if (selectedTableId != null && selectedWaiterId != null) {
        await RestaurantRepository()
            .assignWaiter(selectedTableId!, selectedWaiterId);
      }
      final order = await RestaurantRepository().openOrder(
        tableId: selectedTableId,
        covers: covers,
      );
      ref.invalidate(openOrdersProvider);
      ref.invalidate(tablesProvider);
      if (context.mounted) {
        context.push('/restaurant/commande/${order.id}');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(extractAnyError(e)),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }
}

// ── Order card ────────────────────────────────────────────────────────────────

class _OrderCard extends StatelessWidget {
  final RestaurantOrderModel order;
  final String symbol;
  final NumberFormat fmt;
  final VoidCallback onTap;

  const _OrderCard({
    required this.order,
    required this.symbol,
    required this.fmt,
    required this.onTap,
  });

  Color get _statusColor {
    if (order.isReady) return AppColors.success;
    if (order.sentToKitchen) return AppColors.warning;
    return AppColors.primary;
  }

  String get _statusLabel {
    if (order.isReady) return 'Prête';
    if (order.sentToKitchen) return 'En cuisine';
    return 'Ouverte';
  }

  String get _timeLabel {
    if (order.createdAt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(order.createdAt!);
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
    return DateFormat('HH:mm').format(order.createdAt!);
  }

  @override
  Widget build(BuildContext context) {
    final tableLabel = order.hasTable ? (order.tableName ?? 'Table') : 'Comptoir / Bar';

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              // Icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  order.hasTable
                      ? Icons.table_restaurant_rounded
                      : Icons.countertops_rounded,
                  color: _statusColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(tableLabel,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(_statusLabel,
                              style: TextStyle(
                                  color: _statusColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.people_outline_rounded,
                            size: 13, color: AppColors.textSecondary),
                        const SizedBox(width: 3),
                        Text('${order.covers} couvert${order.covers > 1 ? 's' : ''}',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary)),
                        if (order.waiterName != null) ...[
                          const SizedBox(width: 10),
                          Icon(Icons.person_outline_rounded,
                              size: 13, color: AppColors.textSecondary),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(order.waiterName!,
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.textSecondary),
                                overflow: TextOverflow.ellipsis),
                          ),
                        ] else
                          const Spacer(),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '${order.items.length} article${order.items.length > 1 ? 's' : ''}',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                        const Spacer(),
                        Text(
                          '$symbol${fmt.format(order.total)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: AppColors.primary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_timeLabel,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textSecondary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onNew;
  const _EmptyState({required this.onNew});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.receipt_long_rounded, size: 72, color: AppColors.divider),
          const SizedBox(height: 16),
          const Text('Aucune commande ouverte',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          const Text('Démarrez une commande pour une table ou au comptoir',
              style: TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onNew,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Nouvelle commande'),
          ),
        ],
      ),
    );
  }
}
