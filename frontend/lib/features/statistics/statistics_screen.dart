import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pos_connect/core/date_utils.dart' show haitiNow;
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/sale_model.dart';
import 'package:pos_connect/providers/settings_provider.dart';

// ── Period enum ────────────────────────────────────────────────────────────

enum _RevPeriod { week, month, year, custom }

extension _RevPeriodLabel on _RevPeriod {
  String get label {
    switch (this) {
      case _RevPeriod.week:   return 'Semaine';
      case _RevPeriod.month:  return 'Mois';
      case _RevPeriod.year:   return 'Année';
      case _RevPeriod.custom: return 'Personnalisé';
    }
  }
}

// ── Provider params (period + optional custom range) ───────────────────────

class _RevParams {
  final _RevPeriod period;
  final DateTimeRange? customRange;
  const _RevParams(this.period, [this.customRange]);

  @override
  bool operator ==(Object other) =>
      other is _RevParams &&
      other.period == period &&
      other.customRange?.start == customRange?.start &&
      other.customRange?.end == customRange?.end;

  @override
  int get hashCode =>
      Object.hash(period, customRange?.start, customRange?.end);
}

// ── Chart data point ───────────────────────────────────────────────────────

class _ChartPoint {
  final String label;
  final String tooltipLabel;
  final double value;
  const _ChartPoint(
      {required this.label,
      required this.tooltipLabel,
      required this.value});
}

// ── Shared paginated fetch ─────────────────────────────────────────────────

Future<List<SaleModel>> _fetchAllSales(DateTime from, DateTime to) async {
  final dateFmt = DateFormat('yyyy-MM-dd');
  const limit = 100;
  final base = {
    'limit': limit,
    'date_from': dateFmt.format(from),
    'date_to': dateFmt.format(to),
  };

  final first =
      await dio.get('/api/sales/', queryParameters: {...base, 'page': 1});
  final meta = first.data['meta'] as Map<String, dynamic>? ?? {};
  final pages = (meta['pages'] as num?)?.toInt() ?? 1;

  final all = <SaleModel>[
    ...(first.data['data'] as List? ?? [])
        .map((e) => SaleModel.fromJson(e as Map<String, dynamic>)),
  ];

  if (pages > 1) {
    final futures = List.generate(
      pages - 1,
      (i) => dio.get('/api/sales/',
          queryParameters: {...base, 'page': i + 2}),
    );
    for (final res in await Future.wait(futures)) {
      all.addAll((res.data['data'] as List? ?? [])
          .map((e) => SaleModel.fromJson(e as Map<String, dynamic>)));
    }
  }

  return all;
}

// ── Providers ──────────────────────────────────────────────────────────────

final _revPeriodProvider =
    StateProvider<_RevPeriod>((ref) => _RevPeriod.month);

final _customRangeProvider = StateProvider<DateTimeRange?>((ref) => null);

/// KPI + top products + payment methods — always current month.
final _statsProvider = FutureProvider.autoDispose<_StatsData>((ref) async {
  final now = haitiNow();
  final from = DateTime(now.year, now.month, 1);
  final sales = await _fetchAllSales(from, now.add(const Duration(days: 1)));
  return _StatsData.from(sales);
});

