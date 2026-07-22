import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pos_connect/shared/widgets/pos_logo.dart';

const _pubNavy  = Color(0xFF1B2A3B);
const _pubBlue  = Color(0xFF0077C5);
const _pubWhite = Colors.white;

class PublicNavBar extends StatelessWidget {
  const PublicNavBar({super.key});

  void _openMobileMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _MobileNavTile(Icons.home_rounded,           'Accueil',         '/home',    context),
            _MobileNavTile(Icons.mail_outline_rounded,   'Contact',         '/contact', context),
            _MobileNavTile(Icons.article_outlined,       'CGU',             '/terms',   context),
            _MobileNavTile(Icons.privacy_tip_outlined,   'Confidentialité', '/privacy', context),
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _pubBlue,
                      side: const BorderSide(color: _pubBlue),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () { Navigator.pop(ctx); context.go('/login'); },
                    child: Text('Se connecter',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _pubBlue,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () { Navigator.pop(ctx); context.go('/register'); },
                    child: Text('S\'inscrire',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

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
                const PosLogo(width: 110),
              ]),
            ),
            const Spacer(),
            // Liens de navigation (cachés sur écran étroit)
            if (!isNarrow) ...[
              _PubNavLink('Accueil',         '/home'),
              _PubNavLink('Contact',         '/contact'),
              _PubNavLink('CGU',             '/terms'),
              _PubNavLink('Confidentialité', '/privacy'),
              const SizedBox(width: 16),
            ],
            // Boutons CTA — écrans larges
            if (!isNarrow) ...[
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
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _pubBlue,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onPressed: () => context.go('/register'),
                child: Text('Créer un compte',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
              ),
            ],
            // Écrans étroits : CTA compact + hamburger
            if (isNarrow) ...[
              if (!isVeryNarrow) ...[
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _pubBlue,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  ),
                  onPressed: () => context.go('/register'),
                  child: Text('S\'inscrire',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
                ),
                const SizedBox(width: 4),
              ],
              IconButton(
                icon: const Icon(Icons.menu_rounded, color: _pubNavy, size: 26),
                tooltip: 'Menu',
                onPressed: () => _openMobileMenu(context),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _MobileNavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String route;
  final BuildContext parentCtx;
  const _MobileNavTile(this.icon, this.label, this.route, this.parentCtx);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: _pubNavy, size: 20),
      title: Text(label,
          style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500, color: _pubNavy)),
      onTap: () {
        Navigator.pop(context);
        parentCtx.go(route);
      },
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
