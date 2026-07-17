import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart' show FormData, Options, DioException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:pos_connect/core/permissions.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/shared/widgets/limit_exceeded_dialog.dart';
import 'package:pos_connect/core/responsive.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/models/product_model.dart';
import 'package:pos_connect/data/models/sale_model.dart';
import 'package:pos_connect/data/models/user_model.dart';
import 'package:pos_connect/data/repositories/sale_repository.dart';
import 'package:pos_connect/providers/customer_provider.dart';
import 'package:pos_connect/providers/draft_provider.dart';
import 'package:pos_connect/providers/permission_provider.dart';
import 'package:pos_connect/providers/pos_provider.dart';
import 'package:pos_connect/providers/product_provider.dart';
import 'package:pos_connect/providers/settings_provider.dart';
import 'package:pos_connect/services/thermal_printer_service.dart';

final _fmt =
    NumberFormat.currency(locale: 'fr_HT', symbol: 'HTG ', decimalDigits: 2);

String _fmtQty(double q) =>
    q % 1 == 0 ? q.toInt().toString() : q.toStringAsFixed(2);

// ─── Receipt dialog ──────────────────────────────────────────────────────────
class _ReceiptDialog extends ConsumerStatefulWidget {
  final String saleId;
  const _ReceiptDialog({required this.saleId});

  @override
  ConsumerState<_ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends ConsumerState<_ReceiptDialog> {
  SaleModel? _sale;
  bool _loading = true;
  bool _printing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final sale = await SaleRepository().getSale(widget.saleId);
      if (mounted) {
        setState(() { _sale = sale; _loading = false; });
        // Auto-print if configured
        final settings = ref.read(settingsProvider);
        if (settings.posAutoPrint) {
          _print();
        }
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _print() async {
    if (_sale == null) return;
    setState(() => _printing = true);
    final settings = ref.read(settingsProvider);
    try {
      await ThermalPrinterService.instance.printReceipt(
        _sale!,
        settings,
        printerUrl: settings.posPrinterName.isNotEmpty ? settings.posPrinterName : null,
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTiny = context.isTinyPhone;
    return Dialog(
      insetPadding: isTiny
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 8)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(isTiny ? 8 : 12)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isTiny ? double.infinity : 580,
          maxHeight: isTiny
              ? MediaQuery.sizeOf(context).height - 16
              : 680,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long_rounded,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Reçu de vente',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline,
                                  color: AppColors.error, size: 40),
                              const SizedBox(height: 12),
                              const Text(
                                'Erreur lors du chargement du reçu',
                                style: TextStyle(color: AppColors.error),
                              ),
                            ],
                          ),
                        )
                      : _ReceiptPreview(sale: _sale!),
            ),

            // Actions
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Fermer'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed:
                        (_loading || _printing || _sale == null) ? null : _print,
                    icon: _printing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.print_rounded, size: 16),
                    label: const Text('Imprimer'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptPreview extends StatelessWidget {
  final SaleModel sale;
  const _ReceiptPreview({required this.sale});

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd/MM/yyyy à HH:mm');
    final lbl = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    final val = const TextStyle(fontSize: 12, fontWeight: FontWeight.w500);
    final big = const TextStyle(fontSize: 14, fontWeight: FontWeight.w700);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _row('Référence', sale.reference, lbl, val),
          _row('Date', dateFmt.format(sale.createdAt), lbl, val),
          if (sale.customerName != null)
            _row('Client', sale.customerName!, lbl, val),
          if (sale.userFullName != null)
            _row('Caissier', sale.userFullName!, lbl, val),
          const Divider(height: 20),
          const Text('Articles',
              style:
                  TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 6),
          ...sale.items.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(item.productName ?? 'Produit',
                          style: const TextStyle(fontSize: 12)),
                    ),
                    Text(
                      '${_fmtQty(item.quantity)} × ${_fmt.format(item.unitPrice)}',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                    const SizedBox(width: 8),
                    Text(_fmt.format(item.subtotal),
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              )),
          const Divider(height: 20),
          if (sale.discount > 0) ...[
            _total('Sous-total', _fmt.format(sale.totalAmount), lbl, val),
            _total('Remise', '-${_fmt.format(sale.discount)}', lbl,
                const TextStyle(
                    fontSize: 12,
                    color: AppColors.warning,
                    fontWeight: FontWeight.w500)),
          ],
          _total('Total', _fmt.format(sale.finalAmount), lbl, big),
          const SizedBox(height: 4),
          _total('Montant reçu', _fmt.format(sale.paidAmount), lbl, val),
          if (sale.balance.abs() > 0.001)
            _total(
              sale.balance > 0 ? 'Reste à payer' : 'Monnaie',
              _fmt.format(sale.balance.abs()),
              lbl,
              TextStyle(
                fontSize: 12,
                color: sale.balance > 0 ? AppColors.error : AppColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(height: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
            decoration: BoxDecoration(
              color: _statusColor(sale.status).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_statusIcon(sale.status),
                    color: _statusColor(sale.status), size: 14),
                const SizedBox(width: 4),
                Text(_statusLabel(sale.status),
                    style: TextStyle(
                        color: _statusColor(sale.status),
                        fontWeight: FontWeight.w600,
                        fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, TextStyle lbl, TextStyle val) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Text('$label : ', style: lbl),
          Expanded(
              child: Text(value, style: val, overflow: TextOverflow.ellipsis)),
        ]),
      );

  Widget _total(String label, String value, TextStyle lbl, TextStyle val) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child:
            Row(children: [Text(label, style: lbl), const Spacer(), Text(value, style: val)]),
      );

  Color _statusColor(String s) => switch (s) {
        'PAID' => AppColors.accent,
        'PARTIAL' => AppColors.warning,
        'CANCELLED' => AppColors.error,
        _ => AppColors.textSecondary,
      };

  IconData _statusIcon(String s) => switch (s) {
        'PAID' => Icons.check_circle_rounded,
        'PARTIAL' => Icons.pending_rounded,
        'CANCELLED' => Icons.cancel_rounded,
        _ => Icons.hourglass_empty_rounded,
      };

  String _statusLabel(String s) => switch (s) {
        'PAID' => 'Payé',
        'PARTIAL' => 'Paiement partiel',
        'CANCELLED' => 'Annulée',
        _ => 'Non payé',
      };
}