/// Revenue chart — depends on period and optional custom range.
final _revenueChartProvider = FutureProvider.family
    .autoDispose<List<_ChartPoint>, _RevParams>((ref, params) async {
  final now = haitiNow();

  final DateTime from;
  final DateTime to = now.add(const Duration(days: 1));

  switch (params.period) {
    case _RevPeriod.week:
      from = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 6));
    case _RevPeriod.month:
      from = DateTime(now.year, now.month, 1);
    case _RevPeriod.year:
      from = DateTime(now.year, 1, 1);
    case _RevPeriod.custom:
      if (params.customRange == null) return [];
      from = params.customRange!.start;
  }

  final toDate = params.period == _RevPeriod.custom && params.customRange != null
      ? params.customRange!.end.add(const Duration(days: 1))
      : to;

  final sales = await _fetchAllSales(from, toDate);

  switch (params.period) {
    case _RevPeriod.week:
      final shortFmt = DateFormat('dd/MM');
      final dayFmt  = DateFormat('EEE', 'fr');
      return List.generate(7, (i) {
        final day      = now.subtract(Duration(days: 6 - i));
        final dayStart = DateTime(day.year, day.month, day.day);
        final dayEnd   = dayStart.add(const Duration(days: 1));
        final rev = sales
            .where((s) => !s.createdAt.isBefore(dayStart) && s.createdAt.isBefore(dayEnd))
            .fold(0.0, (s, e) => s + e.finalAmount);
        return _ChartPoint(
            label: dayFmt.format(day),
            tooltipLabel: shortFmt.format(day),
            value: rev);
      });

    case _RevPeriod.month:
      final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
      final points = <_ChartPoint>[];
      for (var d = 1; d <= daysInMonth; d++) {
        final dayStart = DateTime(now.year, now.month, d);
        if (dayStart.isAfter(now)) break;
        final dayEnd = dayStart.add(const Duration(days: 1));
        final rev = sales
            .where((s) => !s.createdAt.isBefore(dayStart) && s.createdAt.isBefore(dayEnd))
            .fold(0.0, (s, e) => s + e.finalAmount);
        points.add(_ChartPoint(
            label: '$d',
            tooltipLabel: DateFormat('dd/MM').format(dayStart),
            value: rev));
      }
      return points;

    case _RevPeriod.year:
      final monthFmt = DateFormat('MMM', 'fr');
      final points = <_ChartPoint>[];
      for (var m = 1; m <= 12; m++) {
        final monthStart = DateTime(now.year, m, 1);
        if (monthStart.isAfter(now)) break;
        final monthEnd = DateTime(now.year, m + 1, 1);
        final rev = sales
            .where((s) => !s.createdAt.isBefore(monthStart) && s.createdAt.isBefore(monthEnd))
            .fold(0.0, (s, e) => s + e.finalAmount);
        points.add(_ChartPoint(
            label: monthFmt.format(monthStart),
            tooltipLabel: DateFormat('MMMM yyyy', 'fr').format(monthStart),
            value: rev));
      }
      return points;

    case _RevPeriod.custom:
      final range = params.customRange!;
      final diff  = range.end.difference(range.start).inDays;
      final points = <_ChartPoint>[];

      if (diff <= 62) {
        // Group by day
        final dayFmt = DateFormat('dd/MM');
        for (var d = 0; d <= diff; d++) {
          final dayStart = DateTime(
              range.start.year, range.start.month, range.start.day)
              .add(Duration(days: d));
          final dayEnd = dayStart.add(const Duration(days: 1));
          final rev = sales
              .where((s) => !s.createdAt.isBefore(dayStart) && s.createdAt.isBefore(dayEnd))
              .fold(0.0, (s, e) => s + e.finalAmount);
          points.add(_ChartPoint(
              label: dayFmt.format(dayStart),
              tooltipLabel: DateFormat('dd/MM/yyyy').format(dayStart),
              value: rev));
        }
      } else {
        // Group by month
        final monthFmt = DateFormat('MMM yy', 'fr');
        var cursor = DateTime(range.start.year, range.start.month, 1);
        final endMonth = DateTime(range.end.year, range.end.month + 1, 1);
        while (cursor.isBefore(endMonth)) {
          final monthEnd = DateTime(cursor.year, cursor.month + 1, 1);
          final rev = sales
              .where((s) => !s.createdAt.isBefore(cursor) && s.createdAt.isBefore(monthEnd))
              .fold(0.0, (s, e) => s + e.finalAmount);
          points.add(_ChartPoint(
              label: monthFmt.format(cursor),
              tooltipLabel: DateFormat('MMMM yyyy', 'fr').format(cursor),
              value: rev));
          cursor = monthEnd;
        }
      }
      return points;
  }
});

// ── Product écoulement providers ───────────────────────────────────────────

class _ProdParams {
  final _RevPeriod period;
  final DateTimeRange? customRange;
  final String? product; // null = tous les produits
  const _ProdParams(this.period, [this.customRange, this.product]);

  @override
  bool operator ==(Object other) =>
      other is _ProdParams &&
      other.period == period &&
      other.product == product &&
      other.customRange?.start == customRange?.start &&
      other.customRange?.end == customRange?.end;

