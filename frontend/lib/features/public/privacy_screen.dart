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

class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactAsync = ref.watch(contactInfoProvider);
    final contact = contactAsync.valueOrNull ?? ContactInfo.fallback;
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
                    SizedBox(width: 220, child: _TableOfContents()),
                    const SizedBox(width: 40),
                    Expanded(child: _Body(contact: contact)),
                  ])
                : Column(children: [
                    _TableOfContents(),
                    const SizedBox(height: 32),
                    _Body(contact: contact),
                  ]),
          ),
          _Footer(),
        ]),
      ),
    );
  }
}


// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
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
        child: Text('Mise à jour : 20 juillet 2026',
            style: GoogleFonts.inter(fontSize: 13, color: _white, fontWeight: FontWeight.w500)),
      ),
      const SizedBox(height: 20),
      Text('Politique de Confidentialité',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(fontSize: 34, fontWeight: FontWeight.w800, color: _white, height: 1.2)),
      const SizedBox(height: 12),
      Text(
        'Infini Software s\'engage à ne collecter que les données strictement nécessaires au fonctionnement du service.',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFFB0C4D8), height: 1.6),
      ),
    ]),
  );
}

// ── Table of contents ─────────────────────────────────────────────────────────

class _TableOfContents extends StatelessWidget {
  static const _anchors = [
    'Qui sommes-nous ?',
    'Données collectées',
    'Utilisation des données',
    'Adresses IP & sécurité',
    'Ce que nous ne faisons PAS',
    'Conservation',
    'Vos droits',
    'Modifications',
    'Nous contacter',
  ];

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: _white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.list_rounded, color: _blue, size: 18),
        const SizedBox(width: 8),
        Text('Sommaire', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: _navy)),
      ]),
      const SizedBox(height: 12),
      Divider(color: _blue.withValues(alpha: 0.1), thickness: 1),
      const SizedBox(height: 8),
      ..._anchors.asMap().entries.map((e) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${e.key + 1}.', style: GoogleFonts.inter(fontSize: 12, color: _blue, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Expanded(child: Text(e.value, style: GoogleFonts.inter(fontSize: 12, color: _navy, height: 1.4))),
        ]),
      )),
    ]),
  );
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _Body extends StatelessWidget {
  final ContactInfo contact;
  const _Body({required this.contact});

  @override
  Widget build(BuildContext context) {
    final email = contact.email.isNotEmpty ? contact.email : 'support@pos-connect.ht';
    final phone = contact.whatsapp.isNotEmpty ? contact.whatsapp : null;

    return Container(
      padding: const EdgeInsets.all(36),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        _Section(
          number: '1',
          title: 'Qui sommes-nous ?',
          icon: Icons.business_rounded,
          child: _Para(
            'POS Connect est un logiciel de point de vente développé par Infini Software. '
            'Notre mission est de fournir aux commerces et restaurants un outil moderne, fiable et accessible. '
            'La présente politique de confidentialité décrit comment nous traitons vos données personnelles.',
          ),
        ),

        _Section(
          number: '2',
          title: 'Données collectées',
          icon: Icons.data_object_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Para('Lors de la création de votre compte, nous collectons uniquement les informations nécessaires au fonctionnement du service :'),
            const SizedBox(height: 12),
            _InfoRow(Icons.store_rounded,  _blue,  'Nom de l\'entreprise',   'Pour identifier votre espace et personnaliser l\'interface.'),
            _InfoRow(Icons.email_rounded,  _blue,  'Adresse email',          'Utilisée pour la connexion et les notifications essentielles du service.'),
            _InfoRow(Icons.lock_rounded,   _blue,  'Mot de passe',           'Stocké sous forme de hash cryptographique (argon2). Jamais en clair.'),
            _InfoRow(Icons.phone_rounded,  _blue,  'Téléphone (optionnel)',  'Pour le support en cas de besoin. Non obligatoire.'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF2CA01C).withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF2CA01C).withValues(alpha: 0.2)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.shield_rounded, color: Color(0xFF2CA01C), size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  'Vos données commerciales (produits, ventes, clients, stocks, etc.) sont stockées '
                  'sur vos propres appareils et serveurs, et sont utilisées uniquement pour assurer la '
                  'synchronisation entre vos terminaux (avec ou sans connexion). '
                  'Infini Software n\'y a aucun accès et ne les analyse jamais.',
                  style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF2A5A25), height: 1.5),
                )),
              ]),
            ),
          ]),
        ),

        _Section(
          number: '3',
          title: 'Utilisation des données',
          icon: Icons.settings_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Para('Les données de compte collectées sont utilisées exclusivement pour :'),
            const SizedBox(height: 10),
            _Bullet([
              'Créer et gérer votre espace locataire (tenant) sur nos serveurs.',
              'Vous authentifier de manière sécurisée lors de vos connexions.',
              'Assurer la synchronisation cloud de vos données entre vos appareils.',
              'Vous envoyer des notifications essentielles (expiration du plan, mises à jour critiques).',
              'Assurer le support technique si vous nous contactez.',
            ]),
          ]),
        ),

        _Section(
          number: '4',
          title: 'Adresses IP & sécurité',
          icon: Icons.security_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Para(
              'Lors de chaque tentative de connexion, l\'adresse IP de l\'appareil est enregistrée '
              'à des fins exclusives de sécurité : détection de connexions frauduleuses, protection '
              'de votre compte contre les accès non autorisés.',
            ),
            const SizedBox(height: 10),
            _Para('Ces journaux de connexion sont conservés pendant 30 jours puis supprimés automatiquement. '
                'Ils ne sont jamais utilisés à des fins de suivi, de profilage ou de publicité.'),
          ]),
        ),

        _Section(
          number: '5',
          title: 'Ce que nous ne faisons PAS',
          icon: Icons.do_not_disturb_on_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _NoBullet([
              'Accéder à vos données commerciales (ventes, produits, clients, stocks).',
              'Vendre ou louer vos données à des tiers.',
              'Utiliser vos données à des fins publicitaires ou de profilage.',
              'Partager vos données avec des partenaires sans votre consentement explicite.',
              'Conserver vos données après la clôture de votre compte (au-delà du délai légal).',
            ]),
          ]),
        ),

        _Section(
          number: '6',
          title: 'Conservation des données',
          icon: Icons.schedule_rounded,
          child: _Para(
            'Vos données sont conservées pendant toute la durée de votre abonnement. '
            'En cas de résiliation, elles sont maintenues pendant 90 jours pour vous permettre un export complet. '
            'Passé ce délai, elles sont définitivement et irréversiblement supprimées de nos serveurs.',
          ),
        ),

        _Section(
          number: '7',
          title: 'Vos droits',
          icon: Icons.verified_user_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Para('Conformément aux principes de protection des données, vous disposez du droit de :'),
            const SizedBox(height: 10),
            _Bullet([
              'Accéder à vos données personnelles en nous contactant.',
              'Rectifier toute information inexacte associée à votre compte.',
              'Demander la suppression de votre compte et de toutes vos données.',
              'Obtenir une copie exportable de l\'ensemble de vos données.',
            ]),
            const SizedBox(height: 12),
            _Para('Pour exercer ces droits, écrivez-nous à : $email'),
          ]),
        ),

        _Section(
          number: '8',
          title: 'Modifications de cette politique',
          icon: Icons.update_rounded,
          child: _Para(
            'Infini Software se réserve le droit de modifier cette politique de confidentialité. '
            'En cas de changement substantiel, vous serez informé par email au moins 15 jours avant l\'entrée en vigueur. '
            'La date de mise à jour figure toujours en haut de cette page.',
          ),
        ),

        _Section(
          number: '9',
          title: 'Nous contacter',
          icon: Icons.email_rounded,
          isLast: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Para('Pour toute question relative à cette politique de confidentialité :'),
            const SizedBox(height: 16),
            _ContactChip(Icons.email_outlined, 'Email', email),
            if (phone != null) ...[
              const SizedBox(height: 10),
              _ContactChip(Icons.chat_rounded, 'WhatsApp', phone),
            ],
            const SizedBox(height: 20),
            Builder(builder: (ctx) => OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: _blue,
                side: const BorderSide(color: _blue),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              icon: const Icon(Icons.send_rounded, size: 16),
              label: const Text('Envoyer un message'),
              onPressed: () => ctx.go('/contact'),
            )),
          ]),
        ),
      ]),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String number;
  final String title;
  final IconData icon;
  final Widget child;
  final bool isLast;

  const _Section({
    required this.number, required this.title,
    required this.icon, required this.child, this.isLast = false,
  });

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      Container(
        width: 32, height: 32,
        decoration: const BoxDecoration(color: _blue, shape: BoxShape.circle),
        child: Center(child: Text(number, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: _white))),
      ),
      const SizedBox(width: 12),
      Icon(icon, color: _blue, size: 20),
      const SizedBox(width: 8),
      Expanded(child: Text(title, style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: _navy))),
    ]),
    const SizedBox(height: 16),
    Padding(padding: const EdgeInsets.only(left: 44), child: child),
    if (!isLast) ...[
      const SizedBox(height: 28),
      Divider(color: const Color(0xFFE2E8F0), thickness: 1),
      const SizedBox(height: 24),
    ],
  ]);
}