// ─── Drafts bottom sheet ─────────────────────────────────────────────────────
class _DraftsBottomSheet extends ConsumerWidget {
  final VoidCallback? onDraftLoaded;
  const _DraftsBottomSheet({this.onDraftLoaded});

  void _load(BuildContext context, WidgetRef ref, DraftCart draft) {
    void doLoad() {
      ref.read(posProvider.notifier).loadDraft(draft);
      ref.read(draftsProvider.notifier).removeDraft(draft.id);
      Navigator.of(context).pop();
      onDraftLoaded?.call();
    }

    if (ref.read(posProvider).items.isEmpty) {
      doLoad();
      return;
    }

    showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('Remplacer le panier ?'),
        content: const Text('Le panier actuel sera vidé. Continuer ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dlgCtx).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dlgCtx).pop();
              doLoad();
            },
            child: const Text('Remplacer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drafts = ref.watch(draftsProvider);
    final timeFmt = DateFormat('HH:mm');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              const Icon(Icons.pause_circle_outline_rounded,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Ventes en attente (${drafts.length})',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (drafts.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Text('Aucune vente en attente',
                style: TextStyle(color: AppColors.textSecondary)),
          )
        else
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: drafts.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final draft = drafts[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        AppColors.primary.withValues(alpha: 0.1),
                    child: Text(
                      '${draft.itemCount}',
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13),
                    ),
                  ),
                  title: Text(draft.label,
                      style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                    '${timeFmt.format(draft.savedAt)} — ${_fmt.format(draft.total)}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => _load(ctx, ref, draft),
                        style: TextButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 0)),
                        child: const Text('Charger',
                            style: TextStyle(fontSize: 12)),
                      ),
                      IconButton(
                        onPressed: () => ref
                            .read(draftsProvider.notifier)
                            .removeDraft(draft.id),
                        icon: const Icon(Icons.delete_outline_rounded,
                            size: 18, color: AppColors.error),
                        tooltip: 'Supprimer',
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(8),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}

// ─── Root screen ──────────────────────────────────────────────────────────────
class PosScreen extends ConsumerWidget {
  const PosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    if (isWide) return const _DesktopPos();
    return const _MobilePos();
  }
}

// ─── Desktop layout ───────────────────────────────────────────────────────────
class _DesktopPos extends StatelessWidget {
  const _DesktopPos();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(flex: 3, child: _ProductPanel()),
        Container(
          width: 360,
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(left: BorderSide(color: AppColors.divider)),
          ),
          child: const _CartPanel(),
        ),
      ],
    );
  }
}

// ─── Mobile layout ────────────────────────────────────────────────────────────
class _MobilePos extends ConsumerStatefulWidget {
  const _MobilePos();

  @override
  ConsumerState<_MobilePos> createState() => _MobilePosState();
}

class _MobilePosState extends ConsumerState<_MobilePos>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cartCount =
        ref.watch(posProvider).items.fold(0.0, (s, i) => s + i.quantity);

    return Column(
      children: [
        Container(
          color: AppColors.surface,
          child: TabBar(
            controller: _tabs,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            tabs: [
              const Tab(text: 'Produits'),
              Tab(text: 'Panier ($cartCount)'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: const [_ProductPanel(), _CartPanel()],
          ),
        ),
      ],
    );
  }
}

// ─── Product panel ─────────────────────────────────────────────────────────
class _ProductPanel extends ConsumerStatefulWidget {
  const _ProductPanel();

  @override
  ConsumerState<_ProductPanel> createState() => _ProductPanelState();
}