  @override
  int get hashCode =>
      Object.hash(period, customRange?.start, customRange?.end, product);
}

class _ProdResult {
  final List<_ChartPoint> points; // quantity per time unit
  final List<String> products;    // all product names found in period
  final int bestIdx;              // index with highest quantity (-1 if empty)
  const _ProdResult(
      {required this.points, required this.products, required this.bestIdx});
}

final _prodPeriodProvider =
    StateProvider<_RevPeriod>((ref) => _RevPeriod.month);
final _prodCustomRangeProvider = StateProvider<DateTimeRange?>((ref) => null);
final _prodFilterProvider = StateProvider<String?>((ref) => null);

final _prodChartProvider = FutureProvider.family
    .autoDispose<_ProdResult, _ProdParams>((ref, params) async {
  final now = haitiNow();

  final DateTime from;
  final DateTime toDate;
  switch (params.period) {
    case _RevPeriod.week:
      from   = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
      toDate = now.add(const Duration(days: 1));
    case _RevPeriod.month:
      from   = DateTime(now.year, now.month, 1);
      toDate = now.add(const Duration(days: 1));
    case _RevPeriod.year:
      from   = DateTime(now.year, 1, 1);
      toDate = now.add(const Duration(days: 1));
    case _RevPeriod.custom:
      if (params.customRange == null) {
        return const _ProdResult(points: [], products: [], bestIdx: -1);
      }
      from   = params.customRange!.start;
      toDate = params.customRange!.end.add(const Duration(days: 1));
  }

  final sales = await _fetchAllSales(from, toDate);

  // Collect all product names for the dropdown
  final allProducts = <String>{};
  for (final sale in sales) {
    for (final item in sale.items) {
      allProducts.add(item.productName ?? 'Produit');
    }
  }
  final productList = allProducts.toList()..sort();

  // Helper: sum quantity sold in a time slot (respects product filter)
  double qty(DateTime start, DateTime end) {
    double total = 0;
    for (final sale in sales) {
      if (!sale.createdAt.isBefore(start) && sale.createdAt.isBefore(end)) {
        for (final item in sale.items) {
          if (params.product == null ||
              item.productName == params.product) {
            total += item.quantity;
          }
        }
      }
    }
    return total;
  }

  // Build time buckets
  final List<_ChartPoint> points;

  switch (params.period) {
    case _RevPeriod.week:
      final dayFmt   = DateFormat('EEE', 'fr');
      final shortFmt = DateFormat('dd/MM');
      points = List.generate(7, (i) {
        final day      = now.subtract(Duration(days: 6 - i));
        final dayStart = DateTime(day.year, day.month, day.day);
        return _ChartPoint(
            label: dayFmt.format(day),
            tooltipLabel: shortFmt.format(day),
            value: qty(dayStart, dayStart.add(const Duration(days: 1))));
      });

    case _RevPeriod.month:
      final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
      final pts = <_ChartPoint>[];
      for (var d = 1; d <= daysInMonth; d++) {
        final dayStart = DateTime(now.year, now.month, d);
        if (dayStart.isAfter(now)) break;
        pts.add(_ChartPoint(
            label: '$d',
            tooltipLabel: DateFormat('dd/MM').format(dayStart),
            value: qty(dayStart, dayStart.add(const Duration(days: 1)))));
      }
      points = pts;

    case _RevPeriod.year:
      final monthFmt = DateFormat('MMM', 'fr');
      final pts = <_ChartPoint>[];
      for (var m = 1; m <= 12; m++) {
        final monthStart = DateTime(now.year, m, 1);
        if (monthStart.isAfter(now)) break;
        pts.add(_ChartPoint(
            label: monthFmt.format(monthStart),
            tooltipLabel: DateFormat('MMMM yyyy', 'fr').format(monthStart),
            value: qty(monthStart, DateTime(now.year, m + 1, 1))));
      }
      points = pts;

    case _RevPeriod.custom:
      final range = params.customRange!;
      final diff  = range.end.difference(range.start).inDays;
      final pts   = <_ChartPoint>[];
      if (diff <= 62) {
        final dayFmt = DateFormat('dd/MM');
        for (var d = 0; d <= diff; d++) {
          final dayStart = DateTime(range.start.year, range.start.month,
                  range.start.day)
              .add(Duration(days: d));
          pts.add(_ChartPoint(
              label: dayFmt.format(dayStart),
              tooltipLabel: DateFormat('dd/MM/yyyy').format(dayStart),
              value:
                  qty(dayStart, dayStart.add(const Duration(days: 1)))));
        }
      } else {
        final monthFmt = DateFormat('MMM yy', 'fr');
        var cursor = DateTime(range.start.year, range.start.month, 1);
        final endMonth =
            DateTime(range.end.year, range.end.month + 1, 1);
        while (cursor.isBefore(endMonth)) {
          final monthEnd = DateTime(cursor.year, cursor.month + 1, 1);
          pts.add(_ChartPoint(
              label: monthFmt.format(cursor),
              tooltipLabel:
                  DateFormat('MMMM yyyy', 'fr').format(cursor),
              value: qty(cursor, monthEnd)));
          cursor = monthEnd;
        }
      }
      points = pts;
  }

  // Find best time slot
  var bestIdx = -1;
  var bestVal = -1.0;
  for (var i = 0; i < points.length; i++) {
    if (points[i].value > bestVal) {
      bestVal = points[i].value;
      bestIdx = i;
    }
  }

  return _ProdResult(
      points: points, products: productList, bestIdx: bestIdx);
});

