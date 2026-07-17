import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pos_connect/core/permissions.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/warehouse_model.dart';
import 'package:pos_connect/data/repositories/warehouse_repository.dart';
import 'package:pos_connect/providers/auth_provider.dart';
import 'package:pos_connect/providers/settings_provider.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  Période
// ══════════════════════════════════════════════════════════════════════════════

enum _Period { today, week, month, lastMonth, custom }

extension _PeriodLabel on _Period {
  String get label => switch (this) {
        _Period.today     => "Auj.",
        _Period.week      => 'Semaine',
        _Period.month     => 'Mois',
        _Period.lastMonth => 'Mois préc.',
        _Period.custom    => 'Perso.',
      };

  (DateTime, DateTime) range([DateTimeRange? custom]) {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (this) {
      case _Period.today:
        return (today, today.add(const Duration(days: 1)));
      case _Period.week:
        final start = today.subtract(Duration(days: today.weekday - 1));
        return (start, today.add(const Duration(days: 1)));
      case _Period.month:
        return (DateTime(now.year, now.month, 1), today.add(const Duration(days: 1)));
      case _Period.lastMonth:
        final first = DateTime(now.year, now.month - 1, 1);
        return (first, DateTime(now.year, now.month, 1));
      case _Period.custom:
        if (custom != null) return (custom.start, custom.end.add(const Duration(days: 1)));
        return (today, today.add(const Duration(days: 1)));
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Modèles de données
// ══════════════════════════════════════════════════════════════════════════════

class _WarehouseStat {
  final String id;
  final String name;
  final bool isDefault;
  final bool isActive;
  final double revenue;
  final double profit;
  final double margin;
  final int sales;
  final double items;
  final int rank;

  const _WarehouseStat({
    required this.id, required this.name, required this.isDefault,
    required this.isActive, required this.revenue, required this.profit,
    required this.margin, required this.sales, required this.items,
    required this.rank,
  });

  factory _WarehouseStat.fromJson(Map<String, dynamic> j) => _WarehouseStat(
    id:        j['warehouse_id']?.toString() ?? '',
    name:      j['warehouse_name']?.toString() ?? '',
    isDefault: j['is_default'] as bool? ?? false,
    isActive:  j['is_active']  as bool? ?? true,
    revenue:   (j['total_revenue'] as num?)?.toDouble() ?? 0,
    profit:    (j['total_profit']  as num?)?.toDouble() ?? 0,
    margin:    (j['profit_margin'] as num?)?.toDouble() ?? 0,
    sales:     (j['total_sales']   as num?)?.toInt()    ?? 0,
    items:     (j['total_items_sold'] as num?)?.toDouble() ?? 0,
    rank:      (j['rank'] as num?)?.toInt() ?? 0,
  );
}

class _GlobalStat {
  final double revenue, profit, margin, items;
  final int sales;

  const _GlobalStat({
    required this.revenue, required this.profit, required this.margin,
    required this.sales, required this.items,
  });

  factory _GlobalStat.fromJson(Map<String, dynamic> j) => _GlobalStat(
    revenue: (j['total_revenue']    as num?)?.toDouble() ?? 0,
    profit:  (j['total_profit']     as num?)?.toDouble() ?? 0,
    margin:  (j['profit_margin']    as num?)?.toDouble() ?? 0,
    sales:   (j['total_sales']      as num?)?.toInt()    ?? 0,
    items:   (j['total_items_sold'] as num?)?.toDouble() ?? 0,
  );
}

class _ProductStat {
  final String id, name;
  final double qty, revenue, profit, margin;

  const _ProductStat({
    required this.id, required this.name, required this.qty,
    required this.revenue, required this.profit, required this.margin,
  });

  factory _ProductStat.fromJson(Map<String, dynamic> j) => _ProductStat(
    id:      j['product_id']?.toString()   ?? '',
    name:    j['product_name']?.toString() ?? '',
    qty:     (j['total_quantity'] as num?)?.toDouble() ?? 0,
    revenue: (j['total_revenue']  as num?)?.toDouble() ?? 0,
    profit:  (j['total_profit']   as num?)?.toDouble() ?? 0,
    margin:  (j['profit_margin']  as num?)?.toDouble() ?? 0,
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  Providers
// ══════════════════════════════════════════════════════════════════════════════

class _ReportParams {
  final DateTime from;
  final DateTime to;

  const _ReportParams(this.from, this.to);

  @override
  bool operator ==(Object other) =>
      other is _ReportParams && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

class _ProductParams {
  final DateTime from;
  final DateTime to;
  final String? warehouseId;

  const _ProductParams(this.from, this.to, this.warehouseId);

  @override
  bool operator ==(Object other) =>
      other is _ProductParams &&
      other.from == from && other.to == to &&
      other.warehouseId == warehouseId;

  @override
  int get hashCode => Object.hash(from, to, warehouseId);
}

final _warehouseStatsProvider = FutureProvider.autoDispose
    .family<({_GlobalStat global, List<_WarehouseStat> byWarehouse}), _ReportParams>(
  (ref, params) async {
    final res = await dio.get('/api/reports/warehouses', queryParameters: {
      'date_from': params.from.toIso8601String(),
      'date_to':   params.to.toIso8601String(),
    });
    final data = res.data as Map<String, dynamic>;
    return (
      global: _GlobalStat.fromJson(data['global'] as Map<String, dynamic>),
      byWarehouse: (data['by_warehouse'] as List)
          .map((e) => _WarehouseStat.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  },
);

final _topProductsProvider = FutureProvider.autoDispose
    .family<List<_ProductStat>, _ProductParams>((ref, params) async {
  final res = await dio.get('/api/reports/top-products', queryParameters: {
    'date_from': params.from.toIso8601String(),
    'date_to':   params.to.toIso8601String(),
    'limit':     20,
    if (params.warehouseId != null) 'warehouse_id': params.warehouseId,
  });
  return (res.data as List)
      .map((e) => _ProductStat.fromJson(e as Map<String, dynamic>))
      .toList();
});

final _warehouseListProvider =
    FutureProvider.autoDispose<List<WarehouseModel>>((ref) async {
  return WarehouseRepository().listWarehouses();
});

// ══════════════════════════════════════════════════════════════════════════════
//  Écran principal
// ══════════════════════════════════════════════════════════════════════════════

class DepotReportsScreen extends ConsumerStatefulWidget {
  const DepotReportsScreen({super.key});

  @override
  ConsumerState<DepotReportsScreen> createState() =>
      _DepotReportsScreenState();
}

class _DepotReportsScreenState extends ConsumerState<DepotReportsScreen> {
  _Period _period = _Period.month;
  DateTimeRange? _customRange;
  String? _productWarehouseFilter; // null = Tous

  (DateTime, DateTime) get _range => _period.range(_customRange);

  _ReportParams get _reportParams =>
      _ReportParams(_range.$1, _range.$2);

  _ProductParams get _productParams =>
      _ProductParams(_range.$1, _range.$2, _productWarehouseFilter);

  @override
  Widget build(BuildContext context) {
    final settings       = ref.watch(settingsProvider);
    final user           = ref.watch(authProvider).user;
    final canRead        = user?.hasPermission(Perm.salesRead) ?? false;
    final warehousesAsync = ref.watch(_warehouseListProvider);

    final fmt = NumberFormat.currency(
      locale: 'fr_HT',
      symbol: settings.currencySymbol,
      decimalDigits: 0,
    );

    if (!canRead) {
      return const Scaffold(
        body: Center(child: Text('Accès non autorisé')),
      );
    }

    final statsAsync    = ref.watch(_warehouseStatsProvider(_reportParams));
    final productsAsync = ref.watch(_topProductsProvider(_productParams));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── En-tête ────────────────────────────────────────────────────
            Row(
              children: [
                const Text(
                  'Rapports par dépôt',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Actualiser',
                  icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
                  onPressed: () {
                    ref.invalidate(_warehouseStatsProvider);
                    ref.invalidate(_topProductsProvider);
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Comparez la rentabilité de chaque dépôt et les produits les plus écoulés.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),

            // ── Sélecteur période ──────────────────────────────────────────
            _PeriodSelector(
              selected: _period,
              customRange: _customRange,
              onPeriodChanged: (p) => setState(() => _period = p),
              onCustomRangeChanged: (r) => setState(() {
                _customRange = r;
                _period = _Period.custom;
              }),
            ),
            const SizedBox(height: 24),

            // ── Résumé global ──────────────────────────────────────────────
            statsAsync.when(
              loading: () => const _LoadingSection(label: 'Chargement des stats…'),
              error:   (e, _) => _ErrorSection(error: e, onRetry: () => ref.invalidate(_warehouseStatsProvider)),
              data: (data) => _GlobalSummary(global: data.global, fmt: fmt),
            ),
            const SizedBox(height: 24),

            // ── Classement dépôts ──────────────────────────────────────────
            _SectionTitle(
              icon: Icons.leaderboard_rounded,
              title: 'Classement des dépôts',
              subtitle: 'Par chiffre d\'affaires sur la période',
            ),
            const SizedBox(height: 12),
            statsAsync.when(
              loading: () => const _LoadingSection(label: 'Chargement…'),
              error:   (e, _) => _ErrorSection(error: e, onRetry: () => ref.invalidate(_warehouseStatsProvider)),
              data: (data) => data.byWarehouse.isEmpty
                  ? _emptyState('Aucune vente enregistrée pour cette période')
                  : _WarehouseRanking(stats: data.byWarehouse, fmt: fmt),
            ),
            const SizedBox(height: 32),

            // ── Top produits ───────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _SectionTitle(
                    icon: Icons.inventory_2_rounded,
                    title: 'Stock écoulé — Top produits',
                    subtitle: 'Produits les plus vendus sur la période',
                  ),
                ),
                const SizedBox(width: 12),
                // Filtre dépôt pour les produits
                warehousesAsync.maybeWhen(
                  data: (warehouses) => _WarehouseFilterDropdown(
                    warehouses: warehouses,
                    selected: _productWarehouseFilter,
                    onChanged: (v) => setState(() => _productWarehouseFilter = v),
                  ),
                  orElse: () => const SizedBox.shrink(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            productsAsync.when(
              loading: () => const _LoadingSection(label: 'Chargement des produits…'),
              error:   (e, _) => _ErrorSection(error: e, onRetry: () => ref.invalidate(_topProductsProvider)),
              data: (products) => products.isEmpty
                  ? _emptyState('Aucun produit vendu sur cette période')
                  : _TopProductsTable(products: products, fmt: fmt),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(String msg) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Center(
      child: Text(msg,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  Sélecteur de période
// ══════════════════════════════════════════════════════════════════════════════

class _PeriodSelector extends StatelessWidget {
  final _Period selected;
  final DateTimeRange? customRange;
  final ValueChanged<_Period> onPeriodChanged;
  final ValueChanged<DateTimeRange> onCustomRangeChanged;

  const _PeriodSelector({
    required this.selected,
    required this.customRange,
    required this.onPeriodChanged,
    required this.onCustomRangeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: _Period.values.map((p) {
        final active = p == selected;
        return ChoiceChip(
          label: Text(p.label),
          selected: active,
          onSelected: (_) async {
            if (p == _Period.custom) {
              final now = DateTime.now();
              final result = await showDateRangePicker(
                context: context,
                firstDate: DateTime(now.year - 3),
                lastDate: now,
                initialDateRange: customRange ??
                    DateTimeRange(
                      start: DateTime(now.year, now.month, 1),
                      end: now,
                    ),
                locale: const Locale('fr'),
              );
              if (result != null) onCustomRangeChanged(result);
            } else {
              onPeriodChanged(p);
            }
          },
        );
      }).toList(),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Résumé global
// ══════════════════════════════════════════════════════════════════════════════

class _GlobalSummary extends StatelessWidget {
  final _GlobalStat global;
  final NumberFormat fmt;

  const _GlobalSummary({required this.global, required this.fmt});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          icon: Icons.bar_chart_rounded,
          title: 'Résumé global',
          subtitle: 'Tous dépôts confondus',
        ),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (_, constraints) {
          final cols = constraints.maxWidth > 700 ? 4 : 2;
          return GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: cols == 4 ? 2.2 : 2.0,
            children: [
              _KpiCard(
                label: 'Chiffre d\'affaires',
                value: fmt.format(global.revenue),
                icon: Icons.attach_money_rounded,
                color: AppColors.primary,
              ),
              _KpiCard(
                label: 'Marge brute',
                value:
                    '${fmt.format(global.profit)}  (${global.margin.toStringAsFixed(1)} %)',
                icon: Icons.trending_up_rounded,
                color: AppColors.success,
              ),
              _KpiCard(
                label: 'Ventes',
                value: '${global.sales}',
                icon: Icons.receipt_long_rounded,
                color: AppColors.info,
              ),
              _KpiCard(
                label: 'Articles écoulés',
                value: _formatQty(global.items),
                icon: Icons.inventory_rounded,
                color: AppColors.accent,
              ),
            ],
          );
        }),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Classement dépôts
// ══════════════════════════════════════════════════════════════════════════════

class _WarehouseRanking extends StatelessWidget {
  final List<_WarehouseStat> stats;
  final NumberFormat fmt;

  const _WarehouseRanking({required this.stats, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final best = stats.isNotEmpty ? stats.first.revenue : 1.0;

    return Card(
      elevation: 0,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: Column(
        children: [
          // Table header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                _th('#', flex: 1),
                _th('Dépôt', flex: 5),
                _th('CA', flex: 4, right: true),
                _th('Marge', flex: 3, right: true),
                _th('Ventes', flex: 2, right: true),
                _th('Articles', flex: 2, right: true),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          // Rows
          ...stats.asMap().entries.map((entry) {
            final i    = entry.key;
            final stat = entry.value;
            final pct  = best > 0 ? stat.revenue / best : 0.0;
            return _WarehouseRow(
              stat: stat,
              fmt: fmt,
              barPct: pct,
              isLast: i == stats.length - 1,
            );
          }),
        ],
      ),
    );
  }

  Widget _th(String text, {int flex = 1, bool right = false}) => Expanded(
    flex: flex,
    child: Text(
      text,
      textAlign: right ? TextAlign.right : TextAlign.left,
      style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary),
    ),
  );
}

class _WarehouseRow extends StatelessWidget {
  final _WarehouseStat stat;
  final NumberFormat fmt;
  final double barPct;
  final bool isLast;

  const _WarehouseRow({
    required this.stat, required this.fmt,
    required this.barPct, required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final rankColor = stat.rank == 1
        ? const Color(0xFFF59E0B)
        : stat.rank == 2
            ? AppColors.textSecondary
            : stat.rank == 3
                ? const Color(0xFFCD7F32)
                : AppColors.textSecondary.withValues(alpha: 0.5);

    return Container(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: AppColors.divider, width: 0.5)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                // Rank
                Expanded(
                  flex: 1,
                  child: Text(
                    '${stat.rank}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: rankColor),
                  ),
                ),
                // Name + badges
                Expanded(
                  flex: 5,
                  child: Wrap(
                    spacing: 5,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(stat.name,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary)),
                      if (stat.isDefault)
                        _MiniChip('Défaut', AppColors.primary),
                      if (!stat.isActive)
                        _MiniChip('Inactif', AppColors.textSecondary),
                    ],
                  ),
                ),
                // CA
                Expanded(
                  flex: 4,
                  child: Text(
                    fmt.format(stat.revenue),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary),
                  ),
                ),
                // Marge %
                Expanded(
                  flex: 3,
                  child: Text(
                    '${stat.margin.toStringAsFixed(1)} %',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 13,
                        color: stat.margin > 0
                            ? AppColors.success
                            : AppColors.textSecondary),
                  ),
                ),
                // Ventes
                Expanded(
                  flex: 2,
                  child: Text(
                    '${stat.sales}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
                ),
                // Articles
                Expanded(
                  flex: 2,
                  child: Text(
                    _formatQty(stat.items),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          // Barre de progression CA
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: barPct,
                minHeight: 4,
                backgroundColor:
                    AppColors.primary.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(
                  stat.rank == 1 ? AppColors.primary : AppColors.info,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Top produits
// ══════════════════════════════════════════════════════════════════════════════

class _TopProductsTable extends StatelessWidget {
  final List<_ProductStat> products;
  final NumberFormat fmt;

  const _TopProductsTable({required this.products, required this.fmt});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              _th('#', flex: 1),
              _th('Produit', flex: 5),
              _th('Qté vendue', flex: 2, right: true),
              _th('CA', flex: 3, right: true),
              _th('Marge', flex: 2, right: true),
            ]),
          ),
          const Divider(height: 1, color: AppColors.divider),
          ...products.asMap().entries.map((e) {
            final i = e.key;
            final p = e.value;
            return Container(
              decoration: BoxDecoration(
                border: i < products.length - 1
                    ? const Border(
                        bottom: BorderSide(
                            color: AppColors.divider, width: 0.5))
                    : null,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 11),
                child: Row(children: [
                  Expanded(
                    flex: 1,
                    child: Text('${i + 1}',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary)),
                  ),
                  Expanded(
                    flex: 5,
                    child: Text(p.name,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary),
                        overflow: TextOverflow.ellipsis),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(_formatQty(p.qty),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textPrimary)),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(fmt.format(p.revenue),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '${p.margin.toStringAsFixed(1)} %',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 13,
                          color: p.margin > 0
                              ? AppColors.success
                              : AppColors.textSecondary),
                    ),
                  ),
                ]),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _th(String text, {int flex = 1, bool right = false}) => Expanded(
    flex: flex,
    child: Text(
      text,
      textAlign: right ? TextAlign.right : TextAlign.left,
      style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  Filtre dépôt pour les produits
// ══════════════════════════════════════════════════════════════════════════════

class _WarehouseFilterDropdown extends StatelessWidget {
  final List<WarehouseModel> warehouses;
  final String? selected;
  final ValueChanged<String?> onChanged;

  const _WarehouseFilterDropdown({
    required this.warehouses,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String?>(
      value: selected,
      underline: const SizedBox(),
      hint: const Text('Tous les dépôts',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('Tous les dépôts',
              style: TextStyle(fontSize: 13)),
        ),
        ...warehouses.map((wh) => DropdownMenuItem<String?>(
          value: wh.id,
          child: Text(wh.name, style: const TextStyle(fontSize: 13)),
        )),
      ],
      onChanged: onChanged,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Widgets helpers
// ══════════════════════════════════════════════════════════════════════════════

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionTitle({
    required this.icon, required this.title, required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            Text(subtitle,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.label, required this.value,
    required this.icon, required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
            ]),
            Text(value,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: color),
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String label;
  final Color color;

  const _MiniChip(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(label,
        style: TextStyle(
            fontSize: 10, color: color, fontWeight: FontWeight.w600)),
  );
}

class _LoadingSection extends StatelessWidget {
  final String label;
  const _LoadingSection({required this.label});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
        ],
      ),
    ),
  );
}

class _ErrorSection extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const _ErrorSection({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 36),
          const SizedBox(height: 8),
          Text('$error',
              style: const TextStyle(fontSize: 12, color: AppColors.error)),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('Réessayer')),
        ],
      ),
    ),
  );
}

// ── Utility ───────────────────────────────────────────────────────────────────

String _formatQty(double qty) {
  if (qty == qty.truncateToDouble()) {
    return qty.toInt().toString();
  }
  return qty.toStringAsFixed(2);
}
