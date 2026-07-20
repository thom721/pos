import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

const _pubNavy  = Color(0xFF1B2A3B);
const _pubBlue  = Color(0xFF0077C5);
const _pubWhite = Colors.white;

class PublicNavBar extends StatelessWidget {
  const PublicNavBar({super.key});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final isNarrow = w < 860;
    final isVeryNarrow = w < 500;

    return Material(
      elevation: 1,
      color: _pubWhite,
      child: SizedBox(
        height: 64,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(children: [
            // Logo cliquable
            GestureDetector(
              onTap: () => context.go('/home'),
              child: Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: _pubBlue,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.point_of_sale_rounded, color: _pubWhite, size: 20),
                ),
                const SizedBox(width: 10),
                Text('POS Connect',
                    style: GoogleFonts.inter(
                        fontSize: 16, fontWeight: FontWeight.w700, color: _pubNavy)),
              ]),
            ),
            const Spacer(),
            // Liens de navigation (cachés sur très petit écran)
            if (!isNarrow) ...[
              _PubNavLink('Accueil',         '/home'),
              _PubNavLink('Contact',         '/contact'),
              _PubNavLink('CGU',             '/terms'),
              _PubNavLink('Confidentialité', '/privacy'),
              const SizedBox(width: 16),
            ],
            // Bouton Se connecter
            if (!isVeryNarrow)
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _pubBlue,
                  side: const BorderSide(color: _pubBlue),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onPressed: () => context.go('/login'),
                child: Text('Se connecter',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
              ),
            const SizedBox(width: 8),
            // Bouton Créer un compte
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _pubBlue,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onPressed: () => context.go('/register'),
              child: Text(isNarrow ? 'S\'inscrire' : 'Créer un compte',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _PubNavLink extends StatelessWidget {
  final String label;
  final String route;
  const _PubNavLink(this.label, this.route);

  @override
  Widget build(BuildContext context) {
    final current = GoRouterState.of(context).matchedLocation;
    final isActive = current == route;
    return TextButton(
      onPressed: () => context.go(route),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 14,
          color: isActive ? _pubBlue : _pubNavy,
          fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}