// ── KPI data model ─────────────────────────────────────────────────────────

class _StatsData {
  final List<SaleModel> sales;
  final Map<String, double> revenueByProduct;
  final Map<String, double> byPaymentMethod;

  _StatsData({
    required this.sales,
    required this.revenueByProduct,
    required this.byPaymentMethod,
  });

  factory _StatsData.from(List<SaleModel> sales) {
    final Map<String, double> byProduct = {};
    final Map<String, double> byMethod  = {};
    for (final sale in sales) {
      for (final item in sale.items) {
        final name = item.productName ?? 'Produit';
        byProduct[name] = (byProduct[name] ?? 0) + item.subtotal;
      }
      for (final pmt in sale.payments) {
        byMethod[pmt.method] = (byMethod[pmt.method] ?? 0) + pmt.amount;
      }
    }
    return _StatsData(
        sales: sales,
        revenueByProduct: byProduct,
        byPaymentMethod: byMethod);
  }

  double get totalRevenue => sales.fold(0.0, (s, e) => s + e.finalAmount);
  double get totalPaid    => sales.fold(0.0, (s, e) => s + e.paidAmount);
  double get avgBasket    => sales.isEmpty ? 0 : totalRevenue / sales.length;
}

// ── Screen ─────────────────────────────────────────────────────────────────

