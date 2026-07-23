import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart' show Options, ResponseType;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:pos_connect/core/permissions.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/core/date_utils.dart' show haitiNow;
import 'package:pos_connect/data/models/sale_model.dart';
import 'package:pos_connect/providers/auth_provider.dart';
import 'package:pos_connect/providers/settings_provider.dart';

// ── User info for print dialog ─────────────────────────────────────────────

class _UserInfo {
  final String id;
  final String fullName;
  _UserInfo(this.id, this.fullName);
}

final _allUsersProvider = FutureProvider.autoDispose<List<_UserInfo>>((ref) async {
  final res = await dio.get('/api/users/');
  final data = res.data as List? ?? [];
  final list = data.map((e) {
    final fname = e['fname']?.toString() ?? '';
    final lname = e['lname']?.toString() ?? '';
    return _UserInfo(e['id'].toString(), '$fname $lname'.trim());
  }).toList();
  list.sort((a, b) => a.fullName.compareTo(b.fullName));
  return list;
});

// ── Period helpers ─────────────────────────────────────────────────────────

enum ReportPeriod { today, week, month, lastMonth, custom }

extension ReportPeriodLabel on ReportPeriod {
  String get label {
    switch (this) {
      case ReportPeriod.today:
        return "Aujourd'hui";
      case ReportPeriod.week:
        return 'Cette semaine';
      case ReportPeriod.month:
        return 'Ce mois';
      case ReportPeriod.lastMonth:
        return 'Mois précédent';
      case ReportPeriod.custom:
        return 'Personnalisé';
    }
  }

  (DateTime, DateTime) get range {
    final now = haitiNow();
    final today = DateTime(now.year, now.month, now.day);
    switch (this) {
      case ReportPeriod.today:
        return (today, today.add(const Duration(days: 1)));
      case ReportPeriod.week:
        final start = today.subtract(Duration(days: today.weekday - 1));
        return (start, today.add(const Duration(days: 1)));
      case ReportPeriod.month:
        return (DateTime(now.year, now.month, 1),
            today.add(const Duration(days: 1)));
      case ReportPeriod.lastMonth:
        final first = DateTime(now.year, now.month - 1, 1);
        final last = DateTime(now.year, now.month, 1);
        return (first, last);
      case ReportPeriod.custom:
        return (today, today.add(const Duration(days: 1)));
    }
  }
}

// ── State ──────────────────────────────────────────────────────────────────

class ReportParams {
  final ReportPeriod period;
  final DateTime? customFrom;
  final DateTime? customTo;
  final String? userFilter;

  const ReportParams({
    this.period = ReportPeriod.month,
    this.customFrom,
    this.customTo,
    this.userFilter,
  });

  (DateTime, DateTime) get effectiveRange {
    if (period == ReportPeriod.custom &&
        customFrom != null &&
        customTo != null) {
      return (customFrom!, customTo!.add(const Duration(days: 1)));
    }
    return period.range;
  }
}

final reportParamsProvider = StateProvider((ref) => const ReportParams());

final reportSalesProvider =
    FutureProvider.autoDispose<List<SaleModel>>((ref) async {
  final params = ref.watch(reportParamsProvider);
  final (from, to) = params.effectiveRange;
  final dateFmt = DateFormat('yyyy-MM-dd');
  const limit = 100;

  final baseQuery = {
    'limit': limit,
    'date_from': dateFmt.format(from),
    'date_to': dateFmt.format(to),
  };

  // First page — also tells us the total page count
  final first = await dio.get('/api/sales/',
      queryParameters: {...baseQuery, 'page': 1});
  final meta = first.data['meta'] as Map<String, dynamic>? ?? {};
  final pages = (meta['pages'] as num?)?.toInt() ?? 1;

  SaleModel parse(dynamic e) =>
      SaleModel.fromJson(e as Map<String, dynamic>);

  final all = <SaleModel>[
    ...(first.data['data'] as List? ?? []).map(parse),
  ];

  if (pages > 1) {
    final rest = await Future.wait(List.generate(
      pages - 1,
      (i) => dio.get('/api/sales/',
          queryParameters: {...baseQuery, 'page': i + 2}),
    ));
    for (final res in rest) {
      all.addAll((res.data['data'] as List? ?? []).map(parse));
    }
  }

  return all;
});

