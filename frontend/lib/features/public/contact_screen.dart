import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pos_connect/providers/contact_info_provider.dart';
import 'package:pos_connect/features/public/public_nav_bar.dart';

const _navy  = Color(0xFF1B2A3B);
const _blue  = Color(0xFF0077C5);
const _green = Color(0xFF2CA01C);
const _bg    = Color(0xFFF0F2F5);
const _white = Colors.white;

class ContactScreen extends ConsumerStatefulWidget {
  const ContactScreen({super.key});
  @override
  ConsumerState<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends ConsumerState<ContactScreen> {
  final _formKey    = GlobalKey<FormState>();
  final _nameCtr    = TextEditingController();
  final _emailCtr   = TextEditingController();
  final _subjectCtr = TextEditingController();
  final _msgCtr     = TextEditingController();
  bool _sending = false;
  bool _sent    = false;

  @override
  void dispose() {
    _nameCtr.dispose(); _emailCtr.dispose();
    _subjectCtr.dispose(); _msgCtr.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sending = true);
    await Future.delayed(const Duration(seconds: 1));
    setState(() { _sending = false; _sent = true; });
  }

  @override
  Widget build(BuildContext context) {
    final contact = ref.watch(contactInfoProvider).valueOrNull ?? ContactInfo.fallback;
    return Scaffold(
      backgroundColor: _bg,
      body: SingleChildScrollView(
        child: Column(children: [
          const PublicNavBar(),
          const _Header(),
          _Body(
            formKey: _formKey, nameCtr: _nameCtr, emailCtr: _emailCtr,
            subjectCtr: _subjectCtr, msgCtr: _msgCtr,
            sending: _sending, sent: _sent, onSend: _send,
            contact: contact,
          ),
          const _Footer(),
        ]),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header();
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
        child: Text('Support & Contact', style: GoogleFonts.inter(fontSize: 13, color: _white, fontWeight: FontWeight.w500)),
      ),
      const SizedBox(height: 20),
      Text('Nous sommes là pour vous aider',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(fontSize: 36, fontWeight: FontWeight.w800, color: _white, height: 1.2)),
      const SizedBox(height: 12),
      Text(
        'Une question, un projet, un besoin d\'assistance ? Envoyez-nous un message et nous vous répondons dans les 24 heures.',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFFB0C4D8), height: 1.6)),
    ]),
  );
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _Body extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nameCtr, emailCtr, subjectCtr, msgCtr;
  final bool sending, sent;
  final VoidCallback onSend;
  final ContactInfo contact;

  const _Body({
    required this.formKey, required this.nameCtr, required this.emailCtr,
    required this.subjectCtr, required this.msgCtr,
    required this.sending, required this.sent, required this.onSend,
    required this.contact,
  });

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isWide ? 80 : 24, vertical: 56),
      child: isWide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _ContactInfo(contact: contact)),
              const SizedBox(width: 48),
              Expanded(flex: 2, child: _ContactForm(
                formKey: formKey, nameCtr: nameCtr, emailCtr: emailCtr,
                subjectCtr: subjectCtr, msgCtr: msgCtr,
                sending: sending, sent: sent, onSend: onSend,
              )),
            ])
          : Column(children: [
              _ContactInfo(contact: contact),
              const SizedBox(height: 40),
              _ContactForm(
                formKey: formKey, nameCtr: nameCtr, emailCtr: emailCtr,
                subjectCtr: subjectCtr, msgCtr: msgCtr,
                sending: sending, sent: sent, onSend: onSend,
              ),
            ]),
    );
  }
}

// ── Contact info panel ────────────────────────────────────────────────────────

class _ContactInfo extends StatelessWidget {
  final ContactInfo contact;
  const _ContactInfo({required this.contact});