class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(_statsProvider);
    final settings   = ref.watch(settingsProvider);
    final fmt = NumberFormat.currency(
        locale: 'fr_HT', symbol: settings.currencySymbol, decimalDigits: 0);

    return statsAsync.when(
      data: (data) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Statistiques · ${DateFormat('MMMM yyyy', 'fr').format(haitiNow())}',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),

            _KpiRow(data: data, fmt: fmt),
            const SizedBox(height: 24),

            // Revenue chart with period selector
            Consumer(builder: (context, ref, _) {
              final period      = ref.watch(_revPeriodProvider);
              final customRange = ref.watch(_customRangeProvider);
              final params      = _RevParams(period, customRange);
              final chartAsync  = ref.watch(_revenueChartProvider(params));

              return _ChartCard(
                title: 'Revenus',
                icon: Icons.show_chart_rounded,
                height: 220,
                headerAction: _PeriodTabs(
                  period: period,
                  customRange: customRange,
                  onPeriodChanged: (p) =>
                      ref.read(_revPeriodProvider.notifier).state = p,
                  onCustomRange: (r) {
                    ref.read(_customRangeProvider.notifier).state = r;
                    ref.read(_revPeriodProvider.notifier).state =
                        _RevPeriod.custom;
                  },
                ),
                child: chartAsync.when(
                  data: (points) {
                    final hasData = points.any((p) => p.value > 0);
                    return hasData
                        ? _RevenueLineChart(points: points, fmt: fmt)
                        : _noData();
                  },
                  loading: () => const Center(
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  error: (e, _) => _noData(),
                ),
              );
            }),
            const SizedBox(height: 16),

            // Bottom row: top products + payment methods
            LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth >= 700;
              final topProducts = _ChartCard(
                title: 'Top produits',
                icon: Icons.bar_chart_rounded,
                height: 260,
                child: data.revenueByProduct.isEmpty
                    ? _noData()
                    : _TopProductsBar(data: data, fmt: fmt),
              );
              final paymentMethods = _ChartCard(
                title: 'Modes de paiement',
                icon: Icons.pie_chart_rounded,
                height: 260,
                child: data.byPaymentMethod.isEmpty
                    ? _noData()
                    : _PaymentPieChart(data: data),
              );

              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: topProducts),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: paymentMethods),
                  ],
                );
              }
              return Column(children: [
                topProducts,
                const SizedBox(height: 16),
                paymentMethods,
              ]);
            }),
            const SizedBox(height: 16),

            // Product écoulement section
            const _ProductEcoulementSection(),
            const SizedBox(height: 20),
          ],
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text('Erreur: $e',
                style: const TextStyle(color: AppColors.error)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => ref.invalidate(_statsProvider),
              child: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _noData() => const Center(
        child: Text('Aucune donnée',
            style:
                TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      );
}

// ── Period tabs ────────────────────────────────────────────────────────────

class _PeriodTabs extends StatelessWidget {
  final _RevPeriod period;
  final DateTimeRange? customRange;
  final ValueChanged<_RevPeriod> onPeriodChanged;
  final ValueChanged<DateTimeRange> onCustomRange;

  const _PeriodTabs({
    required this.period,
    required this.customRange,
    required this.onPeriodChanged,
    required this.onCustomRange,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      children: [
        // Fixed period tabs
        Container(
          height: 30,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [_RevPeriod.week, _RevPeriod.month, _RevPeriod.year]
                .map((p) => _tab(p, period == p))
                .toList(),
          ),
        ),

        // Custom range button
        GestureDetector(
          onTap: () async {
            final now = haitiNow();
            final picked = await showDateRangePicker(
              context: context,
              firstDate: DateTime(now.year - 3),
              lastDate: now,
              initialDateRange: customRange ??
                  DateTimeRange(
                      start: now.subtract(const Duration(days: 30)),
                      end: now),
              locale: const Locale('fr'),
              builder: (context, child) => Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: ColorScheme.light(
                    primary: AppColors.primary,
                    onSurface: AppColors.textPrimary,
                  ),
                ),
                child: child!,
              ),
            );
            if (picked != null) onCustomRange(picked);
          },
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: period == _RevPeriod.custom
                  ? AppColors.primary.withValues(alpha: 0.08)
                  : AppColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: period == _RevPeriod.custom
                    ? AppColors.primary.withValues(alpha: 0.4)
                    : AppColors.divider,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.date_range_rounded,
                  size: 13,
                  color: period == _RevPeriod.custom
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: 5),
                Text(
                  period == _RevPeriod.custom && customRange != null
                      ? '${DateFormat('dd/MM').format(customRange!.start)} – ${DateFormat('dd/MM').format(customRange!.end)}'
                      : 'Personnalisé',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: period == _RevPeriod.custom
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: period == _RevPeriod.custom
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _tab(_RevPeriod p, bool selected) {
    return GestureDetector(
      onTap: () => onPeriodChanged(p),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: selected
              ? [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1))
                ]
              : null,
        ),
        child: Text(
          p.label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ── KPI row ────────────────────────────────────────────────────────────────

class _KpiRow extends StatelessWidget {
  final _StatsData data;
  final NumberFormat fmt;
  const _KpiRow({required this.data, required this.fmt});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _Kpi(label: 'Chiffre d\'affaires', value: fmt.format(data.totalRevenue),
            icon: Icons.trending_up_rounded, color: AppColors.primary),
        _Kpi(label: 'Encaissé', value: fmt.format(data.totalPaid),
            icon: Icons.check_circle_outline_rounded, color: AppColors.success),
        _Kpi(label: 'Panier moyen', value: fmt.format(data.avgBasket),
            icon: Icons.shopping_cart_rounded, color: AppColors.info),
        _Kpi(label: 'Nb transactions', value: '${data.sales.length}',
            icon: Icons.receipt_rounded, color: AppColors.warning),
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _Kpi({required this.label, required this.value,
      required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: TextStyle(fontSize: 15,
                fontWeight: FontWeight.w700, color: color)),
            Text(label, style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary)),
          ],
        )),
      ]),
    );
  }
}

