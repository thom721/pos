import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pos_connect/providers/pricing_provider.dart';
import 'package:pos_connect/features/public/public_nav_bar.dart';

// ── Palette ───────────────────────────────────────────────────────────────────

const _navy   = Color(0xFF1B2A3B);
const _blue   = Color(0xFF0077C5);
const _green  = Color(0xFF2CA01C);
const _bg     = Color(0xFFF0F2F5);
const _white  = Colors.white;

// ── Screen ────────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _white,
      body: SingleChildScrollView(
        controller: _scrollCtrl,
        child: Column(children: [
          const PublicNavBar(),
          const _Hero(),
          _Features(scrollCtrl: _scrollCtrl),
          const _RestaurantBand(),
          _Pricing(),
          _CtaBand(),
          _Footer(),
        ]),
      ),
    );
  }
}

// ── Hero ──────────────────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF0A1929), Color(0xFF1B2A3B), Color(0xFF0D3B6E)],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: isWide ? 80 : 24, vertical: isWide ? 80 : 48),
        child: isWide
            ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Expanded(child: _HeroText()),
                const SizedBox(width: 64),
                Expanded(child: const _HeroImage()),
              ])
            : Column(children: [_HeroText(), const SizedBox(height: 40), const _HeroImage()]),
      ),
    );
  }
}

class _HeroText extends StatelessWidget {
  const _HeroText();

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: _blue.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _blue.withValues(alpha: 0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 7, height: 7, decoration: const BoxDecoration(color: _green, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text('Solution POS #1 en Haïti',
              style: GoogleFonts.inter(fontSize: 13, color: _white, fontWeight: FontWeight.w500)),
        ]),
      ),
      const SizedBox(height: 24),
      Text(
        'Gérez votre commerce.\nPartout. Toujours.',
        style: GoogleFonts.inter(
          fontSize: 46, fontWeight: FontWeight.w800,
          color: _white, height: 1.15, letterSpacing: -0.5,
        ),
      ),
      const SizedBox(height: 16),
      // Sector chips
      Wrap(spacing: 8, runSpacing: 8, children: [
        _SectorChip(Icons.store_rounded,           'Commerce général'),
        _SectorChip(Icons.restaurant_menu_rounded, 'Restaurant'),
        _SectorChip(Icons.nightlife_rounded,        'Club / Bar'),
        _SectorChip(Icons.local_pharmacy_rounded,  'Pharmacie'),
        _SectorChip(Icons.more_horiz_rounded,       'Et plus...'),
      ]),
      const SizedBox(height: 20),
      Text(
        'La caisse tout-en-un adaptée à votre secteur d\'activité — inventaire, ventes, rapports et synchronisation cloud en temps réel.',
        style: GoogleFonts.inter(fontSize: 16, color: const Color(0xFFB0C4D8), height: 1.6),
      ),
      const SizedBox(height: 32),
      Wrap(spacing: 14, runSpacing: 12, children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: _blue,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          icon: const Icon(Icons.rocket_launch_rounded, size: 18),
          label: const Text('Commencer gratuitement'),
          onPressed: () => context.go('/register'),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: _white,
            side: BorderSide(color: _white.withValues(alpha: 0.4)),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            textStyle: GoogleFonts.inter(fontSize: 15),
          ),
          icon: const Icon(Icons.contact_support_outlined, size: 18),
          label: const Text('Parler à un expert'),
          onPressed: () => context.go('/contact'),
        ),
      ]),
      const SizedBox(height: 28),
      // Platform availability
      Text('Disponible sur',
          style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF90A4BE), letterSpacing: 0.8)),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 8, children: [
        _PlatformPill(Icons.android_rounded,    'Android', available: true),
        _PlatformPill(Icons.computer_rounded,   'macOS',   available: true),
        _PlatformPill(Icons.web_rounded,        'Web',     available: true),
        _PlatformPill(Icons.phone_iphone_rounded, 'iOS',   available: false, soon: true),
      ]),
      const SizedBox(height: 32),
      // Stats row
      Row(children: [
        _Stat('500+', 'Commerces actifs'),
        _divider(),
        _Stat('10k+', 'Transactions/jour'),
        _divider(),
        _Stat('99.9%', 'Disponibilité'),
      ]),
    ]);
  }

  Widget _divider() => Container(
    width: 1, height: 36, margin: const EdgeInsets.symmetric(horizontal: 20),
    color: _white.withValues(alpha: 0.2),
  );
}