class _ProductPanelState extends ConsumerState<_ProductPanel> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(posProductsProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              hintText: 'Rechercher un produit (nom ou code-barres)...',
              prefixIcon: Icon(Icons.search_rounded),
              border: OutlineInputBorder(),
            ),
            onChanged: (v) =>
                ref.read(posProductSearchProvider.notifier).state = v,
          ),
        ),
        Expanded(
          child: productsAsync.when(
            data: (products) {
              if (products.data.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off_rounded,
                          size: 48, color: AppColors.textSecondary),
                      SizedBox(height: 12),
                      Text('Aucun produit trouvé',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                );
              }
              // Mobile: 2 colonnes fixes (maxCrossAxisExtent cause 3 colonnes sur ~390dp)
              final delegate = context.isMobile
                  ? const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.85,
                    )
                  : const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 200,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.85,
                    );
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                gridDelegate: delegate,
                itemCount: products.data.length,
                itemBuilder: (context, i) =>
                    _ProductCard(product: products.data[i]),
              );
            },
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text('Erreur: $e',
                  style: const TextStyle(color: AppColors.error)),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProductCard extends ConsumerWidget {
  final ProductModel product;
  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inCart = ref
        .watch(posProvider)
        .items
        .any((i) => i.product.id == product.id);

    return GestureDetector(
      onTap: () => ref.read(posProvider.notifier).addProduct(product),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: inCart ? AppColors.primary : AppColors.divider,
            width: inCart ? 2 : 1,
          ),
          boxShadow: [
            if (inCart)
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(10)),
              child: SizedBox(
                height: 80,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (product.imageUrl != null && product.imageUrl!.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: '${dio.options.baseUrl}${product.imageUrl}',
                        fit: BoxFit.cover,
                        placeholder: (_, __) => _ProductCardPlaceholder(product: product),
                        errorWidget: (_, __, ___) => _ProductCardPlaceholder(product: product),
                      )
                    else
                      _ProductCardPlaceholder(product: product),
                    if (inCart)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check,
                              color: Colors.white, size: 12),
                        ),
                      ),
                    if (product.isLowStock)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('Stock bas',
                              style: TextStyle(
                                  color: Colors.white, fontSize: 9)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _fmt.format(product.salePrice),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductCardPlaceholder extends StatelessWidget {
  final ProductModel product;
  const _ProductCardPlaceholder({required this.product});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: (product.isLowStock ? AppColors.warning : AppColors.primary)
          .withValues(alpha: 0.08),
      child: Center(
        child: Icon(
          Icons.inventory_2_rounded,
          size: 36,
          color: product.isLowStock ? AppColors.warning : AppColors.primary,
        ),
      ),
    );
  }
}

// ─── Cart panel ───────────────────────────────────────────────────────────────
class _CartPanel extends ConsumerStatefulWidget {
  const _CartPanel();

  @override
  ConsumerState<_CartPanel> createState() => _CartPanelState();
}

class _CartPanelState extends ConsumerState<_CartPanel> {
  final _discountCtrl = TextEditingController(text: '0');
  final _paidCtrl = TextEditingController(text: '0');
  bool _discountUnlocked = false;