// ── Chart card wrapper ─────────────────────────────────────────────────────

class _ChartCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final double height;
  final Widget child;
  final Widget? headerAction;

  const _ChartCard({
    required this.title, required this.icon,
    required this.height, required this.child,
    this.headerAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700)),
            if (headerAction != null) ...[
              const Spacer(),
              headerAction!,
            ],
          ]),
          const SizedBox(height: 16),
          SizedBox(height: height, child: child),
        ],
      ),
    );
  }
}

// ── Revenue line chart ─────────────────────────────────────────────────────

class _RevenueLineChart extends StatelessWidget {
  final List<_ChartPoint> points;
  final NumberFormat fmt;
  const _RevenueLineChart({required this.points, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final spots = points.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.value))
        .toList();
    final maxY = points.map((p) => p.value).fold(0.0, (a, b) => a > b ? a : b);
    final interval = maxY > 0 ? maxY / 4 : 1.0;
    final xInterval = (points.length / 8).ceilToDouble().clamp(1.0, 999.0);

    return LineChart(LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: interval,
        getDrawingHorizontalLine: (_) =>
            const FlLine(color: AppColors.divider, strokeWidth: 1),
      ),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (spots) => spots.map((spot) {
            final idx = spot.x.toInt();
            final lbl = idx < points.length ? points[idx].tooltipLabel : '';
            return LineTooltipItem(
              '$lbl\n${fmt.format(spot.y)}',
              const TextStyle(color: Colors.white, fontSize: 11,
                  fontWeight: FontWeight.w600),
            );
          }).toList(),
        ),
      ),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 56,
            interval: interval,
            getTitlesWidget: (v, meta) {
              if (v == 0 || v >= meta.max * 0.99) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(fmt.format(v),
                    style: const TextStyle(
                        fontSize: 9, color: AppColors.textSecondary)),
              );
            },
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            interval: xInterval,
            getTitlesWidget: (v, meta) {
              final idx = v.toInt();
              if (idx < 0 || idx >= points.length) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(points[idx].label,
                    style: const TextStyle(
                        fontSize: 9, color: AppColors.textSecondary)),
              );
            },
          ),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          curveSmoothness: 0.35,
          color: AppColors.primary,
          barWidth: 2.5,
          dotData: FlDotData(
            show: points.length <= 12,
            getDotPainter: (_, percent, bar, idx) => FlDotCirclePainter(
              radius: 3.5,
              color: AppColors.primary,
              strokeWidth: 1.5,
              strokeColor: AppColors.surface,
            ),
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.primary.withValues(alpha: 0.18),
                AppColors.primary.withValues(alpha: 0.01),
              ],
            ),
          ),
        ),
      ],
      minY: 0,
      maxY: maxY > 0 ? maxY * 1.2 : 1,
    ));
  }
}

// ── Top products bar chart ─────────────────────────────────────────────────