class _SectorChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectorChip(this.icon, this.label);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: _white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _white.withValues(alpha: 0.15)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: _white.withValues(alpha: 0.65)),
      const SizedBox(width: 6),
      Text(label,
          style: GoogleFonts.inter(fontSize: 12, color: _white.withValues(alpha: 0.75))),
    ]),
  );
}

class _PlatformPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool available;
  final bool soon;
  const _PlatformPill(this.icon, this.label,
      {required this.available, this.soon = false});

  @override
  Widget build(BuildContext context) {
    final fg = available ? _green : _white.withValues(alpha: 0.4);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: available
            ? _green.withValues(alpha: 0.12)
            : _white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: available
              ? _green.withValues(alpha: 0.3)
              : _white.withValues(alpha: 0.12),
        ),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: fg),
        const SizedBox(width: 6),
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 12, color: fg, fontWeight: FontWeight.w500)),
        if (soon) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('bientôt',
                style: GoogleFonts.inter(
                    fontSize: 9,
                    color: Colors.amber,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat(this.value, this.label);
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(value, style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w800, color: _white)),
    Text(label, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF90A4BE))),
  ]);
}

class _HeroImage extends StatelessWidget {
  const _HeroImage();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 40, offset: const Offset(0, 20))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        Image.network(
          'https://images.unsplash.com/photo-1556740758-90de374c12ad?w=700&q=80',
          fit: BoxFit.cover, height: 400, width: double.infinity,
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : Container(height: 400, color: const Color(0xFF1A3A5C)),
          errorBuilder: (_, __, ___) => Container(
            height: 400, color: const Color(0xFF1A3A5C),
            child: const Center(child: Icon(Icons.point_of_sale_rounded, color: _blue, size: 80)),
          ),
        ),
        Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.4)],
          ),
        ))),
        Positioned(bottom: 16, left: 16, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.check_circle_rounded, color: _white, size: 16),
            const SizedBox(width: 6),
            Text('Sync en temps réel',
                style: GoogleFonts.inter(color: _white, fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        )),
      ]),
    );
  }
}

// ── Scroll-reveal wrapper ─────────────────────────────────────────────────────

class _Reveal extends StatefulWidget {
  final Widget child;
  final ScrollController scrollCtrl;
  final int delayMs;

  const _Reveal({
    required this.child,
    required this.scrollCtrl,
    this.delayMs = 0,
  });

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>  _fade;
  late final Animation<Offset>  _slide;
  final _key = GlobalKey();
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    widget.scrollCtrl.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  void _check() {
    if (_done || !mounted) return;
    final ctx = _key.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final pos = box.localToGlobal(Offset.zero);
    final screenH = MediaQuery.of(ctx).size.height;
    if (pos.dy < screenH + 80) {
      _done = true;
      Future.delayed(Duration(milliseconds: widget.delayMs), () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    widget.scrollCtrl.removeListener(_check);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: KeyedSubtree(key: _key, child: widget.child),
      ),
    );
  }
}

// ── Features ──────────────────────────────────────────────────────────────────

class _Features extends StatelessWidget {
  final ScrollController scrollCtrl;
  const _Features({required this.scrollCtrl});

