import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/models/sale_model.dart';
import 'package:pos_connect/features/reports/reports_screen.dart'
    show ReportPeriod, ReportPeriodLabel, ReportParams, fetchSalesForRange, generateSalesReportPdf;
import 'package:pos_connect/providers/auth_provider.dart';
import 'package:pos_connect/providers/settings_provider.dart';
import 'package:pos_connect/shared/widgets/stat_card.dart';

/// Rapport personnel — Android uniquement. Affiche exclusivement les ventes
/// du caissier connecté (jamais celles des autres, quel que soit son rôle).
/// Le rapport complet (toutes les caisses, export CSV/PDF configurable) est
/// accessible via l'entrée "Voir plus" du tiroir de navigation (app_shell.dart),
/// pas depuis cet écran.
class MobileReportScreen extends ConsumerStatefulWidget {
  const MobileReportScreen({super.key});

  @override
  ConsumerState<MobileReportScreen> createState() => _MobileReportScreenState();
}

class _MobileReportScreenState extends ConsumerState<MobileReportScreen> {
  ReportPeriod _period = ReportPeriod.today;
  List<SaleModel>? _sales;
  bool _loading = false;
  bool _printing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final (from, to) = _period.range;
      // /api/sales/ scope déjà côté serveur : un caissier sans reports.read_all
      // ne reçoit que ses propres ventes. Un admin/manager (reports.read_all)
      // reçoit tout le tenant — comme sur le web/bureau, on ne restreint pas
      // davantage ici (sinon un admin verrait moins sur mobile que partout ailleurs).
      final all = await fetchSalesForRange(from, to);
      final user = ref.read(authProvider).user;
      final scoped = (user?.canViewAllReports ?? false)
          ? all
          : all.where((s) => s.userFullName == user?.fullName).toList();
      if (!mounted) return;
      setState(() {
        _sales = scoped;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _print() async {
    final sales = _sales;
    if (sales == null || sales.isEmpty) return;
    final settings = ref.read(settingsProvider);
    final user = ref.read(authProvider).user;
    final canViewAll = user?.canViewAllReports ?? false;
    final (from, to) = _period.range;
    setState(() => _printing = true);
    try {
      await generateSalesReportPdf(
        sales,
        ReportParams(
          period: _period,
          customFrom: from,
          customTo: to.subtract(const Duration(days: 1)),
          // null = "tous" dans l'en-tête PDF (comme sur le web quand l'admin
          // ne filtre sur personne en particulier) ; sinon son propre nom.
          userFilter: canViewAll ? null : user?.fullName,
        ),
        settings,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur lors de l'impression : $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canViewAll = ref.watch(authProvider).user?.canViewAllReports ?? false;
    final sales = _sales ?? const <SaleModel>[];
    final totalSales = sales.fold<double>(0, (s, e) => s + e.finalAmount);
    final totalDiscount = sales.fold<double>(0, (s, e) => s + e.discount);
    final count = sales.length;
    final sym = ref.watch(settingsProvider).currencySymbol.trim();
    String mon(double v) => '$sym ${v.toStringAsFixed(2)}';

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ReportPeriod.values
                  .where((p) => p != ReportPeriod.custom)
                  .map((p) => ChoiceChip(
                        label: Text(p.label),
                        selected: _period == p,
                        onSelected: (_) {
                          setState(() => _period = p);
                          _load();
                        },
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!, style: const TextStyle(color: AppColors.error)),
              )
            else ...[
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.5,
                children: [
                  StatCard(
                    label: canViewAll ? 'Ventes (tous)' : 'Mes ventes',
                    value: mon(totalSales),
                    icon: Icons.point_of_sale_rounded,
                    color: AppColors.primary,
                  ),
                  StatCard(
                    label: 'Transactions',
                    value: '$count',
                    icon: Icons.receipt_long_rounded,
                    color: AppColors.accent,
                  ),
                  StatCard(
                    label: 'Rabais accordés',
                    value: mon(totalDiscount),
                    icon: Icons.sell_outlined,
                    color: AppColors.warning,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: sales.isEmpty || _printing ? null : _print,
                  icon: _printing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.print_rounded),
                  label: Text(canViewAll ? 'Imprimer le rapport' : 'Imprimer mon rapport'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