class _TopProductsBar extends StatelessWidget {
  final _StatsData data;
  final NumberFormat fmt;
  const _TopProductsBar({required this.data, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final sorted = data.revenueByProduct.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top  = sorted.take(6).toList();
    final maxY = top.isEmpty ? 1.0 : top.first.value;

    const colors = [
      AppColors.primary, AppColors.info, AppColors.success,
      AppColors.warning, AppColors.accent, AppColors.statusPartial,
    ];

    return BarChart(BarChartData(
      alignment: BarChartAlignment.spaceAround,
      maxY: maxY * 1.2,
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipItem: (group, gIdx, rod, rIdx) => BarTooltipItem(
            '${top[gIdx].key}\n${fmt.format(rod.toY)}',
            const TextStyle(color: Colors.white, fontSize: 11,
                fontWeight: FontWeight.w600),
          ),
        ),
      ),
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 28,
            getTitlesWidget: (v, meta) {
              final idx = v.toInt();
              if (idx < 0 || idx >= top.length) return const SizedBox.shrink();
              final name  = top[idx].key;
              final short = name.length > 8 ? '${name.substring(0, 8)}…' : name;
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(short, style: const TextStyle(
                    fontSize: 9, color: AppColors.textSecondary)),
              );
            },
          ),
        ),
        leftTitles:  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      gridData:   const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      barGroups: top.asMap().entries.map((e) => BarChartGroupData(
        x: e.key,
        barRods: [
          BarChartRodData(
            toY: e.value.value,
            color: colors[e.key % colors.length],
            width: 20,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ],
      )).toList(),
    ));
  }
}

// ── Payment pie chart ──────────────────────────────────────────────────────

class _PaymentPieChart extends StatefulWidget {
  final _StatsData data;
  const _PaymentPieChart({required this.data});

  @override
  State<_PaymentPieChart> createState() => _PaymentPieChartState();
}

class _PaymentPieChartState extends State<_PaymentPieChart> {
  int _touched = -1;

  static const _colors = [
    AppColors.primary, AppColors.success, AppColors.warning,
    AppColors.info, AppColors.accent,
  ];

  String _label(String m) {
    switch (m.toUpperCase()) {
      case 'CASH':   return 'Espèces';
      case 'BANK':   return 'Banque';
      case 'MOBILE': return 'Mobile';
      default:       return m;
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.data.byPaymentMethod.entries.toList();
    final total   = entries.fold(0.0, (s, e) => s + e.value);

    return Column(children: [
      Expanded(
        child: PieChart(PieChartData(
          pieTouchData: PieTouchData(
            touchCallback: (event, resp) => setState(() {
              if (!event.isInterestedForInteractions ||
                  resp?.touchedSection == null) {
                _touched = -1;
              } else {
                _touched = resp!.touchedSection!.touchedSectionIndex;
              }
            }),
          ),
          sections: entries.asMap().entries.map((e) {
            final isTouched = e.key == _touched;
            final pct = total > 0 ? e.value.value / total * 100 : 0;
            return PieChartSectionData(
              value: e.value.value,
              title: '${pct.toStringAsFixed(0)}%',
              radius: isTouched ? 70 : 58,
              color: _colors[e.key % _colors.length],
              titleStyle: const TextStyle(fontSize: 11,
                  fontWeight: FontWeight.w700, color: Colors.white),
            );
          }).toList(),
          sectionsSpace: 2,
          centerSpaceRadius: 36,
        )),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 4,
        children: entries.asMap().entries.map((e) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10, height: 10,
              decoration: BoxDecoration(
                  color: _colors[e.key % _colors.length],
                  shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text(_label(e.value.key),
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary)),
          ],
        )).toList(),
      ),
    ]);
  }
}

// ── Product écoulement section ─────────────────────────────────────────────

class _ProductEcoulementSection extends ConsumerStatefulWidget {
  const _ProductEcoulementSection();

  @override
  ConsumerState<_ProductEcoulementSection> createState() =>
      _ProductEcoulementSectionState();
}