  static const _items = [
    (
      Icons.devices_rounded, _blue,
      'Multi-plateforme',
      'Mobile Android, desktop macOS/Windows et application web — un seul compte, partout.',
      'https://images.unsplash.com/photo-1512941937938-c02a18bd5432?w=500&q=80',
    ),
    (
      Icons.restaurant_menu_rounded, Color(0xFFE67E22),
      'Mode restaurant',
      'Gestion des tables, commandes en cuisine, pourboires et couverts intégrés.',
      'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=500&q=80',
    ),
    (
      Icons.wifi_off_rounded, _green,
      'Hors ligne',
      'Continuez à encaisser même sans internet. Les données se synchronisent à la reconnexion.',
      'https://images.unsplash.com/photo-1556742049-0cfed4f6a45d?w=500&q=80',
    ),
    (
      Icons.store_mall_directory_rounded, Color(0xFF8E44AD),
      'Multi-dépôts',
      'Gérez plusieurs points de vente depuis un tableau de bord centralisé.',
      'https://images.unsplash.com/photo-1441986300917-64674bd600d8?w=500&q=80',
    ),
    (
      Icons.cloud_sync_rounded, Color(0xFF2980B9),
      'Sync cloud',
      'Toutes vos données synchronisées automatiquement entre tous vos appareils.',
      'https://images.unsplash.com/photo-1451187580459-43490279c0fa?w=500&q=80',
    ),
    (
      Icons.bar_chart_rounded, Color(0xFF16A085),
      'Rapports avancés',
      'Statistiques de ventes, rapports par dépôt, analyse des performances en temps réel.',
      'https://images.unsplash.com/photo-1551288049-bebda4e38f71?w=500&q=80',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 700;
    final cards = List.generate(_items.length, (i) {
      final it = _items[i];
      return _Reveal(
        scrollCtrl: scrollCtrl,
        delayMs: (i % 3) * 120,
        child: _FeatureCard(
          icon: it.$1, color: it.$2,
          title: it.$3, desc: it.$4, imageUrl: it.$5,
        ),
      );
    });

    return Container(
      color: _bg,
      padding: EdgeInsets.symmetric(horizontal: isWide ? 80 : 24, vertical: 72),
      child: Column(children: [
        const _SectionLabel('Fonctionnalités'),
        const SizedBox(height: 12),
        Text(
          'Tout ce dont vous avez besoin pour gérer votre commerce',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: isWide ? 32 : 22, fontWeight: FontWeight.w800, color: _navy, height: 1.2),
        ),
        const SizedBox(height: 48),
        if (isWide) ...[
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: cards[0]),
              const SizedBox(width: 20),
              Expanded(child: cards[1]),
              const SizedBox(width: 20),
              Expanded(child: cards[2]),
            ]),
          ),
          const SizedBox(height: 20),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: cards[3]),
              const SizedBox(width: 20),
              Expanded(child: cards[4]),
              const SizedBox(width: 20),
              Expanded(child: cards[5]),
            ]),
          ),
        ] else
          ...cards.expand((c) => [c, const SizedBox(height: 16)]).toList()..removeLast(),
      ]),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String desc;
  final String imageUrl;

  const _FeatureCard({
    required this.icon, required this.color,
    required this.title, required this.desc, required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Image illustrative
        SizedBox(
          height: 148,
          width: double.infinity,
          child: Stack(fit: StackFit.expand, children: [
            Image.network(
              imageUrl,
              fit: BoxFit.cover,
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : Container(color: color.withValues(alpha: 0.08)),
              errorBuilder: (_, __, ___) => Container(
                color: color.withValues(alpha: 0.08),
                child: Icon(icon, color: color, size: 48),
              ),
            ),
            // Gradient overlay so text/icon remain readable
            DecoratedBox(decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withValues(alpha: 0.25)],
              ),
            )),
            // Color accent badge top-right
            Positioned(
              top: 12, right: 12,
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 3))],
                ),
                child: Icon(icon, color: _white, size: 18),
              ),
            ),
          ]),
        ),
        // Text content
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: _navy)),
            const SizedBox(height: 6),
            Text(desc, style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF718096), height: 1.55)),
          ]),
        ),
      ]),
    );
  }
}

// ── Restaurant showcase ───────────────────────────────────────────────────────

class _RestaurantBand extends StatelessWidget {
  const _RestaurantBand();

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    return Container(
      color: _white,
      padding: EdgeInsets.symmetric(horizontal: isWide ? 80 : 24, vertical: 72),
      child: isWide
          ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              const Expanded(child: _RestaurantImage()),
              const SizedBox(width: 64),
              const Expanded(child: _RestaurantText()),
            ])
          : const Column(children: [
              _RestaurantImage(),
              SizedBox(height: 40),
              _RestaurantText(),
            ]),
    );
  }
}

