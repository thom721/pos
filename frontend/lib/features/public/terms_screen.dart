import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pos_connect/providers/contact_info_provider.dart';
import 'package:pos_connect/features/public/public_nav_bar.dart';

const _navy  = Color(0xFF1B2A3B);
const _blue  = Color(0xFF0077C5);
const _bg    = Color(0xFFF0F2F5);
const _white = Colors.white;

class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key});
  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  int _active = 0;

  static const _sections = [
    ('Définitions',               Icons.book_outlined,           _TermsDefs()),
    ('Utilisation du service',    Icons.gavel_rounded,           _TermsUsage()),
    ('Confidentialité',           Icons.lock_outline_rounded,    _TermsPrivacy()),
    ('Paiement & abonnement',     Icons.credit_card_outlined,    _TermsPayment()),
    ('Résiliation',               Icons.cancel_outlined,         _TermsTermination()),
    ('Limitation de responsabilité', Icons.shield_outlined,      _TermsLiability()),
    ('Contact',                   Icons.email_outlined,          _TermsContact()),
  ];

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      backgroundColor: _bg,
      body: SingleChildScrollView(
        child: Column(children: [
          const PublicNavBar(),
          _Header(),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isWide ? 80 : 24, vertical: 48),
            child: isWide
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 240, child: _Sidebar(active: _active, onTap: (i) => setState(() => _active = i))),
                    const SizedBox(width: 40),
                    Expanded(child: _Content(sectionIndex: _active)),
                  ])
                : Column(children: [
                    _MobileTabs(active: _active, onTap: (i) => setState(() => _active = i)),
                    const SizedBox(height: 24),
                    _Content(sectionIndex: _active),
                  ]),
          ),
          const _Footer(),
        ]),
      ),
    );
  }

  static List<(String, IconData, Widget)> get sections => _sections;
}


// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF0A1929), Color(0xFF1B2A3B)],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 56),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: _blue.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _blue.withValues(alpha: 0.4)),
          ),
          child: Text('Mis à jour le 20 juillet 2026', style: GoogleFonts.inter(fontSize: 13, color: _white, fontWeight: FontWeight.w500)),
        ),
        const SizedBox(height: 20),
        Text('Conditions Générales d\'Utilisation',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 34, fontWeight: FontWeight.w800, color: _white, height: 1.2),
        ),
        const SizedBox(height: 12),
        Text(
          'En utilisant POS Connect, vous acceptez les présentes conditions. Veuillez les lire attentivement.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFFB0C4D8), height: 1.6),
        ),
      ]),
    );
  }
}

// ── Sidebar ───────────────────────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  final int active;
  final ValueChanged<int> onTap;
  const _Sidebar({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final sections = _TermsScreenState.sections;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: Column(children: List.generate(sections.length, (i) {
        final isActive = i == active;
        return GestureDetector(
          onTap: () => onTap(i),
          child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isActive ? _blue.withValues(alpha: 0.08) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: isActive ? Border.all(color: _blue.withValues(alpha: 0.25)) : null,
            ),
            child: Row(children: [
              Icon(sections[i].$2, size: 18, color: isActive ? _blue : const Color(0xFF718096)),
              const SizedBox(width: 10),
              Expanded(child: Text(sections[i].$1,
                style: GoogleFonts.inter(fontSize: 13, fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    color: isActive ? _blue : _navy))),
            ]),
          ),
        );
      })),
    );
  }
}

class _MobileTabs extends StatelessWidget {
  final int active;
  final ValueChanged<int> onTap;
  const _MobileTabs({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final sections = _TermsScreenState.sections;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: List.generate(sections.length, (i) {
        final isActive = i == active;
        return GestureDetector(
          onTap: () => onTap(i),
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isActive ? _blue : _white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(sections[i].$1,
                style: GoogleFonts.inter(fontSize: 12, color: isActive ? _white : _navy)),
          ),
        );
      })),
    );
  }
}

// ── Content area ──────────────────────────────────────────────────────────────

class _Content extends StatelessWidget {
  final int sectionIndex;
  const _Content({required this.sectionIndex});

  @override
  Widget build(BuildContext context) {
    final sections = _TermsScreenState.sections;
    final section = sections[sectionIndex];
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: _blue.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
            child: Icon(section.$2, color: _blue, size: 22),
          ),
          const SizedBox(width: 14),
          Text(section.$1, style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800, color: _navy)),
        ]),
        const SizedBox(height: 8),
        Divider(color: _blue.withValues(alpha: 0.1), thickness: 1),
        const SizedBox(height: 20),
        section.$3,
      ]),
    );
  }
}

// ── Section content widgets ───────────────────────────────────────────────────