class _ProductEcoulementSectionState
    extends ConsumerState<_ProductEcoulementSection> {

  @override
  Widget build(BuildContext context) {
    final period      = ref.watch(_prodPeriodProvider);
    final customRange = ref.watch(_prodCustomRangeProvider);
    final product     = ref.watch(_prodFilterProvider);
    final params      = _ProdParams(period, customRange, product);
    final chartAsync  = ref.watch(_prodChartProvider(params));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            const Icon(Icons.inventory_2_rounded,
                size: 18, color: AppColors.success),
            const SizedBox(width: 8),
            const Text('Écoulement des produits',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const Spacer(),
            _PeriodTabs(
              period: period,
              customRange: customRange,
              onPeriodChanged: (p) {
                ref.read(_prodPeriodProvider.notifier).state = p;
                // reset product filter on period change
                ref.read(_prodFilterProvider.notifier).state = null;
              },
              onCustomRange: (r) {
                ref.read(_prodCustomRangeProvider.notifier).state = r;
                ref.read(_prodPeriodProvider.notifier).state =
                    _RevPeriod.custom;
                ref.read(_prodFilterProvider.notifier).state = null;
              },
            ),
          ]),

          const SizedBox(height: 12),

          // Product filter + best-period badge
          chartAsync.when(
            data: (result) => Row(children: [
              // Product dropdown
              Container(
                height: 32,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.divider),
                  borderRadius: BorderRadius.circular(8),
                  color: AppColors.background,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: product,
                    isDense: true,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textPrimary),
                    items: [
                      const DropdownMenuItem(
                          value: null,
                          child: Text('Tous les produits')),
                      ...result.products.map((p) =>
                          DropdownMenuItem(value: p, child: Text(p))),
                    ],
                    onChanged: (v) =>
                        ref.read(_prodFilterProvider.notifier).state = v,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Best-period badge
              if (result.bestIdx >= 0 &&
                  result.points[result.bestIdx].value > 0) ...[
                const Icon(Icons.emoji_events_rounded,
                    size: 14, color: AppColors.warning),
                const SizedBox(width: 4),
                Text(
                  'Meilleur : ${result.points[result.bestIdx].tooltipLabel}'
                  ' (${result.points[result.bestIdx].value.toStringAsFixed(result.points[result.bestIdx].value % 1 == 0 ? 0 : 1)} unités)',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warning),
                ),
              ],
            ]),
            loading: () => const SizedBox(height: 32),
            error: (err, st) => const SizedBox(height: 32),
          ),

          const SizedBox(height: 16),

          // Chart
          SizedBox(
            height: 220,
            child: chartAsync.when(
              data: (result) {
                final hasData = result.points.any((p) => p.value > 0);
                return hasData
                    ? _ProdBarChart(result: result)
                    : const Center(
                        child: Text('Aucune donnée',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13)));
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              error: (e, _) => Center(
                child: Text('Erreur: $e',
                    style: const TextStyle(color: AppColors.error, fontSize: 12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Product écoulement bar chart ───────────────────────────────────────────

class _ProdBarChart extends StatelessWidget {
  final _ProdResult result;
  const _ProdBarChart({required this.result});

  @override
  Widget build(BuildContext context) {
    final points = result.points;
    final maxY = points.map((p) => p.value).fold(0.0, (a, b) => a > b ? a : b);
    final xInterval = (points.length / 8).ceilToDouble().clamp(1.0, 999.0);

    return BarChart(BarChartData(
      alignment: BarChartAlignment.spaceAround,
      maxY: maxY > 0 ? maxY * 1.25 : 1,
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipItem: (group, gIdx, rod, rIdx) {
            final pt = points[gIdx];
            final qty = rod.toY;
            final qtyStr = qty % 1 == 0
                ? qty.toInt().toString()
                : qty.toStringAsFixed(1);
            return BarTooltipItem(
              '${pt.tooltipLabel}\n$qtyStr unités',
              const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            );
          },
        ),
      ),
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 24,
            interval: xInterval,
            getTitlesWidget: (v, meta) {
              final idx = v.toInt();
              if (idx < 0 || idx >= points.length) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(points[idx].label,
                    style: const TextStyle(
                        fontSize: 9, color: AppColors.textSecondary)),
              );
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 36,
            getTitlesWidget: (v, meta) {
              if (v == 0 || v >= meta.max * 0.99) {
                return const SizedBox.shrink();
              }
              return Text(
                v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1),
                style: const TextStyle(
                    fontSize: 9, color: AppColors.textSecondary),
              );
            },
          ),
        ),
        topTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) =>
            const FlLine(color: AppColors.divider, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      barGroups: points.asMap().entries.map((e) {
        final isBest = e.key == result.bestIdx && e.value.value > 0;
        return BarChartGroupData(
          x: e.key,
          barRods: [
            BarChartRodData(
              toY: e.value.value,
              color: isBest
                  ? AppColors.warning
                  : AppColors.success.withValues(alpha: 0.75),
              width: points.length <= 12 ? 20 : 10,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ],
        );
      }).toList(),
    ));
  }
}