class _Para extends StatelessWidget {
  final String text;
  const _Para(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF4A5568), height: 1.7));
}

class _Bullet extends StatelessWidget {
  final List<String> items;
  const _Bullet(this.items);
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: items.map((item) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 6, height: 6, margin: const EdgeInsets.only(top: 7, right: 10),
            decoration: const BoxDecoration(color: _blue, shape: BoxShape.circle)),
        Expanded(child: Text(item, style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF4A5568), height: 1.6))),
      ]),
    )).toList(),
  );
}

class _NoBullet extends StatelessWidget {
  final List<String> items;
  const _NoBullet(this.items);
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: items.map((item) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 22, height: 22, margin: const EdgeInsets.only(right: 10, top: 2),
          decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: const Icon(Icons.close_rounded, size: 14, color: Colors.red),
        ),
        Expanded(child: Text(item, style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF4A5568), height: 1.6))),
      ]),
    )).toList(),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String desc;
  const _InfoRow(this.icon, this.color, this.label, this.desc);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 36, height: 36, margin: const EdgeInsets.only(right: 12, top: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: color, size: 18),
      ),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: _navy)),
        Text(desc,  style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF718096), height: 1.4)),
      ])),
    ]),
  );
}

class _ContactChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _ContactChip(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
      color: _blue.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _blue.withValues(alpha: 0.15)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: _blue, size: 18),
      const SizedBox(width: 10),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF718096))),
        Text(value,  style: GoogleFonts.inter(fontSize: 14, color: _navy, fontWeight: FontWeight.w600)),
      ]),
    ]),
  );
}

// ── Footer ────────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    color: _navy,
    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text('© ${DateTime.now().year} POS Connect — Infini Software. Tous droits réservés.',
          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF718096))),
      Row(children: [
        TextButton(onPressed: () => context.go('/home'),    child: Text('Accueil',  style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF90A4BE)))),
        TextButton(onPressed: () => context.go('/contact'), child: Text('Contact',  style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF90A4BE)))),
        TextButton(onPressed: () => context.go('/terms'),   child: Text('CGU',      style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF90A4BE)))),
      ]),
    ]),
  );
}