// ── Screen ─────────────────────────────────────────────────────────────────

final _dateFmt = DateFormat('dd/MM/yyyy', 'fr');
final _dtFmt = DateFormat('dd/MM/yyyy HH:mm', 'fr');

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final user = ref.read(authProvider).user;
      final isCashier = !(user?.hasPermission(Perm.reportsReadAll) ?? false);
      if (isCashier) {
        ref.read(reportParamsProvider.notifier).state =
            const ReportParams(period: ReportPeriod.today);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final isCashier = !(user?.hasPermission(Perm.reportsReadAll) ?? false);
    final params = ref.watch(reportParamsProvider);
    final salesAsync = ref.watch(reportSalesProvider);

    return Column(
      children: [
        // ── Filter bar ───────────────────────────────────────────────
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Period chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ReportPeriod.values.map((p) {
                    final selected = params.period == p;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(p.label),
                        selected: selected,
                        onSelected: (v) {
                          if (v) {
                            ref.read(reportParamsProvider.notifier).state =
                                ReportParams(
                                    period: p,
                                    userFilter: params.userFilter);
                          }
                        },
                        selectedColor:
                            AppColors.primary.withValues(alpha: 0.15),
                        checkmarkColor: AppColors.primary,
                        labelStyle: TextStyle(
                          fontSize: 12,
                          color: selected
                              ? AppColors.primary
                              : AppColors.textSecondary,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              // Custom date range picker
              if (params.period == ReportPeriod.custom) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _DatePickerField(
                        label: 'Du',
                        date: params.customFrom,
                        onPicked: (d) =>
                            ref.read(reportParamsProvider.notifier).state =
                                ReportParams(
                              period: ReportPeriod.custom,
                              customFrom: d,
                              customTo: params.customTo,
                              userFilter: params.userFilter,
                            ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DatePickerField(
                        label: 'Au',
                        date: params.customTo,
                        onPicked: (d) =>
                            ref.read(reportParamsProvider.notifier).state =
                                ReportParams(
                              period: ReportPeriod.custom,
                              customFrom: params.customFrom,
                              customTo: d,
                              userFilter: params.userFilter,
                            ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),

        // ── Content ──────────────────────────────────────────────────
        Expanded(
          child: salesAsync.when(
            data: (sales) =>
                _ReportContent(allSales: sales, params: params, isCashier: isCashier),
            loading: () =>
                const Center(child: CircularProgressIndicator()),
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
                    onPressed: () => ref.invalidate(reportSalesProvider),
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Report content ─────────────────────────────────────────────────────────

class _ReportContent extends ConsumerStatefulWidget {
  final List<SaleModel> allSales;
  final ReportParams params;
  final bool isCashier;

  const _ReportContent({required this.allSales, required this.params, this.isCashier = false});

  @override
  ConsumerState<_ReportContent> createState() => _ReportContentState();
}

class _ReportContentState extends ConsumerState<_ReportContent> {

  @override
  Widget build(BuildContext context) {
    final params = widget.params;
    final settings = ref.watch(settingsProvider);
    final fmt = NumberFormat.currency(
        locale: 'fr_HT', symbol: settings.currencySymbol, decimalDigits: 2);

    // Unique users from current period's sales
    final uniqueUsers = widget.allSales
        .map((s) => s.userFullName)
        .whereType<String>()
        .where((n) => n.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    // Filter sales by selected user
    final sales = params.userFilter != null
        ? widget.allSales
            .where((s) => s.userFullName == params.userFilter)
            .toList()
        : widget.allSales;

    final totalRevenue = sales.fold(0.0, (s, e) => s + e.finalAmount);
    final totalPaid = sales.fold(0.0, (s, e) => s + e.paidAmount);
    final totalDiscount = sales.fold(0.0, (s, e) => s + e.discount);
    final totalBalance = totalRevenue - totalPaid;
    final paidCount = sales.where((s) => s.status == 'PAID').length;
    final unpaidCount = sales.where((s) => s.status == 'UNPAID').length;
    final partialCount = sales.where((s) => s.status == 'PARTIAL').length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Toolbar: period label + user filter + print button ──
          Row(
            children: [
              // Period label
              Expanded(
                child: Text(
                  _periodLabel(params),
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
              ),

              // User filter — hidden for cashiers (backend enforces their own data)
              if (!widget.isCashier && uniqueUsers.isNotEmpty) ...[
                Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: params.userFilter != null
                          ? AppColors.primary
                          : AppColors.divider,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: params.userFilter,
                      hint: const Text('Tous les caissiers',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary)),
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textPrimary),
                      icon: const Icon(Icons.arrow_drop_down,
                          size: 18, color: AppColors.textSecondary),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Tous les caissiers',
                              style: TextStyle(fontSize: 12)),
                        ),
                        ...uniqueUsers.map((u) => DropdownMenuItem<String?>(
                              value: u,
                              child: Text(u, style: const TextStyle(fontSize: 12)),
                            )),
                      ],
                      onChanged: (user) {
                        ref.read(reportParamsProvider.notifier).state =
                            ReportParams(
                          period: params.period,
                          customFrom: params.customFrom,
                          customTo: params.customTo,
                          userFilter: user,
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],

              // Print button — opens config dialog
              SizedBox(
                height: 36,
                child: ElevatedButton.icon(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) =>
                        _PrintConfigDialog(currentParams: params),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                  icon: const Icon(Icons.print_rounded, size: 16),
                  label: const Text('Imprimer PDF'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── KPI cards ────────────────────────────────────────────
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _KpiCard(
                label: "Chiffre d'affaires",
                value: fmt.format(totalRevenue),
                icon: Icons.trending_up_rounded,
                color: AppColors.primary,
              ),
              _KpiCard(
                label: 'Encaissé',
                value: fmt.format(totalPaid),
                icon: Icons.payments_rounded,
                color: AppColors.success,
              ),
              _KpiCard(
                label: 'Reste à encaisser',
                value: fmt.format(totalBalance),
                icon: Icons.hourglass_bottom_rounded,
                color: AppColors.warning,
              ),
              _KpiCard(
                label: 'Remises accordées',
                value: fmt.format(totalDiscount),
                icon: Icons.local_offer_rounded,
                color: AppColors.info,
              ),
              _KpiCard(
                label: 'Nb ventes',
                value: '${sales.length}',
                icon: Icons.receipt_long_rounded,
                color: AppColors.textSecondary,
              ),
              _KpiCard(
                label: 'Payées / Partielles / Impayées',
                value: '$paidCount / $partialCount / $unpaidCount',
                icon: Icons.pie_chart_rounded,
                color: AppColors.statusPaid,
                width: 240,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Sales table ───────────────────────────────────────────
          if (sales.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: const Column(
                children: [
                  Icon(Icons.receipt_outlined,
                      size: 48, color: AppColors.textSecondary),
                  SizedBox(height: 12),
                  Text('Aucune vente sur cette période',
                      style: TextStyle(color: AppColors.textSecondary)),
                ],
              ),
            )
          else ...[
            const Text('Détail des ventes',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              clipBehavior: Clip.hardEdge,
              child: Table(
                    columnWidths: const {
                      0: FlexColumnWidth(1.4), // Référence
                      1: FlexColumnWidth(1.4), // Date + heure
                      2: FlexColumnWidth(1.8), // Client
                      3: FlexColumnWidth(1.2), // Caissier
                      4: FlexColumnWidth(1.1), // Total
                      5: FlexColumnWidth(1.1), // Payé
                      6: FlexColumnWidth(0.9), // Statut
                    },
                    children: [
                      _tableHeader([
                        'Référence',
                        'Date',
                        'Client',
                        'Caissier',
                        'Total',
                        'Payé',
                        'Statut'
                      ]),
                      ...sales.map((s) => _tableRow([
                            s.reference,
                            _dtFmt.format(s.createdAt),
                            s.customerName ?? 'Comptoir',
                            s.userFullName ?? '-',
                            fmt.format(s.finalAmount),
                            fmt.format(s.paidAmount),
                            _statusLabel(s.status),
                          ], statusColor: _statusColor(s.status))),
                    ],
                  ),
            ),
          ],
        ],
      ),
    );
  }

  String _periodLabel(ReportParams p) {
    if (p.period == ReportPeriod.custom) {
      final from = p.customFrom;
      final to = p.customTo;
      if (from != null && to != null) {
        return 'Du ${_dateFmt.format(from)} au ${_dateFmt.format(to)}';
      }
      return 'Période personnalisée';
    }
    return p.period.label;
  }

  TableRow _tableHeader(List<String> cols) {
    return TableRow(
      decoration: const BoxDecoration(color: AppColors.background),
      children: cols
          .map((c) => Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text(c,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary)),
              ))
          .toList(),
    );
  }

  TableRow _tableRow(List<String> cols, {Color? statusColor}) {
    return TableRow(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      children: cols.asMap().entries.map((entry) {
        final isStatus = entry.key == cols.length - 1;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: isStatus
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: (statusColor ?? AppColors.textSecondary)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    entry.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: statusColor ?? AppColors.textSecondary),
                  ),
                )
              : Text(entry.value,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13)),
        );
      }).toList(),
    );
  }
}

// ── Print config dialog ────────────────────────────────────────────────────

Future<List<SaleModel>> _fetchSalesForRange(DateTime from, DateTime to) async {
  final dateFmt = DateFormat('yyyy-MM-dd');
  const limit = 100;

  final baseQuery = {
    'limit': limit,
    'date_from': dateFmt.format(from),
    'date_to': dateFmt.format(to),
  };

  final first = await dio.get('/api/sales/',
      queryParameters: {...baseQuery, 'page': 1});
  final meta = first.data['meta'] as Map<String, dynamic>? ?? {};
  final pages = (meta['pages'] as num?)?.toInt() ?? 1;

  SaleModel parse(dynamic e) => SaleModel.fromJson(e as Map<String, dynamic>);

  final all = <SaleModel>[
    ...(first.data['data'] as List? ?? []).map(parse),
  ];

  if (pages > 1) {
    final rest = await Future.wait(List.generate(
      pages - 1,
      (i) => dio.get('/api/sales/',
          queryParameters: {...baseQuery, 'page': i + 2}),
    ));
    for (final res in rest) {
      all.addAll((res.data['data'] as List? ?? []).map(parse));
    }
  }

  return all;
}

class _PrintConfigDialog extends ConsumerStatefulWidget {
  final ReportParams currentParams;

  const _PrintConfigDialog({required this.currentParams});

  @override
  ConsumerState<_PrintConfigDialog> createState() => _PrintConfigDialogState();
}

class _PrintConfigDialogState extends ConsumerState<_PrintConfigDialog> {
  late DateTime _from;
  late DateTime _to;
  String? _selectedUserId;
  String? _selectedUserName;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final (from, to) = widget.currentParams.effectiveRange;
    _from = from;
    // effectiveRange 'to' is exclusive (next day at midnight) — show the last day
    _to = to.subtract(const Duration(days: 1));
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authProvider);
    final canViewAll = currentUser.user?.canViewAllReports ?? false;
    final usersAsync = canViewAll ? ref.watch(_allUsersProvider) : null;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.print_rounded, size: 20),
          SizedBox(width: 8),
          Text('Configuration impression',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Date range ──────────────────────────────────────────
            const Text('Période',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _DatePickerField(
                    label: 'Du',
                    date: _from,
                    onPicked: (d) => setState(() => _from = d),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DatePickerField(
                    label: 'Au',
                    date: _to,
                    onPicked: (d) => setState(() => _to = d),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── User filter ─────────────────────────────────────────
            const Text('Caissier',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 8),

            if (!canViewAll)
              // Simple user — locked to own report
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person_rounded,
                        size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Rapport pour : ${currentUser.user?.fullName ?? ''}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              )
            else if (usersAsync != null)
              usersAsync.when(
                data: (users) => Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.divider),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _selectedUserId,
                      isExpanded: true,
                      hint: const Text('Tous les caissiers (rapport global)',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary)),
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textPrimary),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Tous les caissiers',
                              style: TextStyle(fontSize: 13)),
                        ),
                        ...users.map((u) => DropdownMenuItem<String?>(
                              value: u.id,
                              child: Text(u.fullName,
                                  style: const TextStyle(fontSize: 13)),
                            )),
                      ],
                      onChanged: (id) {
                        final user = id != null
                            ? users.firstWhere((u) => u.id == id)
                            : null;
                        setState(() {
                          _selectedUserId = id;
                          _selectedUserName = user?.fullName;
                        });
                      },
                    ),
                  ),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Erreur: $e',
                    style: const TextStyle(color: AppColors.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        OutlinedButton.icon(
          onPressed: _loading ? null : _handleExportCsv,
          style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14)),
          icon: const Icon(Icons.table_chart_outlined, size: 16),
          label: const Text('CSV'),
        ),
        ElevatedButton.icon(
          onPressed: _loading ? null : _handlePrint,
          style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14)),
          icon: _loading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.print_rounded, size: 16),
          label: Text(_loading ? 'Génération...' : 'Imprimer'),
        ),
      ],
    );
  }

  String _buildCsv(List<SaleModel> sales, String sym) {
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'fr');
    const sep = ';';
    final buf = StringBuffer();
    buf.writeln([
      'Date', 'Référence', 'Caissier', 'Client', 'Statut',
      'Total ($sym)', 'Encaissé ($sym)', 'Remise ($sym)',
    ].map((h) => '"$h"').join(sep));

    for (final s in sales) {
      buf.writeln([
        '"${dateFmt.format(s.createdAt)}"',
        '"${s.reference}"',
        '"${s.userFullName ?? ''}"',
        '"${s.customerName ?? ''}"',
        '"${_statusFr(s.status)}"',
        s.finalAmount.toStringAsFixed(2),
        s.paidAmount.toStringAsFixed(2),
        s.discount.toStringAsFixed(2),
      ].join(sep));
    }
    return buf.toString();
  }

  String _statusFr(String s) {
    const m = {'PAID': 'Payé', 'PARTIAL': 'Partiel', 'UNPAID': 'Impayé', 'CANCELLED': 'Annulé'};
    return m[s.toUpperCase()] ?? s;
  }

  Future<void> _handleExportCsv() async {
    final currentUser = ref.read(authProvider);
    final settings = ref.read(settingsProvider);
    final messenger = ScaffoldMessenger.of(context);
    final canViewAll = currentUser.user?.canViewAllReports ?? false;

    setState(() => _loading = true);
    try {
      final toExclusive = _to.add(const Duration(days: 1));
      final sales = await _fetchSalesForRange(_from, toExclusive);

      final filtered = canViewAll
          ? (_selectedUserName != null
              ? sales.where((s) => s.userFullName == _selectedUserName).toList()
              : sales)
          : sales.where((s) => s.userFullName == currentUser.user?.fullName).toList();

      final sym = settings.currencySymbol.trim();
      final csv = _buildCsv(filtered, sym);
      final bytes = utf8.encode(csv);
      final filename =
          'rapport_ventes_${DateFormat('yyyyMMdd').format(haitiNow())}.csv';

      if (kIsWeb) {
        // Web: téléchargement direct via FilePicker
        await FilePicker.platform.saveFile(
          dialogTitle: 'Enregistrer le CSV',
          fileName: filename,
          bytes: bytes,
        );
      } else {
        final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Enregistrer le CSV',
          fileName: filename,
          allowedExtensions: ['csv'],
          type: FileType.custom,
        );
        if (path != null) {
          await File(path).writeAsBytes(bytes);
        }
      }

      if (mounted) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Export CSV téléchargé'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text("Erreur export CSV : $e"),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handlePrint() async {
    final currentUser = ref.read(authProvider);
    final settings = ref.read(settingsProvider);
    final messenger = ScaffoldMessenger.of(context);
    final canViewAll = currentUser.user?.canViewAllReports ?? false;

    setState(() => _loading = true);
    try {
      final toExclusive = _to.add(const Duration(days: 1));
      final sales = await _fetchSalesForRange(_from, toExclusive);

      final filteredSales = canViewAll
          ? (_selectedUserName != null
              ? sales
                  .where((s) => s.userFullName == _selectedUserName)
                  .toList()
              : sales)
          : sales
              .where((s) => s.userFullName == currentUser.user?.fullName)
              .toList();

      final pdfParams = ReportParams(
        period: ReportPeriod.custom,
        customFrom: _from,
        customTo: _to,
        userFilter: canViewAll ? _selectedUserName : currentUser.user?.fullName,
      );

      await _generatePdf(filteredSales, pdfParams, settings);
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text("Erreur lors de l'impression : $e"),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

// ── PDF generation ─────────────────────────────────────────────────────────

Future<void> _generatePdf(
    List<SaleModel> sales, ReportParams params, AppSettings settings) async {
  final regular = await PdfGoogleFonts.notoSansRegular()
      .timeout(const Duration(seconds: 4), onTimeout: () => pw.Font.helvetica());
  final bold = await PdfGoogleFonts.notoSansBold()
      .timeout(const Duration(seconds: 4), onTimeout: () => pw.Font.helveticaBold());

  final dateFmt = DateFormat('dd/MM/yyyy', 'fr');
  final dtFmt = DateFormat('dd/MM/yyyy HH:mm', 'fr');
  final sym = settings.currencySymbol.trim();

  String mon(double v) {
    final n = NumberFormat('#,##0.00').format(v);
    return '$sym $n';
  }

  String statusFr(String s) {
    const m = {
      'PAID': 'Payé',
      'PARTIAL': 'Partiel',
      'UNPAID': 'Impayé',
      'CANCELLED': 'Annulé',
    };
    return m[s.toUpperCase()] ?? s;
  }

  final rev = sales.fold(0.0, (s, e) => s + e.finalAmount);
  final paid = sales.fold(0.0, (s, e) => s + e.paidAmount);
  final disc = sales.fold(0.0, (s, e) => s + e.discount);
  final paidCnt = sales.where((s) => s.status == 'PAID').length;
  final partCnt = sales.where((s) => s.status == 'PARTIAL').length;
  final unpaidCnt = sales.where((s) => s.status == 'UNPAID').length;

  final periodStr = () {
    if (params.period == ReportPeriod.custom) {
      final f = params.customFrom;
      final t = params.customTo;
      if (f != null && t != null) {
        return 'Du ${dateFmt.format(f)} au ${dateFmt.format(t)}';
      }
      return 'Période personnalisée';
    }
    return params.period.label;
  }();

  // Charger le logo si disponible
  pw.MemoryImage? logoImage;
  if (settings.logoPath.isNotEmpty) {
    try {
      final logoRes = await dio
          .get<List<int>>(
            settings.logoPath.startsWith('http')
                ? settings.logoPath
                : '${dio.options.baseUrl.replaceAll(RegExp(r'/$'), '')}/${settings.logoPath.replaceAll(RegExp(r'^/'), '')}',
            options: Options(responseType: ResponseType.bytes),
          )
          .timeout(const Duration(seconds: 4));
      if (logoRes.data != null) {
        logoImage = pw.MemoryImage(Uint8List.fromList(logoRes.data!));
      }
    } catch (_) {
      // Logo non critique : on continue sans
    }
  }

  final doc = pw.Document(creator: 'POS Connect', title: 'Rapport de ventes');

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      header: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Business info (gauche)
              pw.Expanded(
                flex: 3,
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (logoImage != null) ...[
                      pw.Image(logoImage, width: 48, height: 48, fit: pw.BoxFit.contain),
                      pw.SizedBox(width: 10),
                    ],
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            settings.businessName,
                            style: pw.TextStyle(
                                font: bold,
                                fontSize: 15,
                                color: PdfColors.grey900),
                          ),
                          if (settings.address.isNotEmpty)
                            pw.Text(settings.address,
                                style: const pw.TextStyle(
                                    fontSize: 8, color: PdfColors.grey700)),
                          if (settings.phone.isNotEmpty)
                            pw.Text(settings.phone,
                                style: const pw.TextStyle(
                                    fontSize: 8, color: PdfColors.grey700)),
                          if (settings.email.isNotEmpty)
                            pw.Text(settings.email,
                                style: const pw.TextStyle(
                                    fontSize: 8, color: PdfColors.grey700)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 16),
              // Report info (droite)
              pw.Expanded(
                flex: 2,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'RAPPORT DE VENTES',
                      style: pw.TextStyle(
                          font: bold,
                          fontSize: 13,
                          color: PdfColors.blue800),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Période: $periodStr',
                      style: const pw.TextStyle(
                          fontSize: 8, color: PdfColors.grey700),
                    ),
                    if (params.userFilter != null)
                      pw.Text(
                        'Caissier: ${params.userFilter}',
                        style: const pw.TextStyle(
                            fontSize: 8, color: PdfColors.grey700),
                      ),
                    pw.Text(
                      'Généré le: ${dtFmt.format(haitiNow())}',
                      style: const pw.TextStyle(
                          fontSize: 8, color: PdfColors.grey500),
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Divider(color: PdfColors.grey400, thickness: 0.8),
          pw.SizedBox(height: 4),
        ],
      ),
      footer: (ctx) => pw.Column(
        children: [
          pw.Divider(color: PdfColors.grey300, thickness: 0.5),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                settings.receiptFooter,
                style: const pw.TextStyle(
                    fontSize: 8, color: PdfColors.grey500),
              ),
              pw.Text(
                'Page ${ctx.pageNumber} / ${ctx.pagesCount}',
                style: const pw.TextStyle(
                    fontSize: 8, color: PdfColors.grey600),
              ),
            ],
          ),
        ],
      ),
      build: (ctx) => [
        // ── KPI summary ──
        pw.Container(
          padding: const pw.EdgeInsets.all(14),
          decoration: pw.BoxDecoration(
            color: PdfColors.blue50,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'RÉSUMÉ',
                style: pw.TextStyle(
                    font: bold,
                    fontSize: 10,
                    color: PdfColors.blue900),
              ),
              pw.SizedBox(height: 10),
              pw.Row(
                children: [
                  pw.Expanded(child: _pdfKpiCell("Chiffre d'affaires", mon(rev), bold)),
                  pw.SizedBox(width: 10),
                  pw.Expanded(child: _pdfKpiCell('Encaissé', mon(paid), bold)),
                  pw.SizedBox(width: 10),
                  pw.Expanded(
                      child: _pdfKpiCell('Reste à encaisser', mon((rev - paid).clamp(0.0, double.infinity)), bold)),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Row(
                children: [
                  pw.Expanded(
                      child: _pdfKpiCell('Remises accordées', mon(disc), bold)),
                  pw.SizedBox(width: 10),
                  pw.Expanded(
                      child: _pdfKpiCell('Nombre de ventes', '${sales.length}', bold)),
                  pw.SizedBox(width: 10),
                  pw.Expanded(
                      child: _pdfKpiCell(
                          'Payé / Partiel / Impayé',
                          '$paidCnt / $partCnt / $unpaidCnt',
                          bold)),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 18),

        // ── Sales table ──
        if (sales.isNotEmpty) ...[
          pw.Text(
            'DÉTAIL DES VENTES  (${sales.length})',
            style: pw.TextStyle(
                font: bold, fontSize: 10, color: PdfColors.grey900),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.blue800),
            headerStyle: pw.TextStyle(
                font: bold, fontSize: 7, color: PdfColors.white),
            cellStyle: const pw.TextStyle(fontSize: 7),
            cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 6, vertical: 4),
            cellAlignments: {
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
              6: pw.Alignment.center,
            },
            oddRowDecoration:
                const pw.BoxDecoration(color: PdfColors.grey50),
            columnWidths: {
              0: const pw.FlexColumnWidth(1.3),
              1: const pw.FlexColumnWidth(1.5),
              2: const pw.FlexColumnWidth(1.2),
              3: const pw.FlexColumnWidth(1.2),
              4: const pw.FlexColumnWidth(1.3),
              5: const pw.FlexColumnWidth(1.2),
              6: const pw.FlexColumnWidth(0.8),
            },
            headers: [
              'Référence',
              'Date',
              'Client',
              'Caissier',
              'Total',
              'Payé',
              'Statut'
            ],
            data: sales
                .map((s) => [
                      s.reference,
                      dtFmt.format(s.createdAt),
                      s.customerName ?? 'Comptoir',
                      s.userFullName ?? '-',
                      mon(s.finalAmount),
                      mon(s.paidAmount),
                      statusFr(s.status),
                    ])
                .toList(),
          ),
        ] else ...[
          pw.Center(
            child: pw.Text(
              'Aucune vente sur cette période.',
              style: const pw.TextStyle(color: PdfColors.grey500),
            ),
          ),
        ],
      ],
    ),
  );

  final fileName =
      'rapport_ventes_${DateFormat('yyyyMMdd').format(haitiNow())}.pdf';

  if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    final bytes = await doc.save();
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Enregistrer le rapport PDF',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (savePath != null) {
      await File(savePath).writeAsBytes(bytes);
      if (Platform.isMacOS) await Process.run('open', [savePath]);
      if (Platform.isWindows) await Process.run('start', ['', savePath], runInShell: true);
      if (Platform.isLinux) await Process.run('xdg-open', [savePath]);
    }
  } else {
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: fileName,
    );
  }
}

