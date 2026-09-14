// Pilote l'app pour le tuto vidéo Caissier — voir
// scripts/tutorial/generate_tutorial_video.py, qui enregistre l'écran
// pendant l'exécution de ce test et compose la vidéo finale avec la
// narration. Les pauses (Future.delayed) laissent le temps à la voix off
// de chaque étape de se terminer avant l'action suivante — durées lues
// depuis scripts/tutorial/tutorial_scripts.json au moment de la génération,
// répliquées ici en dur pour que le test reste autonome/rejouable seul.
//
// Compte de démo requis (voir scripts/tutorial/seed_demo_data.py) :
//   utilisateur "cassy" / mot de passe "caissierdemo2026"
//   backend accessible en http://127.0.0.1:9003 (voir AppConstants.baseUrl)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_connect/core/constants.dart';
import 'package:pos_connect/main.dart' as app;

Future<void> _wait(WidgetTester tester, Duration d) async {
  await tester.pumpAndSettle();
  await tester.pump(d);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Tuto Caissier — connexion puis écran de caisse',
      (WidgetTester tester) async {
    // Nettoyer uniquement la config serveur persistée par un run précédent
    // sur cette machine (ex: le mode auto-découverte "https://infini-post.local"
    // testé plus tôt cette session) — un prefs.clear() complet réactiverait
    // l'assistant d'installation (clientSetupDoneKey), pas voulu ici.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.serverUrlKey);
    await prefs.remove(AppConstants.serverIpKey);
    await prefs.setBool(AppConstants.clientSetupDoneKey, true);
    await const FlutterSecureStorage().deleteAll();

    app.main();
    await tester.pumpAndSettle();

    // Étape 1 — écran de connexion : laisser le temps à l'auto-découverte
    // mDNS d'échouer (timeout 3s côté app) avant que le formulaire local
    // n'apparaisse.
    await _wait(tester, const Duration(seconds: 8));

    final fields = find.byType(TextFormField);
    expect(fields, findsWidgets);

    // Champ 1 = Nom d'utilisateur, champ 2 = Mot de passe (ordre déclaré
    // dans _buildLocalForm, voir login_screen.dart).
    await tester.enterText(fields.at(0), 'cassy');
    await _wait(tester, const Duration(milliseconds: 800));
    await tester.enterText(fields.at(1), 'caissierdemo2026');
    await _wait(tester, const Duration(seconds: 2));

    final loginBtn = find.text('Se connecter');
    expect(loginBtn, findsOneWidget);
    await tester.tap(loginBtn);
    await _wait(tester, const Duration(seconds: 4));

    // Étape 2 — connecté : le formulaire de connexion a disparu.
    expect(find.text('Se connecter'), findsNothing);
    await _wait(tester, const Duration(seconds: 3));
  });
}