  // ── Session caisse ────────────────────────────────────────────────────────
  Map<String, dynamic>? _session;   // null = pas encore chargé
  bool _sessionChecked = false;
  bool _noSessionPermission = false; // true si 403 sur sessions.open
  String? _deviceId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initSession());
  }

  Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('pos_device_id');
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString('pos_device_id', id);
    }
    return id;
  }

  Future<void> _initSession() async {
    _deviceId = await _getDeviceId();
    try {
      final res = await dio.get('/api/sessions/current', queryParameters: {'device_id': _deviceId});
      final session = res.data['session'];
      if (mounted) {
        setState(() {
          _session = session as Map<String, dynamic>?;
          _sessionChecked = true;
        });
        if (_session == null && mounted) {
          _promptOpenSession();
        }
      }
    } catch (e) {
      if (mounted) {
        final is4xx = e is DioException &&
            ((e.response?.statusCode ?? 0) == 401 ||
             (e.response?.statusCode ?? 0) == 403);
        setState(() {
          _sessionChecked = true;
          _noSessionPermission = is4xx;
        });
        if (!is4xx) _promptOpenSession();
      }
    }
  }

  void _promptOpenSession() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _OpenSessionDialog(
        deviceId: _deviceId!,
        onOpened: (session) {
          if (mounted) setState(() => _session = session);
        },
        onCancelled: () {
          if (mounted) context.go('/dashboard');
        },
      ),
    );
  }

  void _showCloseSession() {
    if (_session == null) return;
    showDialog(
      context: context,
      builder: (_) => _CloseSessionDialog(
        session: _session!,
        onClosed: () {
          if (mounted) setState(() => _session = null);
          _promptOpenSession();
        },
      ),
    );
  }

  @override
  void dispose() {
    _discountCtrl.dispose();
    _paidCtrl.dispose();
    super.dispose();
  }

  void _resetFields() {
    _discountCtrl.text = '0';
    _paidCtrl.text = '0';
    setState(() => _discountUnlocked = false);
  }

  Future<void> _requestDiscountAuth(BuildContext context, PosNotifier notifier) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _SupervisorAuthDialog(),
    );
    if (ok == true && mounted) setState(() => _discountUnlocked = true);
  }

  void _syncFields(PosState pos) {
    final disc = pos.discount > 0 ? pos.discount.toStringAsFixed(2) : '0';
    if (_discountCtrl.text != disc) _discountCtrl.text = disc;
    if (_paidCtrl.text != '0') _paidCtrl.text = '0';
  }

  void _saveAsDraft() {
    final pos = ref.read(posProvider);
    if (pos.items.isEmpty) return;

    String? customerName;
    ref.read(customersProvider).whenData((c) {
      customerName = c.data
          .where((x) => x.id == pos.customerId)
          .map((x) => x.name)
          .firstOrNull;
    });

    ref.read(draftsProvider.notifier).saveDraft(
          items: pos.items
              .map((i) => DraftItem(
                    productId: i.product.id,
                    productName: i.product.name,
                    salePrice: i.product.salePrice,
                    customPrice: i.isPriceModified ? i.unitPrice : null,
                    quantity: i.quantity,
                  ))
              .toList(),
          discount: pos.discount,
          paymentMethod: pos.paymentMethod,
          customerId: pos.customerId,
          customerName: customerName,
        );

    ref.read(posProvider.notifier).clearCart();
    _resetFields();

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Panier mis en attente'),
      duration: Duration(seconds: 2),
    ));
  }

  void _showDrafts() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxHeight: 520),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _DraftsBottomSheet(
        onDraftLoaded: () {
          if (mounted) _syncFields(ref.read(posProvider));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pos = ref.watch(posProvider);
    final notifier = ref.read(posProvider.notifier);
    final drafts = ref.watch(draftsProvider);
    final isEdit = pos.isEditMode;
    final canDiscount = ref.watch(hasPermissionProvider(Perm.salesDiscount));

    return LayoutBuilder(
      builder: (context, constraints) {
        // Réserve au minimum 100dp pour la zone panier (empty state = 100dp)
        final paymentMaxH = (constraints.maxHeight - 48 - 100).clamp(150.0, 500.0);
        return _buildCart(context, pos, notifier, drafts, isEdit, paymentMaxH, canDiscount);
      },
    );
  }

  Widget _buildCart(BuildContext context, PosState pos, PosNotifier notifier,
      List<DraftCart> drafts, bool isEdit, double paymentMaxH, bool canDiscount) {
    return Column(
      children: [
        // ── Edit mode banner ──────────────────────────────────────────
        if (isEdit)
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: AppColors.info.withValues(alpha: 0.12),
            child: Row(
              children: [
                const Icon(Icons.edit_note_rounded,
                    color: AppColors.info, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Modification — ${pos.editingSale!.reference}',
                    style: const TextStyle(
                        color: AppColors.info,
                        fontWeight: FontWeight.w600,
                        fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

        // ── Session banner ────────────────────────────────────────────
        if (!_sessionChecked)
          const LinearProgressIndicator(minHeight: 2)
        else if (_session != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            color: AppColors.accent.withValues(alpha: 0.10),
            child: Row(
              children: [
                const Icon(Icons.point_of_sale_rounded,
                    color: AppColors.accent, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Session ouverte — Fond: ${_fmt.format((_session!['opening_balance'] as num?)?.toDouble() ?? 0)}',
                    style: const TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w500,
                        fontSize: 11),
                  ),
                ),
                InkWell(
                  onTap: _showCloseSession,
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text('Fermer caisse',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.accent,
                            decoration: TextDecoration.underline,
                            decorationColor: AppColors.accent)),
                  ),
                ),
              ],
            ),
          )
        else
          // Session absente après vérification — bloquer visuellement
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            color: AppColors.error.withValues(alpha: 0.08),
            child: Row(
              children: [
                Icon(
                  _noSessionPermission
                      ? Icons.no_accounts_rounded
                      : Icons.lock_rounded,
                  color: AppColors.error,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _noSessionPermission
                        ? 'Votre rôle ne permet pas d\'ouvrir une session caisse'
                        : 'Caisse non ouverte — les encaissements sont désactivés',
                    style: const TextStyle(
                        color: AppColors.error,
                        fontWeight: FontWeight.w500,
                        fontSize: 11),
                  ),
                ),
                if (!_noSessionPermission)
                  TextButton(
                    onPressed: _promptOpenSession,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: AppColors.error,
                      textStyle: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    child: const Text('Ouvrir la caisse'),
                  ),
              ],
            ),
          ),

        // ── Header ────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.divider)),
          ),
          child: Row(
            children: [
              Icon(
                isEdit
                    ? Icons.edit_rounded
                    : Icons.shopping_cart_rounded,
                color: isEdit ? AppColors.info : AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                isEdit
                    ? 'Articles (${pos.items.length})'
                    : 'Panier (${pos.items.length} article${pos.items.length != 1 ? 's' : ''})',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const Spacer(),
              // Drafts indicator — hidden in edit mode
              if (!isEdit && drafts.isNotEmpty)
                Tooltip(
                  message: 'Ventes en attente',
                  child: InkWell(
                    onTap: _showDrafts,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Badge(
                            label: Text('${drafts.length}',
                                style: const TextStyle(fontSize: 9)),
                            child: const Icon(
                                Icons.pause_circle_outline_rounded,
                                size: 18,
                                color: AppColors.warning),
                          ),
                          const SizedBox(width: 4),
                          const Text('En attente',
                              style: TextStyle(
                                  fontSize: 11, color: AppColors.warning)),
                        ],
                      ),
                    ),
                  ),
                ),
              if (pos.items.isNotEmpty) ...[
                const SizedBox(width: 4),
                if (!isEdit)
                  TextButton(
                    onPressed: _saveAsDraft,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 0),
                    ),
                    child: const Text('Attendre',
                        style: TextStyle(fontSize: 12)),
                  ),
                if (!isEdit) const SizedBox(width: 4),
                TextButton(
                  onPressed: notifier.clearCart,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.error,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 0),
                  ),
                  child: Text(isEdit ? 'Annuler' : 'Vider',
                      style: const TextStyle(fontSize: 13)),
                ),
              ],
            ],
          ),
        ),

        // ── Cart items ─────────────────────────────────────────────────
        Expanded(
          child: pos.items.isEmpty
              ? LayoutBuilder(
                  builder: (context, c) {
                    final compact = c.maxHeight < 110;
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_shopping_cart_rounded,
                              size: compact ? 32 : 48,
                              color: AppColors.textSecondary),
                          SizedBox(height: compact ? 6 : 12),
                          Text(
                            'Cliquez sur un produit\npour l\'ajouter',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: compact ? 12 : 14,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: pos.items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) => _CartItemTile(
                    item: pos.items[i],
                    notifier: notifier,
                  ),
                ),
        ),

        // ── Payment summary — scrollable si trop grand sur petit écran ──
        LimitedBox(
          maxHeight: paymentMaxH,
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Container(
          padding: const EdgeInsets.all(14),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.divider)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CustomerDropdown(),
              const SizedBox(height: 12),

              // Remise caisse
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Text('Remise caisse (HTG)',
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 13)),
                        if (!canDiscount && !_discountUnlocked) ...[
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => _requestDiscountAuth(context, notifier),
                            child: const Tooltip(
                              message: 'Autorisation requise',
                              child: Icon(Icons.lock_rounded,
                                  size: 14, color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: _discountCtrl,
                      enabled: canDiscount || _discountUnlocked,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        isDense: true,
                      ),
                      onChanged: (v) =>
                          notifier.setDiscount(double.tryParse(v) ?? 0),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Totals
              _TotalRow('Sous-total', _fmt.format(pos.subtotal)),
              if (pos.itemsDiscount > 0)
                _TotalRow(
                  'Remises articles',
                  '-${_fmt.format(pos.itemsDiscount)}',
                  color: AppColors.warning,
                ),
              if (pos.discount > 0)
                _TotalRow(
                  'Remise caisse',
                  '-${_fmt.format(pos.discount)}',
                  color: AppColors.error,
                ),
              const Divider(height: 16),
              _TotalRow('Total', _fmt.format(pos.total), bold: true),
              const SizedBox(height: 12),

              // Payment method
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Paiement :',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      ('CASH', Icons.payments_rounded),
                      ('CARD', Icons.credit_card_rounded),
                      ('BANK', Icons.account_balance_rounded),
                      ('MOBILE', Icons.phone_android_rounded),
                    ]
                        .map((m) => ChoiceChip(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(m.$2, size: 14),
                                  const SizedBox(width: 4),
                                  Text(m.$1,
                                      style:
                                          const TextStyle(fontSize: 11)),
                                ],
                              ),
                              selected: pos.paymentMethod == m.$1,
                              selectedColor: AppColors.primary
                                  .withValues(alpha: 0.15),
                              onSelected: (_) =>
                                  notifier.setPaymentMethod(m.$1),
                            ))
                        .toList(),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // ── Payment section: new sale vs edit mode ────────────────
              if (isEdit) ...[
                // Show original paid (non-editable)
                _TotalRow(
                  'Déjà payé',
                  _fmt.format(pos.editingSale!.paidAmount),
                  color: AppColors.accent,
                ),
                const SizedBox(height: 8),
                // Difference summary
                Builder(builder: (_) {
                  final diff = pos.total - pos.editingSale!.paidAmount;
                  if (diff < 0) {
                    return _TotalRow(
                      'Monnaie à rendre',
                      _fmt.format(diff.abs()),
                      color: AppColors.accent,
                      bold: true,
                    );
                  } else if (diff > 0) {
                    return _TotalRow(
                      'Supplément dû',
                      _fmt.format(diff),
                      color: AppColors.warning,
                      bold: true,
                    );
                  }
                  return const SizedBox.shrink();
                }),
                const SizedBox(height: 8),
                // Additional payment field (only when new total > original paid)
                if (pos.total > pos.editingSale!.paidAmount) ...[
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Paiement reçu (HTG)',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13)),
                      ),
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: _paidCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            isDense: true,
                          ),
                          onChanged: (v) =>
                              notifier.setPaidAmount(double.tryParse(v) ?? 0),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        final diff = pos.total - pos.editingSale!.paidAmount;
                        notifier.setPaidAmount(diff > 0 ? diff : 0);
                        _paidCtrl.text =
                            (diff > 0 ? diff : 0).toStringAsFixed(2);
                      },
                      style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 0)),
                      child: const Text('Paiement complet',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  // Crédit si paiement insuffisant
                  Builder(builder: (_) {
                    final diff = pos.total - pos.editingSale!.paidAmount;
                    final credit = diff - pos.paidAmount;
                    if (credit > 0.005) {
                      return _TotalRow(
                        'Crédit (solde restant)',
                        _fmt.format(credit),
                        color: AppColors.error,
                      );
                    }
                    if (pos.paidAmount > diff + 0.005) {
                      return _TotalRow(
                        'Monnaie à rendre',
                        _fmt.format(pos.paidAmount - diff),
                        color: AppColors.accent,
                      );
                    }
                    return const SizedBox.shrink();
                  }),
                ],
              ] else ...[
                // ── New sale payment section ───────────────────────────
                Row(
                  children: [
                    const Expanded(
                      child: Text('Montant reçu (HTG)',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 13)),
                    ),
                    SizedBox(
                      width: 120,
                      child: TextField(
                        controller: _paidCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          isDense: true,
                        ),
                        onChanged: (v) =>
                            notifier.setPaidAmount(double.tryParse(v) ?? 0),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      notifier.payFull();
                      _paidCtrl.text = pos.total.toStringAsFixed(2);
                    },
                    style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0)),
                    child: const Text('Paiement complet',
                        style: TextStyle(fontSize: 12)),
                  ),
                ),
                if (pos.paidAmount > 0)
                  _TotalRow(
                    pos.balance > 0 ? 'Reste à payer' : 'Monnaie',
                    _fmt.format(pos.balance.abs()),
                    color: pos.balance > 0
                        ? AppColors.error
                        : AppColors.accent,
                  ),
              ],
              const SizedBox(height: 16),

              // Error
              if (pos.error != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(pos.error!,
                      style: const TextStyle(
                          color: AppColors.error, fontSize: 13)),
                ),
                const SizedBox(height: 10),
              ],

              // Checkout / Modify button
              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  style: isEdit
                      ? ElevatedButton.styleFrom(
                          backgroundColor: AppColors.info,
                          foregroundColor: Colors.white,
                        )
                      : null,
                  onPressed: (pos.items.isEmpty || pos.isProcessing || (_sessionChecked && (_session == null || _noSessionPermission)))
                      ? null
                      : () async {
                          if (isEdit) {
                            final saleId = await notifier.modifySale();
                            if (!context.mounted) return;
                            if (saleId != null) {
                              _resetFields();
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(const SnackBar(
                                content: Text('Vente modifiée avec succès'),
                                backgroundColor: AppColors.success,
                              ));
                            }
                            return;
                          }

                          // Crédit → client obligatoire
                          if ((pos.total - pos.paidAmount) > 0.005 &&
                              pos.customerId == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Sélectionnez un client pour une vente à crédit.'),
                                backgroundColor: AppColors.error,
                                duration: Duration(seconds: 3),
                              ),
                            );
                            return;
                          }

                          // New sale — CARD requires approval code
                          String? approvalCode;
                          if (pos.paymentMethod == 'CARD') {
                            approvalCode = await showDialog<String>(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => const _CardApprovalDialog(),
                            );
                            if (approvalCode == null) return;
                            if (!context.mounted) return;
                          }

                          final saleId = await notifier.checkout(
                              approvalCode: approvalCode);
                          if (!context.mounted || saleId == null) return;
                          await showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => _ReceiptDialog(saleId: saleId),
                          );
                          if (!context.mounted) return;
                          notifier.clearCart();
                          _resetFields();
                        },
                  icon: pos.isProcessing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : Icon(isEdit
                          ? Icons.check_rounded
                          : Icons.check_circle_rounded),
                  label: Text(pos.isProcessing
                      ? 'Traitement...'
                      : isEdit
                          ? 'Modifier la vente'
                          : 'Encaisser ${_fmt.format(pos.paidAmount)}'),
                ),
              ),
            ],
          ),
            ),   // Container
          ),     // SingleChildScrollView
        ),       // LimitedBox
      ],
    );
  }
}