  @override
  Widget build(BuildContext context) {
    final email = contact.email.isNotEmpty ? contact.email : 'support@pos-connect.ht';
    final phone = contact.whatsapp.isNotEmpty ? contact.whatsapp : null;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Coordonnées', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800, color: _navy)),
      const SizedBox(height: 24),
      _InfoTile(Icons.email_outlined,      'Email',    email),
      if (phone != null)
        _InfoTile(Icons.chat_rounded,      'WhatsApp', phone),
      _InfoTile(Icons.access_time_rounded, 'Horaires', 'Lun–Ven : 8h – 17h (EST)'),
      _InfoTile(Icons.location_on_outlined,'Adresse',  'Port-au-Prince, Haïti'),
      const SizedBox(height: 32),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _blue.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _blue.withValues(alpha: 0.15)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.headset_mic_rounded, color: _blue, size: 20),
            const SizedBox(width: 8),
            Text('Support prioritaire', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: _navy)),
          ]),
          const SizedBox(height: 8),
          Text(
            'Les abonnés Pro et Enterprise bénéficient d\'une réponse garantie sous 4 heures ouvrables et d\'un accès au support WhatsApp.',
            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF718096), height: 1.5)),
        ]),
      ),
      const SizedBox(height: 24),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _green.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _green.withValues(alpha: 0.15)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.book_outlined, color: _green, size: 20),
            const SizedBox(width: 8),
            Text('Documentation', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: _navy)),
          ]),
          const SizedBox(height: 8),
          Text(
            'Consultez notre base de connaissances pour des guides pas à pas, des tutoriels vidéo et des FAQ.',
            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF718096), height: 1.5)),
        ]),
      ),
    ]);
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoTile(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 44, height: 44,
        decoration: BoxDecoration(color: _blue.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: _blue, size: 20),
      ),
      const SizedBox(width: 14),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF718096), fontWeight: FontWeight.w500)),
        Text(value,  style: GoogleFonts.inter(fontSize: 14, color: _navy, fontWeight: FontWeight.w600)),
      ]),
    ]),
  );
}

// ── Contact form ──────────────────────────────────────────────────────────────

class _ContactForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nameCtr, emailCtr, subjectCtr, msgCtr;
  final bool sending, sent;
  final VoidCallback onSend;

  const _ContactForm({
    required this.formKey, required this.nameCtr, required this.emailCtr,
    required this.subjectCtr, required this.msgCtr,
    required this.sending, required this.sent, required this.onSend,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(32),
    decoration: BoxDecoration(
      color: _white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, 8))],
    ),
    child: sent ? const _SuccessState() : Form(
      key: formKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Envoyer un message', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: _navy)),
        const SizedBox(height: 4),
        Text('Nous vous répondons sous 24 heures ouvrables.',
            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF718096))),
        const SizedBox(height: 28),
        Row(children: [
          Expanded(child: _Field(controller: nameCtr,   label: 'Nom complet',  hint: 'Jean Dupont',         icon: Icons.person_outline)),
          const SizedBox(width: 16),
          Expanded(child: _Field(controller: emailCtr,  label: 'Email',        hint: 'jean@example.com',    icon: Icons.email_outlined,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Champ requis';
              if (!v.contains('@')) return 'Email invalide';
              return null;
            })),
        ]),
        const SizedBox(height: 16),
        _Field(controller: subjectCtr, label: 'Sujet',   hint: 'Ex: Problème de connexion',            icon: Icons.subject_rounded),
        const SizedBox(height: 16),
        _Field(
          controller: msgCtr, label: 'Message',
          hint: 'Décrivez votre question ou problème en détail...',
          icon: Icons.chat_bubble_outline_rounded, maxLines: 6,
          validator: (v) => (v == null || v.trim().length < 10) ? 'Message trop court' : null,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _blue,
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            icon: sending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _white))
                : const Icon(Icons.send_rounded, size: 18),
            label: Text(sending ? 'Envoi en cours…' : 'Envoyer le message'),
            onPressed: sending ? null : onSend,
          ),
        ),
      ]),
    ),
  );
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final int maxLines;
  final String? Function(String?)? validator;

  const _Field({
    required this.controller, required this.label,
    required this.hint, required this.icon,
    this.maxLines = 1, this.validator,
  });

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: _navy)),
    const SizedBox(height: 6),
    TextFormField(
      controller: controller, maxLines: maxLines,
      validator: validator ?? (v) => (v == null || v.isEmpty) ? 'Champ requis' : null,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(fontSize: 14, color: const Color(0xFFABB2BF)),
        prefixIcon: maxLines == 1 ? Icon(icon, size: 18, color: const Color(0xFF90A4BE)) : null,
        filled: true, fillColor: _bg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _blue, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.red, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    ),
  ]);
}

class _SuccessState extends StatelessWidget {
  const _SuccessState();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40),
    child: Column(children: [
      Container(
        width: 72, height: 72,
        decoration: const BoxDecoration(color: Color(0xFFE8F5E9), shape: BoxShape.circle),
        child: const Icon(Icons.check_circle_rounded, color: _green, size: 40),
      ),
      const SizedBox(height: 20),
      Text('Message envoyé !', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800, color: _navy)),
      const SizedBox(height: 8),
      Text(
        'Merci pour votre message. Notre équipe vous répondra dans les 24 heures ouvrables.',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF718096), height: 1.5)),
    ]),
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
        TextButton(onPressed: () => context.go('/terms'),   child: Text('CGU',            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF90A4BE)))),
        TextButton(onPressed: () => context.go('/privacy'), child: Text('Confidentialité',style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF90A4BE)))),
      ]),
    ]),
  );
}
