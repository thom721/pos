import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_connect/core/constants.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/providers/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    FlutterNativeSplash.remove();

    if (kIsWeb) {
      // Web: attendre que authProvider finisse d'initialiser (lecture storage),
      // puis naviguer selon l'état réel — évite la course avec le redirect router.
      while (ref.read(authProvider).isLoading) {
        await Future.delayed(const Duration(milliseconds: 30));
        if (!mounted) return;
      }
      if (!mounted) return;
      if (ref.read(authProvider).isAuthenticated) {
        context.go('/dashboard');
        return;
      }
      // Naviguer immédiatement sans bloquer sur le health check.
      // Le check setup tourne en arrière-plan : si le serveur n'est pas configuré
      // il redirigera vers /install une fois la réponse reçue.
      context.go('/home');
      _checkSetupInBackground();
      return;
    }

    // Non-web (mobile / desktop) : navigation directe, pas d'animation.
    final prefs = await SharedPreferences.getInstance();
    final isMobile = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;

    if (!isMobile && Platform.isWindows) {
      // Sur Windows : vérifier si le serveur a crashé au dernier démarrage.
      final crashed = await _checkServerCrashLog();
      if (crashed != null && mounted) {
        await _showCrashDialog(crashed);
        if (!mounted) return;
      }
    }

    if (isMobile) {
      await prefs.setBool(AppConstants.clientSetupDoneKey, true);
    } else {
      final localSetupDone =
          prefs.getBool(AppConstants.clientSetupDoneKey) ?? false;
      if (!mounted) return;
      if (!localSetupDone) {
        context.go('/install');
        return;
      }
    }

    if (!mounted) return;
    context.go('/dashboard');
  }

  // Lit le crash log du serveur Windows. Retourne le contenu si non vide, null sinon.
  // Le log est dans C:\ProgramData\POS_Connect\posconnect-crash.log (server_main.py).
  Future<String?> _checkServerCrashLog() async {
    try {
      final progData = Platform.environment['PROGRAMDATA'] ?? r'C:\ProgramData';
      final logFile = File('$progData\\POS_Connect\\posconnect-crash.log');
      if (!logFile.existsSync()) return null;
      final content = await logFile.readAsString();
      if (content.trim().isEmpty) return null;
      // Effacer le log après lecture pour ne pas le montrer à chaque démarrage.
      await logFile.writeAsString('');
      return content.trim();
    } catch (_) {
      return null;
    }
  }

  Future<void> _showCrashDialog(String? crashLog) async {
    if (crashLog == null || !mounted) return;
    // Extraire la dernière ligne (résumé de l'erreur)
    final lines = crashLog.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final summary = lines.isNotEmpty ? lines.last : 'Erreur inconnue';
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.error_rounded, color: Colors.redAccent, size: 40),
        title: const Text('Erreur de démarrage du serveur'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Le serveur POS Connect n\'a pas pu démarrer correctement '
              'lors du dernier lancement.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
              ),
              child: Text(
                summary,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Chemin du log complet :\n'
              r'C:\ProgramData\POS_Connect\posconnect-crash.log',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Continuer quand même'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/install');
            },
            child: const Text('Relancer l\'installation'),
          ),
        ],
      ),
    );
  }

  void _checkSetupInBackground() {
    dio.get('/api/setup/health').timeout(const Duration(seconds: 8)).then((res) {
      if (!mounted) return;
      final setupDone = res.data['setup_done'] as bool? ?? true;
      if (!setupDone) context.go('/install');
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(backgroundColor: Color(0xFF1B2A3B));
  }
}