// ─── Cart item tile ───────────────────────────────────────────────────────────
class _CartItemTile extends StatelessWidget {
  final CartItem item;
  final PosNotifier notifier;

  const _CartItemTile({required this.item, required this.notifier});

  void _editPrice(BuildContext context) {
    final ctrl =
        TextEditingController(text: item.unitPrice.toStringAsFixed(2));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.product.name, style: const TextStyle(fontSize: 15)),
        content: TextFormField(
          controller: ctrl,
          autofocus: true,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Prix unitaire (HTG)',
            prefixIcon: Icon(Icons.sell_outlined),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final val = double.tryParse(ctrl.text);
              if (val != null && val > 0) {
                notifier.updateItemPrice(item.product.id, val);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Appliquer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.product.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: () => _editPrice(context),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (item.isPriceModified) ...[
                        Text(
                          _fmt.format(item.product.salePrice),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 10,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        _fmt.format(item.unitPrice),
                        style: TextStyle(
                          color: item.isPriceModified
                              ? AppColors.warning
                              : AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: item.isPriceModified
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(
                        Icons.edit_rounded,
                        size: 10,
                        color: item.isPriceModified
                            ? AppColors.warning
                            : AppColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _fmt.format(item.subtotal),
            style:
                const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.divider),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _QtyBtn(
                  icon: Icons.remove,
                  onTap: () => notifier.updateQuantity(
                      item.product.id, item.quantity - 1),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(_fmtQty(item.quantity),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                ),
                _QtyBtn(
                  icon: Icons.add,
                  onTap: () => notifier.updateQuantity(
                      item.product.id, item.quantity + 1),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => notifier.removeItem(item.product.id),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: AppColors.error.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _QtyBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 14, color: AppColors.textPrimary),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? color;

  const _TotalRow(this.label, this.value, {this.bold = false, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(
                fontSize: 13,
                color: color ?? AppColors.textSecondary,
                fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
              )),
          const Spacer(),
          Text(value,
              style: TextStyle(
                fontSize: bold ? 16 : 13,
                color: color ?? AppColors.textPrimary,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              )),
        ],
      ),
    );
  }
}

class _CustomerDropdown extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customersAsync = ref.watch(customersProvider);
    final selectedId = ref.watch(posProvider).customerId;

    return customersAsync.when(
      data: (customers) => DropdownButtonFormField<String>(
        key: ValueKey(selectedId),
        initialValue: selectedId,
        decoration: const InputDecoration(
          labelText: 'Client (optionnel)',
          prefixIcon: Icon(Icons.person_outline, size: 20),
          isDense: true,
        ),
        items: [
          const DropdownMenuItem(
              value: null, child: Text('Client comptoir')),
          ...customers.data.map((c) => DropdownMenuItem(
                value: c.id,
                child:
                    Text(c.name, overflow: TextOverflow.ellipsis),
              )),
        ],
        onChanged: (v) => ref.read(posProvider.notifier).setCustomer(v),
      ),
      loading: () => const LinearProgressIndicator(),
      error: (e, s) => const SizedBox.shrink(),
    );
  }
}

// ── Card approval dialog ───────────────────────────────────────────────────

class _CardApprovalDialog extends StatefulWidget {
  const _CardApprovalDialog();