class _TermsDefs extends StatelessWidget {
  const _TermsDefs();
  @override
  Widget build(BuildContext context) => _Prose([
    _Para('Les termes suivants s\'appliquent dans les présentes conditions :'),
    _Def('POS Connect', 'Le logiciel de point de vente développé et maintenu par Infini Software, accessible via mobile (Android), desktop (macOS/Windows) et application web.'),
    _Def('Service', 'L\'ensemble des fonctionnalités offertes par POS Connect, incluant la gestion des ventes, inventaire, clients, rapports et synchronisation cloud.'),
    _Def('Utilisateur / Abonné', 'Toute personne physique ou morale disposant d\'un compte actif sur POS Connect.'),
    _Def('Tenant', 'L\'espace de données isolé associé à un abonné, hébergé sur les serveurs d\'Infini Software.'),
    _Def('Données', 'Toutes les informations saisies, importées ou générées par l\'Utilisateur dans le cadre de l\'utilisation du Service.'),
    _Def('Plan', 'Le niveau d\'abonnement souscrit (Starter, Pro ou Enterprise) définissant les limites d\'utilisation et les fonctionnalités disponibles.'),
  ]);
}

class _TermsUsage extends StatelessWidget {
  const _TermsUsage();
  @override
  Widget build(BuildContext context) => _Prose([
    _Para('En accédant au Service, l\'Utilisateur s\'engage à :'),
    _Bullet([
      'Fournir des informations exactes lors de la création du compte.',
      'Utiliser le Service uniquement à des fins légales et commerciales légitimes.',
      'Ne pas tenter d\'accéder aux données d\'autres tenants.',
      'Ne pas reproduire, vendre ou transférer l\'accès au Service à des tiers.',
      'Maintenir la confidentialité de ses identifiants de connexion.',
      'Ne pas utiliser le Service pour stocker des données frauduleuses, des informations de paiement falsifiées ou des produits illicites.',
    ]),
    _Para('Infini Software se réserve le droit de suspendre ou résilier tout compte en violation de ces conditions, sans préavis ni remboursement.'),
  ]);
}

class _TermsPrivacy extends StatelessWidget {
  const _TermsPrivacy();
  @override
  Widget build(BuildContext context) => _Prose([
    _Para('Infini Software collecte uniquement les données nécessaires au fonctionnement du Service :'),
    _Bullet([
      'Informations de compte : nom, email, numéro de téléphone.',
      'Données commerciales : ventes, produits, clients, fournisseurs.',
      'Données techniques : adresse IP, type d\'appareil, logs d\'accès.',
    ]),
    _Title('Utilisation des données'),
    _Para('Vos données sont utilisées exclusivement pour fournir et améliorer le Service. Elles ne sont jamais vendues à des tiers. Elles peuvent être partagées avec des sous-traitants techniques (hébergement, emails transactionnels) soumis aux mêmes obligations de confidentialité.'),
    _Title('Droits de l\'Utilisateur'),
    _Para('Vous disposez d\'un droit d\'accès, de rectification et de suppression de vos données personnelles en nous contactant à support@pos-connect.ht.'),
    _Title('Conservation'),
    _Para('Les données sont conservées pendant la durée de l\'abonnement et 90 jours après résiliation, délai pendant lequel vous pouvez demander un export complet.'),
  ]);
}

class _TermsPayment extends StatelessWidget {
  const _TermsPayment();
  @override
  Widget build(BuildContext context) => _Prose([
    _Title('Tarification'),
    _Para('Les tarifs sont affichés en HTG et en USD. L\'abonnement est mensuel, sans engagement minimum pour les plans Starter et Pro. Le plan Enterprise fait l\'objet d\'un contrat annuel sur devis.'),
    _Title('Facturation'),
    _Bullet([
      'La facturation est mensuelle, prépayée au début de chaque période.',
      'En cas de non-paiement, le compte est suspendu après 7 jours de grâce.',
      'Les caisses supplémentaires sont facturées au prorata.',
    ]),
    _Title('Remboursements'),
    _Para('Les paiements effectués ne sont pas remboursables, sauf erreur de facturation imputable à Infini Software. Les demandes de remboursement doivent être soumises dans les 14 jours suivant la facturation.'),
    _Title('Modification des prix'),
    _Para('Infini Software peut modifier ses tarifs avec un préavis de 30 jours par email. Vous pouvez résilier votre abonnement avant l\'entrée en vigueur des nouveaux prix.'),
  ]);
}