class _RestaurantImage extends StatelessWidget {
  const _RestaurantImage();
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(children: [
        Image.network(
          'https://images.unsplash.com/photo-1414235077428-338989a2e8c0?w=700&q=80',
          height: 400, width: double.infinity, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            height: 400, color: const Color(0xFFFFF3E0),
            child: const Center(child: Icon(Icons.restaurant_rounded, size: 80, color: Color(0xFFE67E22))),
          ),
        ),
        Positioned(top: 16, right: 16, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: const Color(0xFFE67E22), borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.restaurant_rounded, color: _white, size: 14),
            const SizedBox(width: 6),
            Text('Mode Restaurant', style: GoogleFonts.inter(color: _white, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        )),
      ]),
    );
  }
}

class _RestaurantText extends StatelessWidget {
  const _RestaurantText();

  static const _points = [
    ('Tables interactives',  'Plan de salle visuel avec statut en temps réel'),
    ('Bons de cuisine',      'Impression automatique ou affichage en cuisine'),
    ('Pourboires & couverts','Calcul automatique configurable par table'),
    ('Commandes multiples',  'Gérez plusieurs tables et commandes simultanément'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SectionLabel('Pour les restaurants'),
      const SizedBox(height: 12),
      Text(
        'Un POS pensé pour la restauration haïtienne',
        style: GoogleFonts.inter(fontSize: 30, fontWeight: FontWeight.w800, color: _navy, height: 1.2),
      ),
      const SizedBox(height: 16),
      Text(
        'Gérez vos tables, prenez les commandes en salle, envoyez les bons en cuisine et calculez automatiquement les pourboires. Tout en temps réel.',
        style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF718096), height: 1.6),
      ),
      const SizedBox(height: 28),
      ..._points.map((e) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 28, height: 28, margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFE67E22).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, color: Color(0xFFE67E22), size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.$1, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: _navy)),
            Text(e.$2, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF718096))),
          ])),
        ]),
      )),
    ]);
  }
}

// ── Pricing ───────────────────────────────────────────────────────────────────

String _fmtHtg(double v) {
  final n = v.round();
  if (n >= 1000) {
    final thousands = n ~/ 1000;
    final remainder = n % 1000;
    return remainder == 0 ? '$thousands 000 HTG' : '$thousands ${remainder.toString().padLeft(3, '0')} HTG';
  }
  return '$n HTG';
}

String _fmtUsd(double v) => '${v % 1 == 0 ? v.round() : v} USD';

class _Pricing extends ConsumerWidget {
  const _Pricing();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    final pricing = ref.watch(pricingProvider);
    final p = pricing.valueOrNull ?? PricingInfo.fallback;

    final proHtg = _fmtHtg(p.monthlyPriceHtg);
    final proUsd = _fmtUsd(p.monthlyPriceUsd);
    final extraLabel = '+ ${_fmtHtg(p.extraCaisseHtg)} / ${_fmtUsd(p.extraCaisseUsd)} par caisse supplémentaire';
    final trialLabel = p.trialDays > 0 ? 'Essai gratuit ${p.trialDays} jours  •  ' : '';