  @override
  State<_CardApprovalDialog> createState() => _CardApprovalDialogState();
}

class _CardApprovalDialogState extends State<_CardApprovalDialog> {

  final _ctrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _confirm() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, _ctrl.text.trim().toUpperCase());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.credit_card_rounded,
              color: AppColors.primary, size: 22),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text('Paiement par carte',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ]),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Instructions
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.info.withValues(alpha: 0.3)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.info_outline_rounded,
                        size: 15, color: AppColors.info),
                    SizedBox(width: 6),
                    Text('Procédure',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: AppColors.info)),
                  ]),
                  SizedBox(height: 6),
                  Text('1. Insérez ou approchez la carte sur le terminal.',
                      style: TextStyle(fontSize: 12)),
                  SizedBox(height: 2),
                  Text('2. Attendez la confirmation du terminal.',
                      style: TextStyle(fontSize: 12)),
                  SizedBox(height: 2),
                  Text(
                      '3. Saisissez le code d\'approbation affiché.',
                      style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Approval code field
            TextFormField(
              controller: _ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Code d\'approbation *',
                hintText: 'Ex: 123456 ou AB1234',
                prefixIcon: Icon(Icons.pin_rounded),
                isDense: true,
                helperText:
                    'Visible sur le reçu du terminal après approbation',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Le code d\'approbation est obligatoire';
                }
                if (v.trim().length < 4) {
                  return 'Code trop court (min 4 caractères)';
                }
                return null;
              },
              onFieldSubmitted: (_) => _confirm(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: _confirm,
          icon: const Icon(Icons.check_rounded, size: 16),
          label: const Text('Confirmer le paiement'),
        ),
      ],
    );
  }
}