class _TermsTermination extends StatelessWidget {
  const _TermsTermination();
  @override
  Widget build(BuildContext context) => _Prose([
    _Title('Résiliation par l\'Utilisateur'),
    _Para('Vous pouvez résilier votre abonnement à tout moment depuis votre espace de facturation ou en nous contactant. La résiliation prend effet à la fin de la période en cours.'),
    _Title('Résiliation par Infini Software'),
    _Para('Infini Software peut résilier ou suspendre votre accès sans préavis en cas de :'),
    _Bullet([
      'Violation des présentes conditions.',
      'Activité frauduleuse ou illégale.',
      'Non-paiement après la période de grâce.',
      'Tentative de compromettre la sécurité du Service.',
    ]),
    _Title('Après résiliation'),
    _Para('Suite à la résiliation, vos données restent accessibles en lecture seule pendant 90 jours pour export. Passé ce délai, elles sont définitivement supprimées.'),
  ]);
}

class _TermsLiability extends StatelessWidget {
  const _TermsLiability();
  @override
  Widget build(BuildContext context) => _Prose([
    _Para('Le Service est fourni "en l\'état". Infini Software s\'engage à maintenir une disponibilité de 99,5 % (hors maintenances planifiées annoncées 24 h à l\'avance).'),
    _Title('Exclusions de responsabilité'),
    _Para('Infini Software ne saurait être tenu responsable de :'),
    _Bullet([
      'Pertes de données résultant d\'une mauvaise utilisation du Service.',
      'Interruptions liées à une force majeure (coupures d\'internet, catastrophes naturelles).',
      'Préjudices indirects, pertes de chiffre d\'affaires ou de clientèle.',
      'Erreurs de saisie ou de paramétrage par l\'Utilisateur.',
    ]),
    _Title('Limite de responsabilité'),
    _Para('Dans tous les cas, la responsabilité d\'Infini Software est limitée au montant payé par l\'Utilisateur pour le Service au cours des 3 derniers mois.'),
  ]);
}

class _TermsContact extends ConsumerWidget {
  const _TermsContact();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contact = ref.watch(contactInfoProvider).valueOrNull ?? ContactInfo.fallback;
    return _Prose([
      _Para('Pour toute question relative aux présentes conditions générales d\'utilisation, contactez-nous :'),
      if (contact.email.isNotEmpty)    _Def('Email',     contact.email),
      if (contact.whatsapp.isNotEmpty) _Def('WhatsApp',  contact.whatsapp),
      if (contact.address.isNotEmpty)  _Def('Adresse',   contact.address),
      _Para('Nos équipes sont disponibles du lundi au vendredi de 8h00 à 17h00 (heure locale).'),
      const SizedBox(height: 16),
      Builder(builder: (ctx) => FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: _blue),
        icon: const Icon(Icons.email_outlined, size: 18),
        label: const Text('Envoyer un message'),
        onPressed: () => ctx.go('/contact'),
      )),
    ]);
  }
}

// ── Prose helpers ─────────────────────────────────────────────────────────────

class _Prose extends StatelessWidget {
  final List<Widget> children;
  const _Prose(this.children);
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: children.map((w) => Padding(padding: const EdgeInsets.only(bottom: 12), child: w)).toList(),
  );
}

class _Para extends StatelessWidget {
  final String text;
  const _Para(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF4A5568), height: 1.7));
}

class _Title extends StatelessWidget {
  final String text;
  const _Title(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(text, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: _navy)),
  );
}

class _Def extends StatelessWidget {
  final String term;
  final String definition;
  const _Def(this.term, this.definition);
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      margin: const EdgeInsets.only(top: 2, right: 10),
      decoration: BoxDecoration(color: _blue.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
      child: Text(term, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: _blue)),
    ),
    Expanded(child: Text(definition,
        style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF4A5568), height: 1.6))),
  ]);
}

class _Bullet extends StatelessWidget {
  final List<String> items;
  const _Bullet(this.items);
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: items.map((item) => Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 6, height: 6, margin: const EdgeInsets.only(top: 7, right: 10),
            decoration: const BoxDecoration(color: _blue, shape: BoxShape.circle)),
        Expanded(child: Text(item, style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF4A5568), height: 1.6))),
      ]),
    )).toList(),
  );
}

// ── Footer ────────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  const _Footer();
  @override
  Widget build(BuildContext context) => Container(
    color: _navy,
    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text('© ${DateTime.now().year} POS Connect. Tous droits réservés.',
          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF718096))),
      Row(children: [
        TextButton(onPressed: () => context.go('/home'),    child: Text('Accueil',        style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF90A4BE)))),
        TextButton(onPressed: () => context.go('/contact'), child: Text('Contact',        style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF90A4BE)))),
        TextButton(onPressed: () => context.go('/privacy'), child: Text('Confidentialité',style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF90A4BE)))),
      ]),
    ]),
  );
}