    return Container(
      color: _bg,
      padding: EdgeInsets.symmetric(horizontal: isWide ? 80 : 24, vertical: 72),
      child: Column(children: [
        const _SectionLabel('Tarification'),
        const SizedBox(height: 12),
        Text(
          'Des tarifs adaptés à chaque commerce',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: isWide ? 32 : 22, fontWeight: FontWeight.w800, color: _navy, height: 1.2),
        ),
        const SizedBox(height: 8),
        Text(
          '${trialLabel}Paiement en HTG ou USD  •  Support inclus',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF718096)),
        ),
        const SizedBox(height: 48),
        if (isWide)
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: _PriceCard(
                plan: 'Starter', priceHtg: 'Gratuit', priceUsd: '',
                period: '${p.trialDays} jours d\'essai', subtitle: 'Pour découvrir',
                highlighted: false,
                features: ['1 dépôt', '1 caisse', 'Ventes & encaissements', 'Gestion clients', 'Rapports de base', 'Support email', 'Aucune carte requise'],
              )),
              const SizedBox(width: 20),
              Expanded(child: _PriceCard(
                plan: 'Pro', priceHtg: proHtg, priceUsd: proUsd,
                period: 'par mois · 1 dépôt', subtitle: 'Basé sur le nombre de caisses',
                highlighted: true,
                features: ['1 dépôt inclus', '3 caisses incluses', 'Mode restaurant', 'Sync cloud temps réel', 'Rapports avancés', 'Multi-plateformes', 'Support prioritaire'],
              )),
              const SizedBox(width: 20),
              const Expanded(child: _PriceCard(
                plan: 'Enterprise', priceHtg: 'Sur devis', priceUsd: '',
                period: '', subtitle: 'Pour les grandes enseignes',
                highlighted: false,
                features: ['Dépôts illimités', 'Caisses illimitées', 'API REST complète', 'White label', 'Formation sur site', 'Gestionnaire dédié', 'SLA 99.9%'],
              )),
            ]),
          )
        else
          Column(children: [
            _PriceCard(plan: 'Starter', priceHtg: 'Gratuit', priceUsd: '', period: '${p.trialDays} jours d\'essai', subtitle: 'Pour découvrir', highlighted: false,
              features: const ['1 dépôt', '1 caisse', 'Ventes & encaissements', 'Gestion clients', 'Rapports de base']),
            const SizedBox(height: 20),
            _PriceCard(plan: 'Pro', priceHtg: proHtg, priceUsd: proUsd, period: 'par mois · 1 dépôt', subtitle: 'Basé sur le nombre de caisses', highlighted: true,
              features: const ['1 dépôt inclus', '3 caisses incluses', 'Mode restaurant', 'Sync cloud', 'Rapports avancés']),
            const SizedBox(height: 20),
            const _PriceCard(plan: 'Enterprise', priceHtg: 'Sur devis', priceUsd: '', period: '', subtitle: 'Pour les grandes enseignes', highlighted: false,
              features: ['Dépôts illimités', 'Caisses illimitées', 'API REST', 'White label', 'Support dédié']),
          ]),
        const SizedBox(height: 20),
        pricing.isLoading
            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(extraLabel, style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF718096))),
      ]),
    );
  }
}

class _PriceCard extends StatelessWidget {
  final String plan, priceHtg, priceUsd, period, subtitle;
  final bool highlighted;
  final List<String> features;

  const _PriceCard({
    required this.plan, required this.priceHtg, required this.priceUsd,
    required this.period, required this.subtitle,
    required this.highlighted, required this.features,
  });

  @override
  Widget build(BuildContext context) {
    final textDim = highlighted ? const Color(0xFF90A4BE) : const Color(0xFF718096);
    final textMain = highlighted ? _white : _navy;

    return Container(
      decoration: BoxDecoration(
        color: highlighted ? _navy : _white,
        borderRadius: BorderRadius.circular(20),
        border: highlighted ? null : Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
        boxShadow: highlighted
            ? [BoxShadow(color: _navy.withValues(alpha: 0.3), blurRadius: 32, offset: const Offset(0, 8))]
            : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12)],
      ),
      child: Stack(children: [
        if (highlighted)
          Positioned(top: 0, left: 0, right: 0, child: Container(
            height: 4,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [_blue, _green]),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
            ),
          )),
        Padding(
          padding: const EdgeInsets.all(28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (highlighted)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_blue, _green]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('Recommandé', style: GoogleFonts.inter(color: _white, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            Text(plan, style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: textMain)),
            const SizedBox(height: 4),
            Text(subtitle, style: GoogleFonts.inter(fontSize: 13, color: textDim)),
            const SizedBox(height: 20),
            Text(priceHtg, style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w800, color: textMain)),
            if (priceUsd.isNotEmpty) Text(priceUsd, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: _blue)),
            if (period.isNotEmpty) Text(period, style: GoogleFonts.inter(fontSize: 13, color: textDim)),
            const SizedBox(height: 24),
            Divider(color: highlighted ? _white.withValues(alpha: 0.1) : const Color(0xFFE2E8F0)),
            const SizedBox(height: 16),
            ...features.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                Icon(Icons.check_circle_rounded, size: 18, color: highlighted ? _green : _blue),
                const SizedBox(width: 10),
                Expanded(child: Text(f, style: GoogleFonts.inter(fontSize: 13, color: textMain.withValues(alpha: 0.9)))),
              ]),
            )),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: priceHtg == 'Sur devis'
                  ? OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textMain,
                        side: BorderSide(color: textMain.withValues(alpha: 0.3)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => context.go('/contact'),
                      child: const Text('Nous contacter'),
                    )
                  : FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: highlighted ? _blue : _navy,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => context.go('/register'),
                      child: Text(plan == 'Starter' ? 'Commencer gratuitement' : 'Choisir $plan'),
                    ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── CTA Band ──────────────────────────────────────────────────────────────────