// ── Supervisor authorization dialog ───────────────────────────────────────────

class _SupervisorAuthDialog extends StatefulWidget {
  const _SupervisorAuthDialog();

  @override
  State<_SupervisorAuthDialog> createState() => _SupervisorAuthDialogState();
}

class _SupervisorAuthDialogState extends State<_SupervisorAuthDialog> {
  final _formKey = GlobalKey<FormState>();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });

    try {
      final response = await dio.post(
        '/api/auth/login',
        data: FormData.fromMap({
          'username': _userCtrl.text.trim(),
          'password': _passCtrl.text,
        }),
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );

      final token = AuthToken.fromJson(response.data as Map<String, dynamic>);
      if (token.user == null) {
        setState(() { _loading = false; _error = 'Réponse invalide du serveur.'; });
        return;
      }

      final supervisor = UserModel.fromJson(token.user!);
      if (supervisor.hasPermission(Perm.salesDiscount)) {
        if (mounted) Navigator.pop(context, true);
      } else {
        setState(() {
          _loading = false;
          _error = "Cet utilisateur n'a pas la permission d'accorder des remises.";
        });
      }
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      setState(() {
        _loading = false;
        _error = status == 401
            ? 'Identifiants incorrects.'
            : 'Erreur de connexion. Réessayez.';
      });
    } catch (_) {
      setState(() { _loading = false; _error = 'Erreur inattendue. Réessayez.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.lock_open_rounded,
              color: AppColors.warning, size: 20),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text('Autorisation superviseur',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ]),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Un superviseur doit s\'authentifier pour autoriser cette remise.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _userCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nom d\'utilisateur',
                prefixIcon: Icon(Icons.person_outline, size: 20),
                isDense: true,
              ),
              validator: (v) => v == null || v.trim().isEmpty ? 'Requis' : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Mot de passe',
                prefixIcon: const Icon(Icons.lock_outline, size: 20),
                isDense: true,
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                      size: 18),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) => v == null || v.isEmpty ? 'Requis' : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!,
                    style:
                        const TextStyle(color: AppColors.error, fontSize: 13)),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child:
                      CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Autoriser'),
        ),
      ],
    );
  }
}

// ─── Open session dialog ──────────────────────────────────────────────────────
class _OpenSessionDialog extends StatefulWidget {
  final String deviceId;
  final void Function(Map<String, dynamic> session) onOpened;
  final VoidCallback? onCancelled;
  const _OpenSessionDialog({required this.deviceId, required this.onOpened, this.onCancelled});

  @override
  State<_OpenSessionDialog> createState() => _OpenSessionDialogState();
}

class _OpenSessionDialogState extends State<_OpenSessionDialog> {
  final _balanceCtrl = TextEditingController(text: '0');
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _balanceCtrl.dispose();
    super.dispose();
  }

  Future<void> _open({bool force = false}) async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await dio.post('/api/sessions/open', data: {
        'device_id': widget.deviceId,
        'register_name': 'Caisse',
        'opening_balance': double.tryParse(_balanceCtrl.text) ?? 0,
        'force': force,
      });
      final session = res.data['session'] as Map<String, dynamic>;
      widget.onOpened(session);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      // 402 = new device exceeds caisse limit → warn and let user confirm
      final confirmed = await handleLimitExceeded(context, e);
      if (!mounted) return;
      if (confirmed) { _open(force: true); return; }
      setState(() {
        _loading = false;
        _error = e is DioException
            ? (e.response?.data['detail'] ?? e.response?.data['message'] ?? 'Erreur réseau')
            : e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.point_of_sale_rounded,
              color: AppColors.accent, size: 20),
        ),
        const SizedBox(width: 12),
        const Text('Ouvrir la caisse',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Saisissez le fond de caisse (espèces disponibles au démarrage).',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _balanceCtrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Fond de caisse (HTG)',
              prefixIcon: Icon(Icons.payments_outlined, size: 20),
              isDense: true,
            ),
            onSubmitted: (_) => _open(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ],
        ],
      ),
      actions: [
        if (widget.onCancelled != null)
          TextButton(
            onPressed: _loading ? null : () {
              Navigator.of(context).pop();
              widget.onCancelled!();
            },
            child: const Text('Annuler'),
          ),
        FilledButton(
          onPressed: _loading ? null : _open,
          child: _loading
              ? const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Ouvrir la caisse'),
        ),
      ],
    );
  }
}