pw.Widget _pdfKpiCell(String label, String value, pw.Font bold) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(label,
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
      pw.SizedBox(height: 2),
      pw.Text(value,
          style: pw.TextStyle(
              font: bold, fontSize: 9, color: PdfColors.grey900)),
    ],
  );
}

// ── Helpers ────────────────────────────────────────────────────────────────

String _statusLabel(String s) {
  switch (s.toUpperCase()) {
    case 'PAID':
      return 'Payé';
    case 'PARTIAL':
      return 'Partiel';
    case 'UNPAID':
      return 'Impayé';
    case 'CANCELLED':
      return 'Annulé';
    default:
      return s;
  }
}

Color _statusColor(String s) {
  switch (s.toUpperCase()) {
    case 'PAID':
      return AppColors.success;
    case 'PARTIAL':
      return AppColors.warning;
    case 'UNPAID':
      return AppColors.error;
    default:
      return AppColors.textSecondary;
  }
}

// ── KPI card ───────────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final double width;

  const _KpiCard(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color,
      this.width = 200});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 10),
          Text(value,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

// ── Date picker field ──────────────────────────────────────────────────────

class _DatePickerField extends StatelessWidget {
  final String label;
  final DateTime? date;
  final void Function(DateTime) onPicked;

  const _DatePickerField(
      {required this.label, required this.date, required this.onPicked});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? haitiNow(),
          firstDate: DateTime(2020),
          lastDate: haitiNow(),
        );
        if (picked != null) onPicked(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          suffixIcon:
              const Icon(Icons.calendar_today_rounded, size: 16),
        ),
        child: Text(
          date != null ? _dateFmt.format(date!) : 'Sélectionner',
          style: TextStyle(
              fontSize: 14,
              color: date != null
                  ? AppColors.textPrimary
                  : AppColors.textSecondary),
        ),
      ),
    );
  }
}