class _CtaBand extends StatelessWidget {
  const _CtaBand();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [_blue, Color(0xFF0D47A1)]),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 64),
      child: Column(children: [
        Text(
          'Prêt à transformer votre commerce ?',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.w800, color: _white, height: 1.2),
        ),
        const SizedBox(height: 16),
        Text(
          'Rejoignez des centaines de commerçants haïtiens qui font confiance à POS Connect.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 16, color: _white.withValues(alpha: 0.8), height: 1.5),
        ),
        const SizedBox(height: 32),
        Wrap(spacing: 16, runSpacing: 12, alignment: WrapAlignment.center, children: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _white, foregroundColor: _blue,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            onPressed: () => context.go('/register'),
            child: const Text('Créer mon compte gratuit'),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: _white,
              side: BorderSide(color: _white.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              textStyle: GoogleFonts.inter(fontSize: 15),
            ),
            onPressed: () => context.go('/contact'),
            child: const Text('Parler à un expert'),
          ),
        ]),
      ]),
    );
  }
}

// ── Footer ────────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 700;
    return Container(
      color: _navy,
      padding: EdgeInsets.symmetric(horizontal: isWide ? 80 : 24, vertical: 48),
      child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: _blue, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.point_of_sale_rounded, color: _white, size: 20),
              ),
              const SizedBox(width: 10),
              Text('POS Connect',
                  style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: _white)),
            ]),
            const SizedBox(height: 12),
            Text(
              'La solution POS moderne pour les commerces et restaurants haïtiens.',
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF718096), height: 1.5),
            ),
          ])),
          if (isWide) ...[
            const SizedBox(width: 40),
            Expanded(child: _FooterCol('Navigation', [('Accueil', '/home'), ('Connexion', '/login'), ('Créer un compte', '/register')])),
            const SizedBox(width: 20),
            Expanded(child: _FooterCol('Légal', [('Conditions générales', '/terms'), ('Politique de confidentialité', '/privacy'), ('Contact', '/contact')])),
            const SizedBox(width: 20),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Contact', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: _white)),
              const SizedBox(height: 12),
              _info(Icons.email_outlined,    'support@pos-connect.ht'),
              _info(Icons.phone_outlined,    '+509 4000-0000'),
              _info(Icons.location_on_outlined, 'Port-au-Prince, Haïti'),
            ])),
          ],
        ]),
        const SizedBox(height: 40),
        Divider(color: _white.withValues(alpha: 0.08)),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('© ${DateTime.now().year} POS Connect. Tous droits réservés.',
              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF718096))),
          if (isWide)
            Text('Fait avec ♥ en Haïti 🇭🇹',
                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF718096))),
        ]),
      ]),
    );
  }

  Widget _info(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Icon(icon, size: 14, color: const Color(0xFF718096)),
      const SizedBox(width: 8),
      Text(text, style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF90A4BE))),
    ]),
  );
}

class _FooterCol extends StatelessWidget {
  final String title;
  final List<(String, String)> links;
  const _FooterCol(this.title, this.links);
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: _white)),
    const SizedBox(height: 12),
    ...links.map((l) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => context.go(l.$2),
        child: Text(l.$1, style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF90A4BE))),
      ),
    )),
  ]);
}

// ── Shared ────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    decoration: BoxDecoration(
      color: _blue.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _blue.withValues(alpha: 0.2)),
    ),
    child: Text(text, style: GoogleFonts.inter(fontSize: 13, color: _blue, fontWeight: FontWeight.w600)),
  );
}