// ─── Close session dialog ─────────────────────────────────────────────────────
class _CloseSessionDialog extends StatefulWidget {
  final Map<String, dynamic> session;
  final VoidCallback onClosed;
  const _CloseSessionDialog({required this.session, required this.onClosed});

  @override
  State<_CloseSessionDialog> createState() => _CloseSessionDialogState();
}

class _CloseSessionDialogState extends State<_CloseSessionDialog> {
  late final TextEditingController _balanceCtrl;
  bool _loading   = false;
  bool _loadingSummary = true;
  String? _error;

  // Reconciliation data from server
  double _opening  = 0;
  double _cash     = 0;
  double _card     = 0;
  double _mobile   = 0;
  double _bank     = 0;
  double _refunds  = 0;
  double _expected = 0;

  @override
  void initState() {
    super.initState();
    _opening = (widget.session['opening_balance'] as num?)?.toDouble() ?? 0;
    _balanceCtrl = TextEditingController();  // vide — le caissier doit compter
    _balanceCtrl.addListener(() => setState(() {}));
    _fetchSummary();
  }

  @override
  void dispose() {
    _balanceCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchSummary() async {
    try {
      final sessionId = widget.session['id'] as String;
      final res = await dio.get('/api/sessions/$sessionId/summary');
      final d = res.data as Map<String, dynamic>;
      setState(() {
        _opening  = (d['opening_balance']          as num?)?.toDouble() ?? _opening;
        _cash     = (d['total_cash_sales']          as num?)?.toDouble() ?? 0;
        _card     = (d['total_card_sales']          as num?)?.toDouble() ?? 0;
        _mobile   = (d['total_mobile_sales']        as num?)?.toDouble() ?? 0;
        _bank     = (d['total_bank_sales']          as num?)?.toDouble() ?? 0;
        _refunds  = (d['total_refunds_cash']        as num?)?.toDouble() ?? 0;
        _expected = (d['expected_closing_balance']  as num?)?.toDouble() ?? _opening;
        // Ne pas pré-remplir le solde réel — le caissier doit compter
        _loadingSummary = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingSummary = false);
    }
  }

  Future<void> _close() async {
    setState(() { _loading = true; _error = null; });
    try {
      final sessionId = widget.session['id'] as String;
      await dio.post('/api/sessions/$sessionId/close', data: {
        'closing_balance': double.tryParse(_balanceCtrl.text) ?? 0,
      });
      widget.onClosed();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e is DioException
            ? (e.response?.data['detail'] ?? e.response?.data['message'] ?? 'Erreur réseau')
            : e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final openedAt = widget.session['opened_at'] != null
        ? DateFormat('HH:mm').format(
            DateTime.tryParse(widget.session['opened_at'].toString()) ?? DateTime.now())
        : '—';

    final closing  = double.tryParse(_balanceCtrl.text) ?? 0;
    final diff     = closing - _expected;
    final diffColor = diff == 0
        ? AppColors.success
        : diff > 0 ? const Color(0xFF2196F3) : AppColors.error;
    final diffLabel = diff > 0
        ? '+${_fmt.format(diff)} (surplus)'
        : diff < 0
            ? '${_fmt.format(diff)} (manque)'
            : 'Équilibré';

    return AlertDialog(
      title: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.lock_rounded, color: AppColors.error, size: 20),
        ),
        const SizedBox(width: 12),
        const Text('Fermer la caisse',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      ]),
      content: SizedBox(
        width: 360,
        child: _loadingSummary
            ? const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator()))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow('Ouverte à', openedAt),
                  const Divider(height: 20),

                  // ── Ventilation des encaissements ───────────────────
                  const Text('Encaissements de la session',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  _InfoRow('Fond initial',  _fmt.format(_opening)),
                  if (_cash   > 0) _InfoRow('Ventes cash',   '+ ${_fmt.format(_cash)}',   color: AppColors.success),
                  if (_card   > 0) _InfoRow('Ventes carte',  '+ ${_fmt.format(_card)}',   color: AppColors.success),
                  if (_mobile > 0) _InfoRow('Ventes mobile', '+ ${_fmt.format(_mobile)}', color: AppColors.success),
                  if (_bank   > 0) _InfoRow('Ventes banque', '+ ${_fmt.format(_bank)}',   color: AppColors.success),
                  if (_refunds > 0) _InfoRow('Remboursements cash', '- ${_fmt.format(_refunds)}',
                      color: AppColors.error),
                  const Divider(height: 16),
                  _InfoRow('Solde théorique', _fmt.format(_expected),
                      bold: true),
                  const SizedBox(height: 16),

                  // ── Solde réel ──────────────────────────────────────
                  TextField(
                    controller: _balanceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Solde réel en caisse *',
                      hintText: 'Comptez et saisissez le montant',
                      prefixIcon: Icon(Icons.payments_outlined, size: 20),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Écart ───────────────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: diffColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: diffColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      Icon(diff == 0 ? Icons.check_circle_outline
                          : diff > 0 ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                          color: diffColor, size: 16),
                      const SizedBox(width: 8),
                      Text('Écart : $diffLabel',
                          style: TextStyle(color: diffColor,
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ]),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: const TextStyle(
                        color: AppColors.error, fontSize: 13)),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: (_loading || _loadingSummary || _balanceCtrl.text.trim().isEmpty) ? null : _close,
          child: _loading
              ? const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Fermer la caisse'),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final bool bold;
  const _InfoRow(this.label, this.value, {this.color, this.bold = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: color ?? AppColors.textSecondary,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.normal)),
            Text(value,
                style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w600)),
          ],
        ),
      );
}
